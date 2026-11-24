#!/usr/bin/env python3
"""原文と直した文の意味のズレ検出・自動復旧・読点整理をまとめて扱う CLI。

使い方:
    python3 nihongo/scripts/cli.py diff <orig> <draft> [--request <req>] [--profile <path>] [--scene {casual,work,formal}] [--json]
    python3 nihongo/scripts/cli.py fix <orig> <draft> <out> [--request <req>] [--no-trim-commas] [--fail-on-remaining]
    python3 nihongo/scripts/cli.py git [--base HEAD] [--staged] [--ext .md,.txt] [--request <req>] [--profile <path>] [--scene {casual,work,formal}] [--hook] [--json] [paths...]

標準ライブラリだけで動く。pyproject.toml からインストールした場合は `nihongo-check` として実行できる。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import unicodedata

__version__ = "3.1.1"

if __package__:
    from . import inbox as inbox_mod
    from . import revert_broken, trim_commas
else:
    _SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    if _SCRIPT_DIR not in sys.path:
        sys.path.insert(0, _SCRIPT_DIR)
    import inbox as inbox_mod  # noqa: E402
    import revert_broken  # noqa: E402
    import trim_commas  # noqa: E402


def _ensure_utf8_stdio() -> None:
    """Windows 環境でも UTF-8 で安全に標準出力・標準エラー出力へ書けるようにする。"""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass


def _read_utf8(path: str) -> str:
    with open(path, encoding="utf-8-sig") as f:
        return f.read()


def _load_request(req_arg: str | None) -> str:
    """--request に渡された値を読み込む。既存ファイルなら中身を読み、そうでなければ文字列として扱う。"""
    if not req_arg:
        return ""
    try:
        if os.path.isfile(req_arg):
            return _read_utf8(req_arg)
    except OSError:
        pass
    return req_arg


def _normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


_PROFILE_HEADING_RE = re.compile(r"^\s*#{1,6}\s+(.+?)\s*$")
_PROFILE_SCENE_RE = re.compile(r"\[(common|casual|work|formal)\]", re.IGNORECASE)
_FORBIDDEN_LINE_RE = re.compile(
    r"^\s*(?:[-*・]\s*)?(?:\*\*)?絶対に言わない表現(?:\*\*)?\s*[：:]\s*(.*)$"
)
_PLACEHOLDER_PAREN_RE = re.compile(
    r"[（(]\s*(?:例|記入例|未記入)\s*(?:[：:][^）)]*)?[）)]"
)
_PLACEHOLDER_PREFIX_RE = re.compile(r"^(?:例|記入例|未記入)\s*[：:]")
# 公式例の「A」「B」にも区切りを補う。括弧で囲んだ語の中の読点やスラッシュは語の一部。
_ADJACENT_QUOTES_RE = re.compile(r"(?<=[」』])\s*(?=[「『])")
_FORBIDDEN_ITEM_RE = re.compile(r"(?:「[^」]*」|『[^』]*』|[^、,／/・])+")
_SKIP_FORBIDDEN_TOKENS = frozenset({"", "...", "…", "-", "—", "なし", "特になし"})

_CASUAL_SSU_RE = re.compile(r"っす(?![ぐうる])")
_CASUAL_LAUGH_RE = re.compile(
    r"(?:(?<![A-Za-z0-9./])[wｗ]{2,}(?![A-Za-z0-9./])|(?<![A-Za-z0-9])[wｗ](?=$|[\s。、！？!?\n]))"
)
# 業務記号（✓✔✕★☆☐☑ 等）を誤検知しないよう、顔文字・絵文字レンジと代表絵文字記号に絞る
_EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\u2728\u2764\u2763\u2757\u2753\u2600\u2601\u2614\u26A1\u2615]")


def _split_forbidden_rhs(rhs: str) -> list[str]:
    """「...」や "..." の内側にある読点・中黒では分割せず、外側の区切り文字だけで分割する。"""
    quote_pairs = {"「": "」", "『": "』", '"': '"', "'": "'", "“": "”"}
    seps = set("、,／/・")
    tokens: list[str] = []
    buf: list[str] = []
    closing: str | None = None
    for ch in rhs:
        if closing is not None:
            buf.append(ch)
            if ch == closing:
                closing = None
            continue
        if ch in quote_pairs:
            closing = quote_pairs[ch]
            buf.append(ch)
            continue
        if ch in seps:
            piece = "".join(buf).strip()
            if piece:
                tokens.append(piece)
            buf = []
            continue
        buf.append(ch)
    tail = "".join(buf).strip()
    if tail:
        tokens.append(tail)
    return tokens


def _clean_forbidden_token(raw: str) -> str:
    token = raw.strip(" \t\r\n\u3000")
    if not token or _PLACEHOLDER_PREFIX_RE.match(token):
        return ""
    if token.startswith(("（例", "(例", "（記入例", "(記入例", "（未記入", "(未記入")):
        return ""
    while len(token) >= 2 and (
        (token[0] == "「" and token[-1] == "」")
        or (token[0] == "『" and token[-1] == "』")
        or (token[0] == '"' and token[-1] == '"')
        or (token[0] == "'" and token[-1] == "'")
        or (token[0] == "“" and token[-1] == "”")
    ):
        token = token[1:-1].strip(" \t\r\n\u3000")
    token = token.strip(" \t\r\n\u3000\"'「」『』“”〜～")
    if not token or _PLACEHOLDER_PREFIX_RE.match(token) or token in _SKIP_FORBIDDEN_TOKENS:
        return ""
    return token


def parse_profile_text(raw_text: str, scene: str | None = None) -> list[str]:
    """profile.md のテキストから「絶対に言わない表現」の一覧を抽出する。"""
    text = _normalize_newlines(raw_text)
    common_items: list[str] = []
    scoped_items: dict[str, list[str]] = {}
    current_section: str | None = None

    for line in text.split("\n"):
        heading = _PROFILE_HEADING_RE.match(line)
        if heading:
            scene_m = _PROFILE_SCENE_RE.search(heading.group(1))
            current_section = scene_m.group(1).lower() if scene_m else None
            continue

        m = _FORBIDDEN_LINE_RE.match(line)
        if not m:
            continue

        rhs = _PLACEHOLDER_PAREN_RE.sub("", m.group(1)).strip()
        if not rhs:
            continue

        parsed: list[str] = []
        for raw_token in _split_forbidden_rhs(_ADJACENT_QUOTES_RE.sub("、", rhs)):
            cleaned = _clean_forbidden_token(raw_token)
            if cleaned:
                parsed.append(cleaned)

        if not parsed:
            continue

        if current_section is None or current_section == "common":
            common_items.extend(parsed)
        else:
            scoped_items.setdefault(current_section, []).extend(parsed)

    combined: list[str] = list(common_items)
    if scene is not None:
        combined.extend(scoped_items.get(scene.lower(), []))
    elif not common_items:
        for items in scoped_items.values():
            combined.extend(items)

    deduped: list[str] = []
    seen: set[str] = set()
    for item in combined:
        if item not in seen:
            seen.add(item)
            deduped.append(item)
    return deduped


def parse_profile(path: str, scene: str | None = None) -> list[str]:
    """profile.md から「絶対に言わない表現」の一覧を抽出する。"""
    return parse_profile_text(_read_utf8(os.path.expanduser(path)), scene=scene)


def check_profile_drift(
    orig: str,
    draft: str,
    forbidden: list[str],
    scene: str | None = None,
) -> list[str]:
    """原文から直した文への変更で、個人ルール違反や formal 場面の崩し表現が増えていないか調べる。"""
    findings: list[str] = []
    orig_norm = unicodedata.normalize("NFKC", _normalize_newlines(orig))
    draft_norm = unicodedata.normalize("NFKC", _normalize_newlines(draft))

    seen_forbidden: set[str] = set()
    for w in forbidden:
        if not w or w in seen_forbidden:
            continue
        seen_forbidden.add(w)
        w_norm = unicodedata.normalize("NFKC", w)
        if not w_norm:
            continue
        if draft_norm.count(w_norm) > orig_norm.count(w_norm):
            findings.append(f"[個人ルール] 避ける表現を検出: 「{w}」")

    if scene == "formal":
        orig_text = _normalize_newlines(orig)
        draft_text = _normalize_newlines(draft)
        casual_checks = (
            (_CASUAL_SSU_RE, "「っす」"),
            (_CASUAL_LAUGH_RE, "「w」"),
            (_EMOJI_RE, "絵文字"),
        )
        for pattern, label in casual_checks:
            if len(pattern.findall(draft_text)) > len(pattern.findall(orig_text)):
                findings.append(f"[場面ガード] formal 場面で崩し表現を検出: {label}")

    return findings


def _format_finding(item: str) -> str:
    """check_meaning.py の内部メッセージを CLI 表示向けに整える（既存ロジックは無変更）。"""
    replacements = (
        ("[確かさ・強さ]", "[確度・必須度]"),
        ("原文にあって直した文で減ったもの:", "削除（原文のみ）:"),
        ("直した文で増えたもの:", "追加（編集後のみ）:"),
        ("の言い方が減った", "表現が減少"),
        ("の言い方が増えた", "表現が増加"),
        ("」が減った", "」が減少"),
        ("」が増えた", "」が増加"),
        ("否定の表現が減った", "否定表現が減少"),
        ("否定の表現が増えた", "否定表現が増加"),
    )
    out = item
    for old, new in replacements:
        out = out.replace(old, new)
    return out


def _parse_extensions(ext_arg: str) -> tuple[str, ...]:
    exts = []
    for raw in ext_arg.split(","):
        item = raw.strip().lower()
        if not item:
            continue
        if not item.startswith("."):
            item = "." + item
        if item not in exts:
            exts.append(item)
    return tuple(exts)


def _matches_ext(path: str, exts: tuple[str, ...]) -> bool:
    if not exts:
        return True
    lower = path.lower()
    return any(lower.endswith(ext) for ext in exts)


def _read_hook_file_path() -> str | None:
    """--hook 時に標準入力の JSON から対象ファイルパスを安全に取り出す。"""
    try:
        if sys.stdin is None or sys.stdin.isatty():
            return None
        if hasattr(sys.stdin, "buffer"):
            raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
        else:
            raw = sys.stdin.read()
    except Exception:
        return None
    if not raw or not raw.strip():
        return None
    try:
        data = json.loads(raw)
    except Exception:
        return None
    if not isinstance(data, dict):
        return None

    tool_input = data.get("tool_input")
    if isinstance(tool_input, dict):
        for key in ("file_path", "path", "TargetFile", "Path"):
            val = tool_input.get(key)
            if isinstance(val, str) and val.strip():
                return val.strip()
    for key in ("file_path", "path", "TargetFile", "Path"):
        val = data.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return None


def _run_git(args: list[str], cwd: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def _find_git_root(probe_dir: str) -> str | None:
    try:
        proc = _run_git(["rev-parse", "--show-toplevel"], cwd=probe_dir)
    except FileNotFoundError:
        return None
    if proc.returncode != 0:
        return None
    root = proc.stdout.decode("utf-8", errors="replace").strip()
    return os.path.realpath(root) if root else None


def _to_repo_relpath(path: str, repo_root: str) -> str | None:
    abs_path = os.path.realpath(os.path.abspath(path))
    abs_root = os.path.realpath(os.path.abspath(repo_root))
    try:
        common = os.path.commonpath([abs_root, abs_path])
    except ValueError:
        return None
    if os.path.normcase(common) != os.path.normcase(abs_root):
        return None
    rel = os.path.relpath(abs_path, abs_root)
    if rel == ".":
        return "."
    return rel.replace(os.sep, "/")


def _git_changed_files(
    repo_root: str,
    base: str,
    staged: bool,
) -> dict[str, str]:
    """変更先のパスから、比較元コミットでのパスを引けるようにする。"""
    cmd = ["diff", "-z", "--name-status", "--find-renames", "--diff-filter=MR"]
    if staged:
        cmd.append("--cached")
    cmd.append(base)
    cmd.append("--")
    proc = _run_git(cmd, cwd=repo_root)
    if proc.returncode != 0:
        return {}
    out: dict[str, str] = {}
    fields = iter(proc.stdout.split(b"\x00")[:-1])
    for status in fields:
        old = next(fields)
        new = next(fields) if status.startswith(b"R") else old
        try:
            out[new.decode("utf-8")] = old.decode("utf-8")
        except UnicodeDecodeError:
            continue
    return out


def _git_show_utf8(repo_root: str, spec: str) -> str | None:
    proc = _run_git(["show", spec], cwd=repo_root)
    if proc.returncode != 0:
        return None
    try:
        return proc.stdout.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _read_working_tree_utf8(repo_root: str, posix_rel: str) -> str | None:
    full_path = os.path.join(repo_root, *posix_rel.split("/"))
    try:
        with open(full_path, "rb") as f:
            raw = f.read()
    except OSError:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


def cmd_diff(args: argparse.Namespace) -> int:
    try:
        src = _read_utf8(args.orig)
        dst = _read_utf8(args.draft)
    except (OSError, UnicodeDecodeError) as exc:
        print(f"ファイルを読み込めませんでした: {exc}", file=sys.stderr)
        return 2

    forbidden: list[str] = []
    if args.profile:
        try:
            forbidden = parse_profile(args.profile, scene=args.scene)
        except (OSError, UnicodeDecodeError) as exc:
            print(f"プロフィールファイルを読み込めませんでした: {exc}", file=sys.stderr)
            return 2
    elif getattr(args, "auto_profile", False):
        store = inbox_mod.LocalFileStorage(home=getattr(args, "home", None))
        proj_dir = getattr(args, "project", None) or os.path.dirname(os.path.abspath(args.draft))
        info = inbox_mod.read_profile(storage=store, project_dir=proj_dir, include_project=True)
        if info["exists"]:
            forbidden = parse_profile_text(info["raw"], scene=args.scene)

    request = _load_request(args.request)
    items = revert_broken.remaining(src, dst, request)
    if forbidden or args.scene:
        items = items + check_profile_drift(src, dst, forbidden, scene=args.scene)
    items = [_format_finding(x) for x in items]

    if args.json:
        payload = {
            "orig": args.orig,
            "draft": args.draft,
            "clean": len(items) == 0,
            "count": len(items),
            "findings": items,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        if not items:
            print("見直す候補はありません。")
        else:
            print(f"見直す候補が{len(items)}件あります。直した文の該当箇所を原文と読み比べてください。")
            for item in items:
                print("- " + item)

    return 1 if items else 0


def cmd_fix(args: argparse.Namespace) -> int:
    try:
        src = _read_utf8(args.orig)
        dst = _read_utf8(args.draft)
    except (OSError, UnicodeDecodeError) as exc:
        print(f"ファイルを読み込めませんでした: {exc}", file=sys.stderr)
        return 2

    request = _load_request(args.request)
    logs: list[str] = []
    rest = revert_broken.remaining(src, dst, request)
    n = len(rest)
    for _ in range(6):
        new, log = revert_broken.one_pass(src, dst, request, rest)
        next_rest = revert_broken.remaining(src, new, request)
        m = len(next_rest)
        if not log or m >= n:
            break
        dst, n = new, m
        rest = next_rest
        logs += log

    comma_logs: list[str] = []
    if not args.no_trim_commas:
        dst, comma_logs = trim_commas.trim(dst)

    try:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(dst)
    except OSError as exc:
        print(f"出力ファイルを書き込めませんでした: {exc}", file=sys.stderr)
        return 2

    if logs:
        print(f"{len(logs)}か所を原文に戻しました。")
        for entry in logs:
            print("- " + entry)
    else:
        print("戻した所はありません。")

    if not args.no_trim_commas:
        if comma_logs:
            print(f"{len(comma_logs)}か所の読点を外しました。")
            for entry in comma_logs:
                print("- " + entry)
        else:
            print("外した読点はありません。")

    if rest:
        print(f"残っている候補が{len(rest)}件あります（読み比べて、同じ意味ならそのままでよい）：")
        for item in rest:
            print("- " + _format_finding(item))

    if args.fail_on_remaining and rest:
        return 1
    return 0


def cmd_git(args: argparse.Namespace) -> int:
    exts = _parse_extensions(args.ext)
    request = _load_request(args.request)
    hook_path: str | None = None

    if args.hook:
        hook_path = _read_hook_file_path()
        if hook_path is not None:
            if not _matches_ext(hook_path, exts):
                if args.json:
                    print(json.dumps({
                        "base": args.base,
                        "staged": args.staged,
                        "clean": True,
                        "checked": 0,
                        "flagged": 0,
                        "files": [],
                    }, ensure_ascii=False, indent=2))
                return 0

    forbidden: list[str] = []
    if args.profile:
        try:
            forbidden = parse_profile(args.profile, scene=args.scene)
        except (OSError, UnicodeDecodeError) as exc:
            if not args.hook:
                print(f"プロフィールファイルを読み込めませんでした: {exc}", file=sys.stderr)
                return 2
            forbidden = []
    elif getattr(args, "auto_profile", False):
        store = inbox_mod.LocalFileStorage(home=getattr(args, "home", None))
        proj_dir = getattr(args, "project", None) or (
            os.path.dirname(os.path.abspath(hook_path)) if hook_path else os.getcwd()
        )
        info = inbox_mod.read_profile(storage=store, project_dir=proj_dir, include_project=True)
        if info["exists"]:
            forbidden = parse_profile_text(info["raw"], scene=args.scene)

    probe_dir = os.getcwd()
    if hook_path is not None:
        candidate_dir = os.path.dirname(os.path.abspath(hook_path))
        if os.path.isdir(candidate_dir):
            probe_dir = candidate_dir
    elif args.paths:
        first_abs = os.path.abspath(args.paths[0])
        candidate_dir = first_abs if os.path.isdir(first_abs) else os.path.dirname(first_abs)
        if os.path.isdir(candidate_dir):
            probe_dir = candidate_dir

    repo_root = _find_git_root(probe_dir)
    if repo_root is None:
        if args.hook:
            return 0
        print("git リポジトリの中で実行してください。", file=sys.stderr)
        return 2

    verify = _run_git(["rev-parse", "--verify", "--quiet", f"{args.base}^{{commit}}"], cwd=repo_root)
    if verify.returncode != 0:
        if args.hook:
            return 0
        print(f"比較元のコミットが見つかりません: {args.base}", file=sys.stderr)
        return 2

    # パスで絞ってから diff を取ると、別ディレクトリからの移動を追加と誤認する。
    sources = _git_changed_files(repo_root, args.base, args.staged)
    targets: list[str] = []
    seen: set[str] = set()

    def _add_target(rel: str) -> None:
        if rel not in seen and _matches_ext(rel, exts):
            seen.add(rel)
            targets.append(rel)

    explicit_paths = [hook_path] if hook_path is not None else list(args.paths)
    if explicit_paths:
        dir_specs: list[str] = []
        for raw_path in explicit_paths:
            rel = _to_repo_relpath(raw_path, repo_root)
            if rel is None:
                continue
            abs_p = os.path.abspath(raw_path)
            if rel == "." or os.path.isdir(abs_p):
                if rel != ".":
                    dir_specs.append(rel)
                else:
                    for changed in sources:
                        _add_target(changed)
            else:
                _add_target(rel)
        if dir_specs:
            for changed in sources:
                if any(changed.startswith(directory + "/") for directory in dir_specs):
                    _add_target(changed)
    else:
        for changed in sources:
            _add_target(changed)

    checked = 0
    flagged_files: list[dict[str, object]] = []

    for rel in targets:
        orig_raw = _git_show_utf8(repo_root, f"{args.base}:{sources.get(rel, rel)}")
        if orig_raw is None:
            continue
        if args.staged:
            curr_raw = _git_show_utf8(repo_root, f":{rel}")
        else:
            curr_raw = _read_working_tree_utf8(repo_root, rel)
        if curr_raw is None:
            continue

        checked += 1
        orig = _normalize_newlines(orig_raw)
        curr = _normalize_newlines(curr_raw)
        if orig == curr:
            continue

        findings = revert_broken.remaining(orig, curr, request)
        if forbidden or args.scene:
            findings = findings + check_profile_drift(orig, curr, forbidden, scene=args.scene)
        findings = [_format_finding(x) for x in findings]
        if findings:
            flagged_files.append({
                "path": rel,
                "count": len(findings),
                "findings": findings,
            })

    total_findings = sum(int(entry["count"]) for entry in flagged_files)

    if args.json:
        payload = {
            "base": args.base,
            "staged": args.staged,
            "clean": len(flagged_files) == 0,
            "checked": checked,
            "flagged": len(flagged_files),
            "files": flagged_files,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))

    if args.hook:
        if flagged_files:
            lines = [f"nihongo-check: 意味が変わった可能性がある箇所を検出しました（base: {args.base}）"]
            for entry in flagged_files:
                lines.append(f"[{entry['path']}] ({entry['count']}件)")
                for item in entry["findings"]:  # type: ignore[union-attr]
                    lines.append(f"- {item}")
            lines.append("原文と読み比べ、意図しない変更があれば元に戻してください。")
            print("\n".join(lines), file=sys.stderr)
            return 2
        return 0

    if not args.json:
        if flagged_files:
            print(f"意味が変わったかもしれない箇所が {len(flagged_files)} ファイル（{total_findings}件）見つかりました（base: {args.base}）。")
            for entry in flagged_files:
                print(f"\n[{entry['path']}] {entry['count']}件")
                for item in entry["findings"]:  # type: ignore[union-attr]
                    print("- " + item)
        elif checked == 0:
            print("チェック対象の変更ファイルはありません。")
        else:
            print(f"{checked}件のファイルを確認しました。見直す候補はありません。")

    return 1 if flagged_files else 0


def _cli_storage(args: argparse.Namespace) -> inbox_mod.LocalFileStorage:
    return inbox_mod.LocalFileStorage(
        home=getattr(args, "home", None),
        profile_path=getattr(args, "profile", None),
        inbox_path=getattr(args, "inbox", None),
    )


def cmd_inbox_propose(args: argparse.Namespace) -> int:
    store = _cli_storage(args)
    try:
        res = inbox_mod.propose_entry(
            scene=args.scene,
            kind=args.kind,
            value=args.value,
            reason=args.reason,
            example_before=args.before,
            example_after=args.after,
            source=args.source,
            storage=store,
        )
    except ValueError as exc:
        if args.json:
            print(json.dumps({"error": str(exc)}, ensure_ascii=False, indent=2))
        else:
            print(f"エラー: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(res["message"])
        if res.get("warning"):
            print(res["warning"])
        if res.get("already_in_profile"):
            print("※似た表現がすでに profile.md に含まれている可能性があります。")
    return 0


def cmd_inbox_list(args: argparse.Namespace) -> int:
    store = _cli_storage(args)
    items = inbox_mod.list_inbox(
        status=args.status,
        scene=args.scene,
        storage=store,
    )
    if args.json:
        print(json.dumps({"count": len(items), "items": items}, ensure_ascii=False, indent=2))
        return 0

    if not items:
        label = "保留中" if args.status == "pending" else args.status
        print(f"受信箱（{label}）に候補はありません。")
        return 0

    print(f"受信箱の候補（{len(items)}件）:")
    scene_ja = {"common": "共通", "casual": "普段・雑談", "work": "社内・同僚", "formal": "社外・目上"}
    kind_ja = {"forbidden": "NG表現", "rule": "書く時の考え方", "tone": "口調・記号", "first_person": "一人称"}
    for idx, item in enumerate(items, 1):
        sc = str(item.get("scene", ""))
        kd = str(item.get("kind", ""))
        line = (
            f"- {idx}. {item['id']} [{item.get('status')}] "
            f"[{scene_ja.get(sc, sc)} / {kind_ja.get(kd, kd)}] {item.get('value')}"
        )
        if item.get("reason"):
            line += f"（理由: {item['reason']}）"
        print(line)
        if item.get("warning"):
            print(f"  {item['warning']}")
    return 0


def cmd_inbox_approve(args: argparse.Namespace) -> int:
    store = _cli_storage(args)
    try:
        res = inbox_mod.approve_entries(
            list(args.ids),
            approve_all=args.all,
            dry_run=args.dry_run,
            force=args.force,
            storage=store,
        )
    except ValueError as exc:
        if args.json:
            print(json.dumps({"error": str(exc)}, ensure_ascii=False, indent=2))
        else:
            print(f"エラー: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        if res["dry_run"]:
            print(f"ドライラン（{res['approved_count']}件が反映対象・profile.md は未変更）:")
        elif res["approved_count"] > 0:
            print(f"{res['approved_count']}件を承認し、{res['profile_path']} に反映しました。")
        else:
            print("承認された候補はありません。")
        for r in res["results"]:
            print(f"- {r['id']}: {r['message']}")
        if res["not_found"]:
            print("見つからなかった ID: " + ", ".join(res["not_found"]), file=sys.stderr)

    if res["not_found"] or res["blocked_by_guard"]:
        return 1
    return 0


def cmd_inbox_reject(args: argparse.Namespace) -> int:
    store = _cli_storage(args)
    try:
        res = inbox_mod.reject_entries(
            list(args.ids),
            reject_all=args.all,
            reason=args.reason,
            storage=store,
        )
    except ValueError as exc:
        if args.json:
            print(json.dumps({"error": str(exc)}, ensure_ascii=False, indent=2))
        else:
            print(f"エラー: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"{res['rejected_count']}件を却下しました（profile.md は変更していません）。")
        for r in res["results"]:
            print(f"- {r['id']}: {r['message']}")
        if res["not_found"]:
            print("見つからなかった ID: " + ", ".join(res["not_found"]), file=sys.stderr)

    return 1 if res["not_found"] else 0


def cmd_inbox_review(args: argparse.Namespace) -> int:
    store = _cli_storage(args)
    pending = inbox_mod.list_inbox(status="pending", storage=store)
    if not pending:
        print("保留中の候補はありません。")
        return 0

    print(f"保留中の候補が {len(pending)} 件あります。1件ずつ承認（a）/ 却下（r）/ スキップ（s）/ 終了（q）を選んでください。")
    approved_total = 0
    rejected_total = 0
    stopped = False
    for idx, item in enumerate(pending, 1):
        print(f"\n[{idx}/{len(pending)}] {item['id']} ({item['scene']} / {item['kind']})")
        print(f"  内容: {item['value']}")
        if item.get("reason"):
            print(f"  理由: {item['reason']}")
        if item.get("example_before") or item.get("example_after"):
            print(f"  例: {item.get('example_before', '')} -> {item.get('example_after', '')}")
        if item.get("warning"):
            print(f"  {item['warning']}")

        while True:
            try:
                ans = input("  判定 [a=承認 / r=却下 / s=スキップ / q=終了]: ").strip().lower()
            except EOFError:
                stopped = True
                break

            if ans in ("q", "quit"):
                stopped = True
                break
            if ans in ("a", "approve", "y", "yes"):
                force_flag = False
                if item.get("warning"):
                    try:
                        confirm = input("  警告付きの候補です。本当に [formal] へ反映しますか？ [y/N]: ").strip().lower()
                    except EOFError:
                        stopped = True
                        break
                    if confirm not in ("y", "yes"):
                        print("  -> 反映を取りやめてスキップしました。")
                        break
                    force_flag = True
                res = inbox_mod.approve_entries(
                    [item["id"]],
                    force=force_flag,
                    storage=store,
                )
                if res["approved_count"]:
                    approved_total += 1
                    print("  -> 承認して profile.md に反映しました。")
                break
            if ans in ("r", "reject", "n", "no"):
                inbox_mod.reject_entries([item["id"]], storage=store)
                rejected_total += 1
                print("  -> 却下しました。")
                break
            if ans in ("s", "skip", ""):
                print("  -> スキップしました。")
                break
            print("  a / r / s / q のいずれかを入力してください。")

        if stopped:
            break

    print(f"\nレビュー完了: 承認 {approved_total} 件 / 却下 {rejected_total} 件")
    return 0


def cmd_profile_show(args: argparse.Namespace) -> int:
    store = _cli_storage(args)
    try:
        info = inbox_mod.read_profile(
            storage=store,
            scene=args.scene,
            project_dir=getattr(args, "project", None),
            include_project=bool(getattr(args, "project", None)),
        )
    except ValueError as exc:
        print(f"エラー: {exc}", file=sys.stderr)
        return 2

    forbidden: list[str] = []
    if info["exists"]:
        forbidden = parse_profile_text(info["raw"], scene=args.scene)
    info["forbidden"] = forbidden

    if args.json:
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return 0

    if not info["exists"]:
        print(f"profile.md がまだありません（既定パス: {info['profile_path']}）。")
        if info["pending_inbox_count"]:
            print(f"保留中の受信箱候補が {info['pending_inbox_count']} 件あります（`nihongo-check inbox list` で確認）。")
        return 0

    print(info["markdown"].rstrip("\n"))
    if info.get("project_profile_path"):
        print(f"\n（2層マージ適用: {info['project_profile_path']}）")
    if info["pending_inbox_count"]:
        print(f"\n（保留中の受信箱候補: {info['pending_inbox_count']}件）")
    return 0


PROJECT_PROFILE_TEMPLATE = """# プロジェクト専用ルール（共通の ~/.nihongo/profile.md に自動で重ねて適用されます）

## [common]
- 絶対に言わない表現：
- 書く時の考え方：

## [work]
- 口調・記号：

## [formal]
- 口調・記号：
"""


def cmd_profile_init(args: argparse.Namespace) -> int:
    if args.project is not None:
        base_dir = os.path.abspath(os.path.expanduser(args.project or os.getcwd()))
        target_path = os.path.join(base_dir, ".nihongo", "profile.md")
        template = PROJECT_PROFILE_TEMPLATE
        layer_kind = "project"
    else:
        store = _cli_storage(args)
        target_path = store.profile_location
        template = inbox_mod.DEFAULT_PROFILE_TEMPLATE
        layer_kind = "global"

    existed = os.path.isfile(target_path)
    if existed and not args.force:
        payload = {
            "created": False,
            "existed": True,
            "layer": layer_kind,
            "profile_path": target_path,
            "message": f"すでに profile.md が存在するため上書きしませんでした: {target_path}",
        }
        if args.json:
            print(json.dumps(payload, ensure_ascii=False, indent=2))
        else:
            print(payload["message"])
            print("上書きしたい場合のみ --force を指定してください。")
        return 0

    inbox_mod._atomic_write_utf8(target_path, template)
    payload = {
        "created": True,
        "existed": existed,
        "layer": layer_kind,
        "profile_path": target_path,
        "message": f"profile.md を作成しました（{layer_kind}）: {target_path}",
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(payload["message"])
    return 0


def cmd_doctor(args: argparse.Namespace) -> int:
    if __package__:
        from . import mcp_server as mcp_mod
    else:
        import mcp_server as mcp_mod  # noqa: E402

    store = _cli_storage(args)
    proj_arg = getattr(args, "project", None)
    info = inbox_mod.read_profile(
        storage=store,
        project_dir=proj_arg,
        include_project=True,
    )
    forbidden = parse_profile_text(info["raw"]) if info["exists"] else []
    sync_folders = inbox_mod.detect_sync_folders()

    resolved_home = inbox_mod.get_nihongo_home(getattr(args, "home", None))
    mcp_clients: list[dict[str, object]] = []
    home_mismatches: list[dict[str, str]] = []
    for target in mcp_mod.INIT_TARGETS:
        cfg_path = mcp_mod.resolve_client_config_path(target)
        exists = os.path.isfile(cfg_path)
        installed = mcp_mod.is_client_installed(target)
        configured = False
        mcp_home: str | None = None
        parse_error: str | None = None
        if exists:
            try:
                with open(cfg_path, encoding="utf-8-sig") as f:
                    raw = f.read()
                if raw.strip():
                    parsed = json.loads(raw)
                    if isinstance(parsed, dict) and isinstance(parsed.get("mcpServers"), dict):
                        entry = parsed["mcpServers"].get("nihongo")
                        if isinstance(entry, dict):
                            configured = True
                            entry_args = entry.get("args")
                            if isinstance(entry_args, list):
                                for idx, token in enumerate(entry_args):
                                    if token == "--home" and idx + 1 < len(entry_args):
                                        mcp_home = os.path.abspath(os.path.expanduser(str(entry_args[idx + 1])))
                                        break
            except Exception as exc:
                parse_error = str(exc)
        if configured:
            effective_mcp_home = mcp_home or inbox_mod.get_nihongo_home()
            if os.path.normcase(effective_mcp_home) != os.path.normcase(resolved_home):
                home_mismatches.append({
                    "target": target,
                    "mcp_home": effective_mcp_home,
                    "cli_home": resolved_home,
                })
        mcp_clients.append({
            "target": target,
            "config_path": cfg_path,
            "installed": installed,
            "config_exists": exists,
            "nihongo_configured": configured,
            "mcp_home": mcp_home,
            "error": parse_error,
        })

    report = {
        "version": __version__,
        "python": sys.version.split()[0],
        "home": resolved_home,
        "configured_home": inbox_mod.read_configured_home(),
        "profile_path": info["profile_path"],
        "global_profile_exists": info["global_exists"],
        "project_profile_path": info["project_profile_path"],
        "active_layers": info["layers"],
        "forbidden_count": len(forbidden),
        "pending_inbox_count": info["pending_inbox_count"],
        "sync_folders": sync_folders,
        "mcp_clients": mcp_clients,
        "home_mismatches": home_mismatches,
    }

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0

    print(f"nihongo-check doctor (v{__version__} / Python {report['python']})")
    g_mark = "あり" if info["global_exists"] else "未作成（nihongo-check profile init で作成可）"
    print(f"- 共通プロフィール: {info['profile_path']} [{g_mark}]")
    if info["project_profile_path"]:
        print(f"- 案件別上書き（2層適用中）: {info['project_profile_path']}")
    print(f"- 登録済みの避ける表現: {len(forbidden)} 件 / 承認待ち受信箱: {info['pending_inbox_count']} 件")
    if sync_folders:
        providers = ", ".join(f"{x['provider']} ({x['suggested_home']})" for x in sync_folders)
        print(f"- 検出した同期フォルダ候補: {providers}")
    else:
        print("- 検出した同期フォルダ候補: なし（ローカル既定を使用）")
    print("- AI アプリの MCP 登録状況:")
    for c in mcp_clients:
        if c["nihongo_configured"]:
            status = "登録済み"
        elif c["error"]:
            status = "JSONエラー"
        elif not c["installed"]:
            status = "未導入"
        else:
            status = "未登録"
        print(f"  - {c['target']}: {status} ({c['config_path']})")
    if home_mismatches:
        print("- [警告] CLI と MCP で保存先が食い違っています:")
        for mm in home_mismatches:
            print(f"  - {mm['target']}: MCP={mm['mcp_home']} / CLI={mm['cli_home']}")
        print("  解消例: nihongo-mcp init --target all --home \"<揃えたい保存先>\"")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nihongo-check",
        description="原文と直した文の意味のズレ検出・自動復旧・読点整理を行う日本語チェック CLI",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    p_diff = sub.add_parser("diff", help="原文と直した文を比べて意味のズレ候補を出す")
    p_diff.add_argument("orig", help="原文ファイルのパス")
    p_diff.add_argument("draft", help="直した文ファイルのパス")
    p_diff.add_argument("--request", default="", help="依頼文（ファイルパスまたは文字列）")
    p_diff.add_argument("--profile", default=None, help="書き方メモ（profile.md）のパス")
    p_diff.add_argument(
        "--auto-profile",
        action="store_true",
        help="共通の ~/.nihongo/profile.md と作業フォルダの .nihongo/profile.md を自動で2層読み込みする",
    )
    p_diff.add_argument("--home", default=None, help="--auto-profile 時のデータディレクトリ")
    p_diff.add_argument("--project", default=None, help="--auto-profile 時の作業フォルダ")
    p_diff.add_argument(
        "--scene",
        choices=("casual", "work", "formal"),
        default=None,
        help="文章の場面（casual / work / formal）",
    )
    p_diff.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_diff.set_defaults(func=cmd_diff)

    p_fix = sub.add_parser("fix", help="意味が変わった文を原文に戻し、要らない読点を外す")
    p_fix.add_argument("orig", help="原文ファイルのパス")
    p_fix.add_argument("draft", help="直した文ファイルのパス")
    p_fix.add_argument("out", help="出力ファイルのパス")
    p_fix.add_argument("--request", default="", help="依頼文（ファイルパスまたは文字列）")
    p_fix.add_argument("--no-trim-commas", action="store_true", help="読点の自動整理を行わない")
    p_fix.add_argument("--fail-on-remaining", action="store_true", help="候補が残った場合に終了コード 1 で終わる")
    p_fix.set_defaults(func=cmd_fix)

    p_git = sub.add_parser("git", help="git で変更したテキスト・Markdown の意味のズレを確認する")
    p_git.add_argument("--base", default="HEAD", help="比較元の git ref（既定: HEAD）")
    p_git.add_argument("--staged", action="store_true", help="ステージ済み（index）の変更を対象にする")
    p_git.add_argument("--ext", default=".md,.txt", help="対象とする拡張子（カンマ区切り、既定: .md,.txt）")
    p_git.add_argument("--request", default="", help="依頼文（ファイルパスまたは文字列）")
    p_git.add_argument("--profile", default=None, help="書き方メモ（profile.md）のパス")
    p_git.add_argument(
        "--auto-profile",
        action="store_true",
        help="共通の ~/.nihongo/profile.md と作業フォルダの .nihongo/profile.md を自動で2層読み込みする",
    )
    p_git.add_argument("--home", default=None, help="--auto-profile 時のデータディレクトリ")
    p_git.add_argument("--project", default=None, help="--auto-profile 時の作業フォルダ")
    p_git.add_argument(
        "--scene",
        choices=("casual", "work", "formal"),
        default=None,
        help="文章の場面（casual / work / formal）",
    )
    p_git.add_argument("--hook", action="store_true", help="PostToolUse フック向けモード（候補検出時は stderr 出力＋終了コード 2）")
    p_git.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_git.add_argument("paths", nargs="*", help="対象を絞るファイルまたはディレクトリ")
    p_git.set_defaults(func=cmd_git)

    # HITL inbox subcommands
    p_inbox = sub.add_parser("inbox", help="個人プロフィールの追記候補（HITL 受信箱）を管理する")
    inbox_sub = p_inbox.add_subparsers(dest="inbox_command", required=True)

    p_prop = inbox_sub.add_parser("propose", help="追記候補を受信箱へ追加する（profile.md は変更しない）")
    p_prop.add_argument("--scene", choices=inbox_mod.VALID_SCENES, default="common", help="対象場面")
    p_prop.add_argument("--kind", choices=inbox_mod.VALID_KINDS, default="rule", help="候補の種類")
    p_prop.add_argument("--value", required=True, help="追記したい表現やルール")
    p_prop.add_argument("--reason", default="", help="なぜ直したか（根拠メモ）")
    p_prop.add_argument("--before", default="", help="修正前の文例（任意）")
    p_prop.add_argument("--after", default="", help="修正後の文例（任意）")
    p_prop.add_argument("--source", default="cli", help="収集元（chatgpt / claude / cursor / cli 等）")
    p_prop.add_argument("--home", default=None, help="データディレクトリ（既定: ~/.nihongo）")
    p_prop.add_argument("--inbox", default=None, help="受信箱ファイルのパス（既定: ~/.nihongo/inbox.jsonl）")
    p_prop.add_argument("--profile", default=None, help="profile.md のパス（既定: ~/.nihongo/profile.md）")
    p_prop.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_prop.set_defaults(func=cmd_inbox_propose)

    p_list = inbox_sub.add_parser("list", help="受信箱の候補を一覧表示する")
    p_list.add_argument(
        "--status",
        choices=("pending", "approved", "rejected", "all"),
        default="pending",
        help="絞り込む状態（既定: pending）",
    )
    p_list.add_argument("--scene", choices=inbox_mod.VALID_SCENES, default=None, help="場面で絞り込む")
    p_list.add_argument("--home", default=None, help="データディレクトリ（既定: ~/.nihongo）")
    p_list.add_argument("--inbox", default=None, help="受信箱ファイルのパス")
    p_list.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_list.set_defaults(func=cmd_inbox_list)

    p_appr = inbox_sub.add_parser("approve", help="保留中の候補を承認して profile.md へ反映する")
    p_appr.add_argument("ids", nargs="*", help="承認する候補 ID")
    p_appr.add_argument("--all", action="store_true", help="保留中の候補をすべて承認する")
    p_appr.add_argument("--dry-run", action="store_true", help="profile.md を書き換えずに結果だけ確認する")
    p_appr.add_argument("--force", action="store_true", help="場面ガード警告のある候補も承認する")
    p_appr.add_argument("--home", default=None, help="データディレクトリ（既定: ~/.nihongo）")
    p_appr.add_argument("--inbox", default=None, help="受信箱ファイルのパス")
    p_appr.add_argument("--profile", default=None, help="profile.md のパス")
    p_appr.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_appr.set_defaults(func=cmd_inbox_approve)

    p_rej = inbox_sub.add_parser("reject", help="保留中の候補を却下する（profile.md は変更しない）")
    p_rej.add_argument("ids", nargs="*", help="却下する候補 ID")
    p_rej.add_argument("--all", action="store_true", help="保留中の候補をすべて却下する")
    p_rej.add_argument("--reason", default="", help="却下理由（任意）")
    p_rej.add_argument("--home", default=None, help="データディレクトリ（既定: ~/.nihongo）")
    p_rej.add_argument("--inbox", default=None, help="受信箱ファイルのパス")
    p_rej.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_rej.set_defaults(func=cmd_inbox_reject)

    p_rev = inbox_sub.add_parser("review", help="保留中の候補を対話形式で1件ずつ承認・却下する")
    p_rev.add_argument("--home", default=None, help="データディレクトリ（既定: ~/.nihongo）")
    p_rev.add_argument("--inbox", default=None, help="受信箱ファイルのパス")
    p_rev.add_argument("--profile", default=None, help="profile.md のパス")
    p_rev.set_defaults(func=cmd_inbox_review)

    # Profile inspection subcommand
    p_prof = sub.add_parser("profile", help="個人プロフィール（~/.nihongo/profile.md）を確認する")
    prof_sub = p_prof.add_subparsers(dest="profile_command", required=True)
    p_pshow = prof_sub.add_parser("show", help="現在の profile.md と保留件数を表示する")
    p_pshow.add_argument("--scene", choices=inbox_mod.VALID_SCENES, default=None, help="特定場面のみ表示")
    p_pshow.add_argument("--home", default=None, help="データディレクトリ（既定: ~/.nihongo）")
    p_pshow.add_argument("--profile", default=None, help="profile.md のパス")
    p_pshow.add_argument("--inbox", default=None, help="受信箱ファイルのパス")
    p_pshow.add_argument("--project", default=None, help="作業フォルダ（.nihongo/profile.md を2層マージ）")
    p_pshow.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_pshow.set_defaults(func=cmd_profile_show)

    p_pinit = prof_sub.add_parser("init", help="profile.md のひな形を作成する（既存ファイルは保護）")
    p_pinit.add_argument("--home", default=None, help="グローバルデータディレクトリ（既定: ~/.nihongo）")
    p_pinit.add_argument(
        "--project",
        nargs="?",
        const="",
        default=None,
        help="作業フォルダ専用の .nihongo/profile.md を作成する（パス省略時はカレントディレクトリ）",
    )
    p_pinit.add_argument("--force", action="store_true", help="既存ファイルがある場合もひな形で上書きする")
    p_pinit.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_pinit.set_defaults(func=cmd_profile_init)

    # Read-only health check subcommand
    p_doc = sub.add_parser("doctor", help="プロフィール・2層設定・同期フォルダ・MCP 登録状況を一括診断する")
    p_doc.add_argument("--home", default=None, help="データディレクトリ（既定: ~/.nihongo）")
    p_doc.add_argument("--project", default=None, help="作業フォルダ（.nihongo/profile.md 検出用）")
    p_doc.add_argument("--json", action="store_true", help="JSON 形式で出力する")
    p_doc.set_defaults(func=cmd_doctor)

    return parser


def main(argv: list[str] | None = None) -> int:
    _ensure_utf8_stdio()
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
