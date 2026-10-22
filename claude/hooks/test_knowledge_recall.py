# uv run --no-project --with pytest pytest claude/hooks/test_knowledge_recall.py
import json
import os
import subprocess
import sys
from pathlib import Path

HOOK = Path(__file__).with_name("knowledge-recall.py")


def note(dir, slug, title, description, status="draft"):
    (dir / f"{slug}.md").write_text(
        f"---\ntype: Concept\ntitle: '{title}'\ndescription: '{description}'\nstatus: {status}\n---\n\n本文\n\n前提: {slug} の前提\n")


def run(tmp_path, event):
    env = dict(os.environ, KNOWLEDGE_DIR=str(tmp_path / "k"), KNOWLEDGE_RECALL_STATE=str(tmp_path / "state"))
    out = subprocess.run([sys.executable, HOOK], input=json.dumps(event), capture_output=True, text=True, env=env, check=True)
    return json.loads(out.stdout)["hookSpecificOutput"]["additionalContext"] if out.stdout.strip() else ""


def knowledge(tmp_path):
    k = tmp_path / "k"
    k.mkdir()
    # 語の重みはノート数で決まる。実物（約 200 枚）に近づけるため、関係のないノートで数を足す。
    for i in range(30):
        note(k, f"filler-{i}", f"別の話題 {i}", f"関係のない説明 {i}")
    note(k, "omlx-load-failure", "omlx は読み込みの失敗を覚えて 409 を返す", "brew services restart で直る")
    note(k, "docker-compose-volumes", "docker compose の volume は worktree ごとに空", "down -v は共有の volume も消す")
    note(k, "old-omlx", "omlx の古い挙動", "409 を返す", status="deprecated")
    (k / "2026-10-21_omlx-log.md").write_text("---\ntype: Work Log\ntitle: omlx 409\n---\n")
    (k / "index.md").write_text("* [x](docker-compose-volumes.md) - y（別名: named volume, ボリューム）\n")


def prompt(text, session="s"):
    return {"hook_event_name": "UserPromptSubmit", "session_id": session, "prompt": text}


def test_prompt_pulls_matching_concept_with_premise_and_path(tmp_path):
    knowledge(tmp_path)
    ctx = run(tmp_path, prompt("omlx が 409 を返す"))
    assert "omlx は読み込みの失敗を覚えて 409 を返す" in ctx
    assert "前提: omlx-load-failure の前提" in ctx
    assert str(tmp_path / "k" / "omlx-load-failure.md") in ctx
    assert "古い挙動" not in ctx and "docker" not in ctx


def test_unrelated_prompt_injects_nothing(tmp_path):
    knowledge(tmp_path)
    assert run(tmp_path, prompt("それで進めて")) == ""


def test_ascii_terms_do_not_match_inside_words(tmp_path):
    knowledge(tmp_path)
    assert run(tmp_path, prompt("composed volumes")) == ""


def test_home_and_repo_root_in_paths_do_not_match(tmp_path):
    knowledge(tmp_path)
    note(tmp_path / "k", "owner-profile", "YosukeIida の workspace の置き場", "github.com の owner")
    cmd = {"hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Bash",
           "tool_input": {"command": f"ls {Path.home()}/workspace/github.com/YosukeIida/dotfiles"}}
    assert run(tmp_path, cmd) == ""


def test_index_aliases_are_search_keys(tmp_path):
    knowledge(tmp_path)
    assert "docker compose" in run(tmp_path, prompt("named volume のボリュームが消えた"))


def test_same_note_is_not_repeated_until_compaction(tmp_path):
    knowledge(tmp_path)
    assert run(tmp_path, prompt("omlx が 409")) != ""
    assert run(tmp_path, prompt("omlx が 409")) == ""
    run(tmp_path, {"hook_event_name": "SessionStart", "session_id": "s", "source": "compact"})
    assert run(tmp_path, prompt("omlx が 409")) != ""


def test_tool_failure_uses_command_and_error_lines_only(tmp_path):
    knowledge(tmp_path)
    failed = {"hook_event_name": "PostToolUseFailure", "session_id": "s", "tool_name": "Bash",
              "tool_input": {"command": "docker compose down -v"}, "error": "Error: volume in use"}
    assert "docker compose" in run(tmp_path, failed)
    read = {"hook_event_name": "PostToolUse", "session_id": "t", "tool_name": "Read",
            "tool_input": {"file_path": "/x/a.txt"}, "tool_response": "Error: docker compose worktree volume"}
    assert run(tmp_path, read) == ""
