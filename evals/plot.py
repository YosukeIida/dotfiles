#!/usr/bin/env python3
"""集計・プロット: trial*.jsonl を平均し、sweep.md §2-4 のメトリクスとプロットを出す。

使い方（matplotlib が要るので uv 経由で）:
    uv run --with matplotlib python3 evals/plot.py --suite nix-config

出力: evals/results/<suite>/ に
    sweep_tokens.png / sweep_cost.png / sweep_latency.png / sweep_report.html
"""
import argparse
import base64
import io
import json
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

EVALS_DIR = Path(__file__).resolve().parent

COLORS = {"haiku": "#7aa2f7", "sonnet": "#e0af68", "opus": "#f7768e",
          "fable": "#9ece6a"}
EFFORT_ORDER = {"none": 0, "low": 1, "medium": 2, "high": 3, "xhigh": 4, "max": 5}
EFFORT_SIZE = {"none": 9, "low": 7, "medium": 11, "high": 16, "xhigh": 19, "max": 22}


def load_records(suite: str) -> list[dict]:
    rdir = EVALS_DIR / "results" / suite
    # resume で同一セルが複数行あるときは最後の行が正（古い infra 失敗を数えない）
    by_key = {}
    for f in sorted(rdir.glob("trial*.jsonl")):
        for line in f.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                by_key[(r["trial"], r["task_id"], r["model"], r["effort"])] = r
    if not by_key:
        raise SystemExit(f"no results under {rdir}")
    return list(by_key.values())


def aggregate(recs: list[dict]) -> list[dict]:
    """(model, effort) セルごとに trial とタスクを跨いで集計する。"""
    cells = defaultdict(list)
    for r in recs:
        cells[(r["model"], r["effort"])].append(r)
    rows = []
    for (model, effort), rs in sorted(cells.items()):
        ok = [r for r in rs if r["status"] == "ok"]
        infra = [r for r in rs if r["status"] != "ok"]
        if not ok:
            rows.append({"model": model, "effort": effort, "n_ok": 0,
                         "n_infra": len(infra), "pass_rate": None})
            continue
        passes = sum(1 for r in ok if r.get("passed"))
        cost = sum(r.get("cost_usd") or 0 for r in ok)
        # 純粋なモデル生成時間に最も近いのは duration_api_ms（wall はリトライ等を含む）
        secs = sum((r.get("duration_api_ms") or 0) / 1000 for r in ok)
        lats = sorted((r.get("duration_api_ms") or 0) / 1000 for r in ok)
        n = len(ok)
        rows.append({
            "model": model, "effort": effort,
            "n_ok": n, "n_infra": len(infra),
            "pass_rate": passes / n,
            "avg_output_tokens": sum(r.get("output_tokens", 0) for r in ok) / n,
            "cost_per_task": cost / n,
            "cost_per_success": (cost / passes) if passes else float("inf"),
            "secs_per_success": (secs / passes) if passes else float("inf"),
            "p50_latency_s": lats[n // 2],
        })
    return rows


def make_plot(rows, xkey, xlabel, title):
    fig, ax = plt.subplots(figsize=(8, 5.5))
    by_model = defaultdict(list)
    for r in rows:
        if r.get("pass_rate") is not None:
            by_model[r["model"]].append(r)
    for model, pts in by_model.items():
        color = COLORS.get(model, "#888888")
        pts = sorted(pts, key=lambda r: EFFORT_ORDER.get(r["effort"], 9))
        xs = [p[xkey] for p in pts]
        ys = [p["pass_rate"] * 100 for p in pts]
        if len(pts) > 1:
            ax.plot(xs, ys, "-", color=color, label=model, zorder=1)
        else:
            ax.plot(xs, ys, "o", color=color, label=model,
                    markersize=EFFORT_SIZE.get(pts[0]["effort"], 9), zorder=1)
        for p, x, y in zip(pts, xs, ys):
            ax.plot([x], [y], "o", color=color,
                    markersize=EFFORT_SIZE.get(p["effort"], 9),
                    markeredgecolor="white", markeredgewidth=1.2, zorder=2)
    ax.set_xlabel(xlabel)
    ax.set_ylabel("pass rate (%)")
    ax.set_ylim(-5, 105)
    ax.set_title(title)
    leg1 = ax.legend(loc="lower right", title="model")
    ax.add_artist(leg1)
    ax.legend(handles=[plt.Line2D([], [], marker="o", color="grey", ls="",
                                  markersize=EFFORT_SIZE[e], label=f"effort = {e}")
                       for e in ("low", "medium", "high")],
              loc="center left", fontsize=8)
    fig.tight_layout()
    return fig


def fig_to_b64(fig) -> str:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=130)
    return base64.b64encode(buf.getvalue()).decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", required=True)
    args = ap.parse_args()

    recs = load_records(args.suite)
    rows = aggregate(recs)
    rdir = EVALS_DIR / "results" / args.suite

    n_tasks = len({r["task_id"] for r in recs})
    n_trials = len({r["trial"] for r in recs})
    noise_floor = 100 / max(n_tasks * n_trials, 1)

    plots = [
        ("sweep_tokens.png", "avg_output_tokens",
         "avg output tokens per task", f"{args.suite}: quality vs output tokens"),
        ("sweep_cost.png", "cost_per_task",
         "avg cost per task (USD)", f"{args.suite}: quality vs cost"),
        ("sweep_latency.png", "p50_latency_s",
         "p50 model-generation latency (s)", f"{args.suite}: quality vs latency"),
    ]
    imgs = []
    for fname, xkey, xlabel, title in plots:
        fig = make_plot(rows, xkey, xlabel, title)
        fig.savefig(rdir / fname, dpi=130)
        imgs.append(fig_to_b64(fig))
        plt.close(fig)

    def fmt(v):
        if v is None:
            return "-"
        if v == float("inf"):
            return "∞"
        return f"{v:.4g}"

    cols = ["model", "effort", "n_ok", "n_infra", "pass_rate",
            "avg_output_tokens", "cost_per_task", "cost_per_success",
            "secs_per_success", "p50_latency_s"]
    table = "<tr>" + "".join(f"<th>{c}</th>" for c in cols) + "</tr>\n"
    for r in sorted(rows, key=lambda r: (r["model"],
                                         EFFORT_ORDER.get(r["effort"], 9))):
        table += "<tr>" + "".join(f"<td>{fmt(r.get(c)) if not isinstance(r.get(c), str) else r[c]}</td>"
                                  for c in cols) + "</tr>\n"

    html = f"""<!doctype html><meta charset="utf-8">
<title>sweep: {args.suite}</title>
<style>body{{font-family:sans-serif;max-width:960px;margin:2rem auto;padding:0 1rem}}
table{{border-collapse:collapse}}td,th{{border:1px solid #ccc;padding:4px 8px;text-align:right}}
th{{background:#eee}}img{{max-width:100%}}</style>
<h1>Sweep report: {args.suite}</h1>
<p>tasks={n_tasks}, trials={n_trials} — noise floor ≈ {noise_floor:.0f} pt
（この差より小さい pass rate 差は意味を持たない。sweep.md §4）</p>
<table>{table}</table>
{"".join(f'<img src="data:image/png;base64,{b}">' for b in imgs)}
"""
    (rdir / "sweep_report.html").write_text(html)

    print(f"tasks={n_tasks} trials={n_trials} noise_floor≈{noise_floor:.0f}pt")
    for r in sorted(rows, key=lambda r: r.get("cost_per_success") or float("inf")):
        print(f"  {r['model']}/{r['effort']}: pass={fmt(r.get('pass_rate'))}"
              f" cost/success={fmt(r.get('cost_per_success'))}"
              f" secs/success={fmt(r.get('secs_per_success'))}"
              f" (n_ok={r['n_ok']}, infra={r['n_infra']})")
    print(f"→ {rdir / 'sweep_report.html'}")


if __name__ == "__main__":
    main()
