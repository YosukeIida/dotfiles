#!/usr/bin/env python3
"""Sweep runner: model × effort グリッドでタスク suite を headless Claude Code に流す。

方法論は agents/skills/eval-audit-and-sweep/references/sweep.md に従う。
使い方:
    python3 evals/run.py --suite nix-config --trial 1
    python3 evals/run.py --suite nix-config --models haiku,sonnet --efforts low,high --trial 1

結果は evals/results/<suite>/trial<t>.jsonl に1行1レコードで追記される。
完了済み (task, model, effort) セルはスキップされるので再実行で resume できる。
transcript は evals/results/<suite>/transcripts/ に保存される。
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import grade as grader_mod

EVALS_DIR = Path(__file__).resolve().parent

# 子プロセスを親セッションから切り離す（ネストセッション扱いを避ける）
ENV_DROP = [
    "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_CHILD_SESSION",
    "CLAUDE_CODE_BRIDGE_SESSION_ID",
]

DEFAULT_MODELS = ["haiku", "sonnet", "opus"]
DEFAULT_EFFORTS = ["low", "medium", "high"]
# effort パラメータを持たないモデル（sweep.md の Haiku 相当の扱い）。
# 該当モデルは effort グリッドに関わらず1セルだけ走らせ、effort="none" と記録する。
NO_EFFORT_MODELS = {"haiku"}


def clean_env():
    env = dict(os.environ)
    for k in ENV_DROP:
        env.pop(k, None)
    return env


def run_claude(prompt: str, model: str, effort: str, cwd: Path,
               allowed_tools: list[str] | None, timeout: int) -> dict:
    """headless claude を1回実行し、計測値つきレコードを返す。

    infra 失敗（timeout / JSON parse 不能 / is_error）は status で区別し、
    model の pass/fail と混ぜない（audit.md §2）。
    """
    cmd = [
        "claude", "-p",
        "--model", model,
        "--output-format", "json",
        # eval と無関係な MCP サーバ・plugin 由来の context を落として条件を揃える
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
    ]
    if effort != "none":
        cmd += ["--effort", effort]
    if allowed_tools:
        cmd += ["--allowedTools", ",".join(allowed_tools),
                "--permission-mode", "acceptEdits"]
    t0 = time.monotonic()
    try:
        proc = subprocess.run(
            cmd, input=prompt, capture_output=True, text=True,
            cwd=str(cwd), env=clean_env(), timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "wall_seconds": round(time.monotonic() - t0, 2)}
    wall = round(time.monotonic() - t0, 2)
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {
            "status": "infra_error", "wall_seconds": wall,
            "detail": {"stdout": proc.stdout[-2000:], "stderr": proc.stderr[-2000:]},
        }
    if data.get("is_error"):
        return {"status": "infra_error", "wall_seconds": wall,
                "detail": {"result": data.get("result", "")[:2000]}}
    usage = data.get("usage", {})
    return {
        "status": "ok",
        "result": data.get("result", ""),
        "wall_seconds": wall,
        "duration_api_ms": data.get("duration_api_ms"),
        "ttft_ms": data.get("ttft_ms"),
        "num_turns": data.get("num_turns"),
        "input_tokens": usage.get("input_tokens", 0),
        "output_tokens": usage.get("output_tokens", 0),
        "cache_read_tokens": usage.get("cache_read_input_tokens", 0),
        "cache_write_tokens": usage.get("cache_creation_input_tokens", 0),
        "cost_usd": data.get("total_cost_usd"),
        # --model の alias がどのモデルに解決されたかの証跡
        "resolved_models": list(data.get("modelUsage", {}).keys()),
        "session_id": data.get("session_id"),
    }


def load_tasks(suite: str, only: list[str] | None) -> list[dict]:
    suite_dir = EVALS_DIR / "suites" / suite
    tasks_dir = suite_dir / "tasks"
    if not tasks_dir.is_dir():
        sys.exit(f"error: no tasks dir at {tasks_dir}")
    tasks = []
    for td in sorted(tasks_dir.iterdir()):
        meta_path = td / "task.json"
        if not meta_path.is_file():
            continue
        meta = json.loads(meta_path.read_text())
        meta["_dir"] = td
        meta.setdefault("id", td.name)
        if only and meta["id"] not in only:
            continue
        tasks.append(meta)
    if not tasks:
        sys.exit(f"error: no tasks matched in {tasks_dir}")
    return tasks


def cell_key(task_id: str, model: str, effort: str) -> str:
    return f"{task_id}|{model}|{effort}"


def load_done(results_path: Path) -> set[str]:
    done = set()
    if results_path.is_file():
        for line in results_path.read_text().splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            # infra 失敗は再実行対象にする（audit.md: retry transient errors）
            if r.get("status") == "ok":
                done.add(cell_key(r["task_id"], r["model"], r["effort"]))
    return done


def run_one(task: dict, model: str, effort: str, args, transcripts_dir: Path) -> dict:
    task_dir: Path = task["_dir"]
    prompt = (task_dir / task.get("prompt_file", "prompt.md")).read_text()

    workspace = Path(tempfile.mkdtemp(prefix=f"eval-{task['id']}-"))
    try:
        fixture = task_dir / "fixture"
        if fixture.is_dir():
            shutil.copytree(fixture, workspace, dirs_exist_ok=True)

        allowed_tools = task.get("allowed_tools")  # 例: ["Read","Edit","Write","Glob","Grep"]
        rec = run_claude(prompt, model, effort, workspace,
                         allowed_tools, args.timeout)
        rec.update({"suite": args.suite, "task_id": task["id"],
                    "model": model, "effort": effort, "trial": args.trial})

        if rec["status"] == "ok":
            verdict = grader_mod.grade(task, workspace, rec.get("result", ""),
                                       judge_model=args.judge_model)
            rec["grader"] = verdict
            if verdict.get("grader_error"):
                # grader 自体の故障はモデルの fail に数えない（resume で再実行される）
                rec["status"] = "grader_error"
            else:
                rec["passed"] = verdict["passed"]

        # transcript 保存（audit.md: 最もレバレッジの高い習慣）
        tpath = transcripts_dir / f"{task['id']}.{model}.{effort}.trial{args.trial}.json"
        tpath.write_text(json.dumps(rec, ensure_ascii=False, indent=2))
        return rec
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", required=True)
    ap.add_argument("--models", default=",".join(DEFAULT_MODELS))
    ap.add_argument("--efforts", default=",".join(DEFAULT_EFFORTS))
    ap.add_argument("--trial", type=int, default=1)
    ap.add_argument("--tasks", help="comma-separated task ids (default: all)")
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--timeout", type=int, default=600, help="per-call seconds")
    ap.add_argument("--judge-model", default="opus",
                    help="LLM-judge 用モデル（被験セルと独立に固定する）")
    args = ap.parse_args()

    models = [m.strip() for m in args.models.split(",") if m.strip()]
    efforts = [e.strip() for e in args.efforts.split(",") if e.strip()]
    only = [t.strip() for t in args.tasks.split(",")] if args.tasks else None
    tasks = load_tasks(args.suite, only)

    results_dir = EVALS_DIR / "results" / args.suite
    transcripts_dir = results_dir / "transcripts"
    transcripts_dir.mkdir(parents=True, exist_ok=True)
    results_path = results_dir / f"trial{args.trial}.jsonl"
    done = load_done(results_path)

    cells = []
    for m in models:
        for e in (["none"] if m in NO_EFFORT_MODELS else efforts):
            for t in tasks:
                if cell_key(t["id"], m, e) not in done:
                    cells.append((t, m, e))
    print(f"suite={args.suite} trial={args.trial}: "
          f"{len(cells)} runs to do ({len(done)} already done)")

    with results_path.open("a") as out, \
         ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futs = {pool.submit(run_one, t, m, e, args, transcripts_dir): (t["id"], m, e)
                for (t, m, e) in cells}
        for fut in as_completed(futs):
            tid, m, e = futs[fut]
            try:
                rec = fut.result()
            except Exception as exc:  # runner 自体のバグはここに出る
                rec = {"suite": args.suite, "task_id": tid, "model": m,
                       "effort": e, "trial": args.trial,
                       "status": "runner_error", "detail": {"error": repr(exc)}}
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            out.flush()
            mark = {"ok": "✓" if rec.get("passed") else "✗",
                    }.get(rec["status"], "!")
            print(f"  [{mark}] {tid} {m}/{e} status={rec['status']}"
                  f" passed={rec.get('passed')} cost={rec.get('cost_usd')}")

    print(f"done → {results_path}")


if __name__ == "__main__":
    main()
