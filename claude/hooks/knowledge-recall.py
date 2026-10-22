# /// script
# requires-python = ">=3.11"
# ///
"""knowledge の概念ノートを、作業中に出た語から引いて agent の文脈に差し込む hook（Claude Code・Codex 共通）。

UserPromptSubmit は送った文、PostToolUse / PostToolUseFailure は触ったパス・コマンド・エラーの行から探す。
SessionStart（compact）では、そのセッションで差し込んだ記録を消し、要約で落ちたノートをまた差し込めるようにする。
agent に「探すかどうか」を判断させると探さない（knowledge の agent-index-always-loaded.md）ので、毎回こちらで探す。
"""

import hashlib
import json
import math
import os
import re
import sys
import time
from pathlib import Path

KNOWLEDGE = Path(os.environ.get("KNOWLEDGE_DIR", Path.home() / "workspace/github.com/YosukeIida/knowledge"))
STATE = Path(os.environ.get("KNOWLEDGE_RECALL_STATE", Path.home() / ".local/state/knowledge-recall"))
# Codex は約 2,500 トークンを超える hook の出力をファイルに逃がすので、日本語 1 文字 ≒ 1 トークンとして下回らせる。
BUDGET = 2000
TOP = 3
MIN_SCORE = 2.5
QUERY_MAX = 4000

TERM = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.\-]{2,}|[ァ-ヴー]{3,}|[一-龥々]{2,}")
# 1 位の何割までを差し込むか。似た題のノートが同点で並ぶと、関係の薄いものまで入る。
RELATIVE = 0.6
ERROR_LINE = re.compile(r"error|exception|traceback|failed|denied|not found|unavailable|エラー|失敗", re.I)
REPO_ROOT = re.compile(r"~/workspace/github\.com/[^/\s]+/")
ALIASES = re.compile(r"^\* \[[^\]]*\]\(([^)]+)\.md\).*（別名: ([^）]*)）", re.M)


def frontmatter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}, text
    fields = {}
    for line in m.group(1).splitlines():
        k, sep, v = line.partition(":")
        if sep and not line.startswith(" "):
            fields[k.strip()] = v.strip().strip("'\"")
    return fields, text[m.end():]


def load_notes():
    aliases = {}
    index = KNOWLEDGE / "index.md"
    if index.exists():
        for slug, words in ALIASES.findall(index.read_text()):
            aliases[slug] = words
    notes = []
    for path in sorted(KNOWLEDGE.glob("[a-z]*.md")):
        fields, body = frontmatter(path.read_text())
        if fields.get("type") != "Concept" or fields.get("status") == "deprecated":
            continue
        premise = next((l for l in body.splitlines() if l.startswith("前提")), "")
        keys = " ".join([fields.get("title", ""), fields.get("description", ""), aliases.get(path.stem, ""),
                         path.stem.replace("-", " ")])
        terms = {t.lower() for t in TERM.findall(keys)}
        notes.append({"slug": path.stem, "path": str(path), "title": fields.get("title", path.stem),
                      "description": fields.get("description", ""), "premise": premise, "terms": terms})
    return notes


def query_text(event):
    name = event.get("hook_event_name", "")
    if name == "UserPromptSubmit":
        return event.get("prompt", "")
    parts = []
    tool_input = event.get("tool_input") or {}
    if isinstance(tool_input, dict):
        parts += [str(tool_input.get(k, "")) for k in ("file_path", "path", "command", "pattern", "url")]
    # 成功した道具の出力（読んだファイル・書き換えた中身・テストの出力）で探すと、その中の語に引きずられる。
    # 出力は失敗したときのエラーの行だけを使う。
    if name == "PostToolUseFailure":
        parts += [l for l in str(event.get("error", "")).splitlines() if ERROR_LINE.search(l)][:20]
    return "\n".join(parts)


def rank(notes, query):
    # どのコマンドにも出るホームと repo の置き場（/Users/<名前>/workspace/github.com/<owner>/）で当てない。
    q = REPO_ROOT.sub("/", query.replace(str(Path.home()), "~")).lower()[:QUERY_MAX]
    df = {}
    for n in notes:
        for t in n["terms"]:
            df[t] = df.get(t, 0) + 1
    scored = []
    for n in notes:
        hits = [t for t in n["terms"] if contains(q, t)]
        score = sum(math.log(len(notes) / df[t]) for t in hits)
        if score >= MIN_SCORE and len(hits) >= 2:
            scored.append((score, n, hits))
    scored.sort(key=lambda s: -s[0])
    return [s for s in scored[:TOP] if s[0] >= scored[0][0] * RELATIVE]


def contains(q, term):
    # 英数字の語は前後が英数字でないときだけ当てる（compose の中の omp を拾わない）。日本語は語の境目が無いので部分一致。
    if term.isascii():
        return re.search(rf"(?<![a-z0-9]){re.escape(term)}(?![a-z0-9])", q) is not None
    return term in q


def render(picked):
    out, slugs, used = [], [], 0
    for _, n, _ in picked:
        block = f"- {n['title']}\n  {n['description']}\n  {n['premise']}\n  本文: {n['path']}"
        if used + len(block) > BUDGET:
            break
        out.append(block)
        slugs.append(n["slug"])
        used += len(block)
    if not out:
        return "", []
    return ("knowledge（repo をまたぐ理解のノート）から、いまの作業に関係しそうなものを自動で差し込んだ。"
            "当てはまるときは本文を読んでから判断する。当てはまらなければ無視してよい。\n" + "\n".join(out)), slugs


def main():
    event = json.load(sys.stdin)
    name = event.get("hook_event_name", "")
    session = re.sub(r"[^A-Za-z0-9_-]", "", str(event.get("session_id", "unknown"))) or "unknown"
    seen_file = STATE / "sessions" / f"{session}.json"
    if name == "SessionStart":
        seen_file.unlink(missing_ok=True)
        return
    query = query_text(event)
    if not query.strip():
        return
    seen = set(json.loads(seen_file.read_text())) if seen_file.exists() else set()
    candidates = rank(load_notes(), query)
    picked = [c for c in candidates if c[1]["slug"] not in seen]
    context, injected = render(picked)
    STATE.mkdir(parents=True, exist_ok=True)
    with open(STATE / "log.jsonl", "a") as log:
        log.write(json.dumps({"ts": int(time.time()), "event": name, "session": session, "tool": event.get("tool_name"),
                              "query": hashlib.sha256(query.encode()).hexdigest()[:12],
                              "candidates": [[c[1]["slug"], round(c[0], 2), sorted(c[2])] for c in candidates],
                              "injected": injected}, ensure_ascii=False) + "\n")
    if not context:
        return
    seen_file.parent.mkdir(parents=True, exist_ok=True)
    seen_file.write_text(json.dumps(sorted(seen | set(injected))))
    print(json.dumps({"hookSpecificOutput": {"hookEventName": name, "additionalContext": context}}, ensure_ascii=False))


if __name__ == "__main__":
    main()
