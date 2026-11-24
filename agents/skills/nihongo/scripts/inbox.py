#!/usr/bin/env python3
"""HITL（Human-in-the-Loop）型の個人プロフィール受信箱（inbox）と profile.md 管理モジュール。

設計原則:
- `~/.nihongo/profile.md` を唯一の正（Single Source of Truth）として保つ。
- 自動化するのは候補を `inbox.jsonl` に拾うところまで（propose は profile.md を一切書き換えない）。
- `profile.md` への反映は必ず本人承認（approve）を経由する。
- 標準ライブラリだけで動作する。
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import re
import shutil
import tempfile
import time
import unicodedata
import uuid
from typing import Any, Protocol, runtime_checkable

VALID_SCENES = ("common", "casual", "work", "formal")
VALID_KINDS = ("forbidden", "rule", "tone", "first_person")
VALID_STATUSES = ("pending", "approved", "rejected")

DEFAULT_PROFILE_TEMPLATE = """# 私の書き方

## [common]
- 一人称：
- 絶対に言わない表現：
- 書く時の考え方：

## [casual]
- 場面：友達・身内・雑談
- 口調・記号：

## [work]
- 場面：社内チャット・PR・同僚
- 口調・記号：

## [formal]
- 場面：目上・社外メール・公式お知らせ（[casual] の崩しや絵文字は持ち込まない）
- 口調・記号：
"""

_SECTION_DEFAULTS: dict[str, str] = {
    "common": "- 一人称：\n- 絶対に言わない表現：\n- 書く時の考え方：",
    "casual": "- 場面：友達・身内・雑談\n- 口調・記号：",
    "work": "- 場面：社内チャット・PR・同僚\n- 口調・記号：",
    "formal": "- 場面：目上・社外メール・公式お知らせ（[casual] の崩しや絵文字は持ち込まない）\n- 口調・記号：",
}

_HEADING_RE = re.compile(r"^\s*(#{1,6})\s+(.+?)\s*$")
_SCENE_TAG_RE = re.compile(r"\[(common|casual|work|formal)\]", re.IGNORECASE)

# PII / 個人情報ガード（NFKC 正規化後にメール・電話・秘密鍵/トークンを拒否）
_DASH_TRANS = str.maketrans({
    "\u2212": "-",  # MINUS SIGN
    "\u2010": "-",  # HYPHEN
    "\u2011": "-",  # NON-BREAKING HYPHEN
    "\u2012": "-",  # FIGURE DASH
    "\u2013": "-",  # EN DASH
    "\u2014": "-",  # EM DASH
    "\u2015": "-",  # HORIZONTAL BAR
    "\u30fc": "-",  # KATAKANA-HIRAGANA PROLONGED SOUND MARK (全角電話番号誤入力対策)
})
_EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
_PHONE_RE = re.compile(
    r"(?<!\d)(?:"
    r"\+81[-\s]?\d{1,4}[-\s]?\d{1,4}[-\s]?\d{3,4}"
    r"|0\d{1,4}[-\s(]+\d{1,4}[-\s)]+\d{3,4}"
    r"|0[789]0\d{8}"
    r"|0\d{9}"
    r")(?!\d)"
)
_SECRET_RE = re.compile(
    r"(?:"
    r"(?<![A-Za-z0-9_])sk-(?:proj-|ant-)?[A-Za-z0-9_-]{16,}"
    r"|(?<![A-Za-z0-9_])ghp_[A-Za-z0-9]{20,}"
    r"|(?<![A-Za-z0-9_])github_pat_[A-Za-z0-9_]{20,}"
    r"|(?<![A-Za-z0-9_])AKIA[0-9A-Z]{16}(?![A-Za-z0-9])"
    r"|(?<![A-Za-z0-9_])xox[baprs]-[A-Za-z0-9-]{10,}"
    r"|(?<![A-Za-z0-9_])AIza[0-9A-Za-z\-_]{20,}"
    r"|-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"
    r")"
)
MAX_VALUE_LEN = 500

# formal 場面の崩しガード
_CASUAL_SSU_RE = re.compile(r"っす(?![ぐうる])")
_CASUAL_LAUGH_RE = re.compile(
    r"(?:(?<![A-Za-z0-9./])[wｗ]{2,}(?![A-Za-z0-9./])|(?<![A-Za-z0-9])[wｗ](?=$|[\s。、！？!?\n]))"
)
_EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\u2728\u2764\u2763\u2757\u2753\u2600\u2601\u2614\u26A1\u2615]")


def default_local_home() -> str:
    """ローカル既定の保存先（~/.nihongo）を返す。"""
    return os.path.abspath(os.path.expanduser("~/.nihongo"))


def config_file_path() -> str:
    """保存先ポインタ（~/.nihongo/config.json）のパスを返す。"""
    env_cfg = os.environ.get("NIHONGO_CONFIG", "").strip()
    if env_cfg:
        return os.path.abspath(os.path.expanduser(env_cfg))
    return os.path.join(default_local_home(), "config.json")


def read_configured_home() -> str | None:
    """~/.nihongo/config.json に記録された保存先（home）を読む。無ければ None。"""
    cfg = config_file_path()
    if not os.path.isfile(cfg):
        return None
    try:
        with open(cfg, encoding="utf-8-sig") as f:
            raw = f.read().strip()
        if not raw:
            return None
        data = json.loads(raw)
        if isinstance(data, dict):
            val = data.get("home")
            if isinstance(val, str) and val.strip():
                return os.path.abspath(os.path.expanduser(val.strip()))
    except Exception:
        return None
    return None


def save_configured_home(home_dir: str) -> str:
    """選択されたデータ保存先を ~/.nihongo/config.json に記録し、全 CLI / MCP で統一する。"""
    resolved = os.path.abspath(os.path.expanduser(home_dir))
    cfg = config_file_path()
    data: dict[str, Any] = {}
    if os.path.isfile(cfg):
        try:
            with open(cfg, encoding="utf-8-sig") as f:
                parsed = json.loads(f.read() or "{}")
            if isinstance(parsed, dict):
                data = parsed
        except Exception:
            data = {}
    data["home"] = resolved
    _atomic_write_utf8(cfg, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return cfg


def migrate_profile_to_home(
    target_home: str,
    *,
    source_home: str | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    """既存の ~/.nihongo/profile.md（と inbox.jsonl）を新しい同期フォルダへ安全に移行（未作成時のみコピー）。"""
    src_dir = os.path.abspath(os.path.expanduser(source_home)) if source_home else default_local_home()
    dst_dir = os.path.abspath(os.path.expanduser(target_home))
    copied: list[str] = []
    skipped: list[str] = []
    if os.path.normcase(src_dir) == os.path.normcase(dst_dir):
        return {"source": src_dir, "target": dst_dir, "copied": copied, "skipped": skipped, "dry_run": dry_run}

    for fname in ("profile.md", "inbox.jsonl"):
        src = os.path.join(src_dir, fname)
        dst = os.path.join(dst_dir, fname)
        if not os.path.isfile(src):
            continue
        if os.path.exists(dst):
            skipped.append(fname)
            continue
        if not dry_run:
            os.makedirs(dst_dir, exist_ok=True)
            shutil.copy2(src, dst)
        copied.append(fname)
    return {"source": src_dir, "target": dst_dir, "copied": copied, "skipped": skipped, "dry_run": dry_run}


def get_nihongo_home(home: str | None = None) -> str:
    """nihongo のデータディレクトリ（優先順: 明示引数 > 環境変数 NIHONGO_HOME > ~/.nihongo/config.json > ~/.nihongo）。"""
    if home:
        return os.path.abspath(os.path.expanduser(home))
    env_home = os.environ.get("NIHONGO_HOME", "").strip()
    if env_home:
        return os.path.abspath(os.path.expanduser(env_home))
    cfg_home = read_configured_home()
    if cfg_home:
        return cfg_home
    return default_local_home()


def default_profile_path(home: str | None = None) -> str:
    return os.path.join(get_nihongo_home(home), "profile.md")


def default_inbox_path(home: str | None = None) -> str:
    return os.path.join(get_nihongo_home(home), "inbox.jsonl")


@runtime_checkable
class ProfileStorage(Protocol):
    """profile.md と inbox.jsonl の保存先を抽象化する最小インターフェース（4メソッド）。

    ローカルファイル（LocalFileStorage）だけでなく、将来 Google Drive などの
    ユーザー自身のクラウドストレージへ差し替えても HITL ロジックをそのまま再利用できる。
    """

    @property
    def profile_location(self) -> str: ...

    @property
    def inbox_location(self) -> str: ...

    def read_profile_text(self) -> str | None: ...

    def write_profile_text(self, content: str) -> None: ...

    def read_inbox_text(self) -> str | None: ...

    def write_inbox_text(self, content: str) -> None: ...


class LocalFileStorage:
    """既定の保存先（~/.nihongo/profile.md と ~/.nihongo/inbox.jsonl）。"""

    def __init__(
        self,
        *,
        home: str | None = None,
        profile_path: str | None = None,
        inbox_path: str | None = None,
    ) -> None:
        self._profile_path = (
            os.path.abspath(os.path.expanduser(profile_path))
            if profile_path
            else default_profile_path(home)
        )
        self._inbox_path = (
            os.path.abspath(os.path.expanduser(inbox_path))
            if inbox_path
            else default_inbox_path(home)
        )

    @property
    def profile_location(self) -> str:
        return self._profile_path

    @property
    def inbox_location(self) -> str:
        return self._inbox_path

    def read_profile_text(self) -> str | None:
        if not os.path.isfile(self._profile_path):
            return None
        with open(self._profile_path, encoding="utf-8-sig") as f:
            return f.read()

    def write_profile_text(self, content: str) -> None:
        _atomic_write_utf8(self._profile_path, content)

    def read_inbox_text(self) -> str | None:
        if not os.path.isfile(self._inbox_path):
            return None
        with open(self._inbox_path, encoding="utf-8-sig") as f:
            return f.read()

    def write_inbox_text(self, content: str) -> None:
        _atomic_write_utf8(self._inbox_path, content)


def _resolve_storage(
    storage: ProfileStorage | None = None,
    *,
    profile_path: str | None = None,
    inbox_path: str | None = None,
) -> ProfileStorage:
    if storage is not None:
        return storage
    return LocalFileStorage(profile_path=profile_path, inbox_path=inbox_path)


def _utc_now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _atomic_write_utf8(path: str, content: str) -> None:
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".nihongo_tmp_", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        last_err: OSError | None = None
        for attempt in range(5):
            try:
                os.replace(tmp_path, path)
                last_err = None
                break
            except PermissionError as exc:
                last_err = exc
                if os.name != "nt" or attempt == 4:
                    raise
                time.sleep(0.03 * (attempt + 1))
        if last_err is not None:
            raise last_err
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _check_pii(texts: list[str]) -> str | None:
    """メールアドレス・電話番号・APIキー等の個人情報が混ざっていれば理由を返す（NFKC正規化対応）。"""
    for raw in texts:
        if not raw:
            continue
        norm = unicodedata.normalize("NFKC", raw).translate(_DASH_TRANS)
        if _EMAIL_RE.search(norm):
            return "メールアドレスが含まれているため記録できません（個人情報保護）。"
        if _PHONE_RE.search(norm):
            return "電話番号と思われる数字列が含まれているため記録できません（個人情報保護）。"
        if _SECRET_RE.search(norm):
            return "APIキー・秘密鍵と思われる文字列が含まれているため記録できません。"
    return None


def _check_formal_boundary(scene: str, kind: str, value: str) -> str | None:
    """formal 場面への崩し表現混入を警告する（forbidden での禁止指定は許可）。"""
    if scene != "formal" or kind == "forbidden":
        return None
    if _CASUAL_SSU_RE.search(value) or _CASUAL_LAUGH_RE.search(value) or _EMOJI_RE.search(value):
        return "[場面ガード] [formal] 場面にくだけた語尾や絵文字を含める候補です。本当に公式・目上向けか確認してください。"
    return None


def _normalize_value(value: str) -> str:
    cleaned = _normalize_newlines(value).strip()
    cleaned = re.sub(r"\s*\n\s*", " ", cleaned)
    return cleaned


def _strip_outer_quotes(text: str) -> str:
    """先頭と末尾が対になっている引用符だけを外す（文中の「」は壊さない）。"""
    v = text.strip(" \t\u3000")
    pairs = (("「", "」"), ("『", "』"), ('"', '"'), ("'", "'"), ("“", "”"))
    changed = True
    while changed and len(v) >= 2:
        changed = False
        for left, right in pairs:
            if v.startswith(left) and v.endswith(right):
                v = v[len(left) : len(v) - len(right)].strip(" \t\u3000")
                changed = True
                break
    return v


def _format_forbidden_item(value: str) -> str:
    v = _strip_outer_quotes(value)
    if not v:
        return ""
    return f"「{v}」"


def load_inbox(
    inbox_path: str | None = None,
    *,
    storage: ProfileStorage | None = None,
) -> list[dict[str, Any]]:
    store = _resolve_storage(storage, inbox_path=inbox_path)
    raw = store.read_inbox_text()
    if not raw:
        return []
    entries: list[dict[str, Any]] = []
    for line in _normalize_newlines(raw).split("\n"):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and "id" in obj:
            entries.append(obj)
    return entries


def save_inbox(
    entries: list[dict[str, Any]],
    inbox_path: str | None = None,
    *,
    storage: ProfileStorage | None = None,
) -> str:
    store = _resolve_storage(storage, inbox_path=inbox_path)
    lines = [json.dumps(item, ensure_ascii=False) for item in entries]
    content = ("\n".join(lines) + "\n") if lines else ""
    store.write_inbox_text(content)
    return store.inbox_location


def _make_entry_id(existing_ids: set[str]) -> str:
    date_tag = _dt.datetime.now().strftime("%Y%m%d")
    for _ in range(20):
        cand = f"inb_{date_tag}_{uuid.uuid4().hex[:6]}"
        if cand not in existing_ids:
            return cand
    return f"inb_{date_tag}_{uuid.uuid4().hex[:10]}"


def _dedup_key(scene: str, kind: str, value: str) -> tuple[str, str, str]:
    norm = unicodedata.normalize("NFKC", _normalize_value(value)).strip("「」『』\"' ")
    return (scene.lower(), kind.lower(), norm)


def propose_entry(
    *,
    scene: str,
    kind: str,
    value: str,
    reason: str = "",
    example_before: str = "",
    example_after: str = "",
    source: str = "chat",
    allow_resubmit: bool = False,
    inbox_path: str | None = None,
    profile_path: str | None = None,
    storage: ProfileStorage | None = None,
) -> dict[str, Any]:
    """追記候補を inbox.jsonl に登録する。profile.md は絶対に書き換えない（HITL原則）。"""
    store = _resolve_storage(storage, profile_path=profile_path, inbox_path=inbox_path)
    scene_norm = scene.strip().lower()
    kind_norm = kind.strip().lower()
    if scene_norm not in VALID_SCENES:
        raise ValueError(f"不正な scene です: {scene!r}（{', '.join(VALID_SCENES)} から指定）")
    if kind_norm not in VALID_KINDS:
        raise ValueError(f"不正な kind です: {kind!r}（{', '.join(VALID_KINDS)} から指定）")

    val = _normalize_value(value)
    if not val:
        raise ValueError("value（追記したい内容）が空です。")
    if len(val) > MAX_VALUE_LEN:
        raise ValueError(f"value が長すぎます（上限 {MAX_VALUE_LEN} 文字）。1行の短いルールに絞ってください。")

    if kind_norm == "first_person" and scene_norm != "common":
        scene_norm = "common"

    pii_err = _check_pii([val, reason, example_before, example_after, source])
    if pii_err:
        raise ValueError(pii_err)

    warning = _check_formal_boundary(scene_norm, kind_norm, val)

    entries = load_inbox(storage=store)
    target_key = _dedup_key(scene_norm, kind_norm, val)

    # すでに pending に同一候補がある場合は重複登録せず既存を返す
    for existing in entries:
        ex_key = _dedup_key(
            str(existing.get("scene", "")),
            str(existing.get("kind", "")),
            str(existing.get("value", "")),
        )
        if ex_key != target_key:
            continue
        st = existing.get("status")
        if st == "pending":
            return {
                "created": False,
                "duplicate": True,
                "previously_rejected": False,
                "entry": existing,
                "warning": warning,
                "message": f"同一の候補がすでに保留中です（ID: {existing['id']}）。",
            }
        if st == "rejected" and not allow_resubmit:
            return {
                "created": False,
                "duplicate": False,
                "previously_rejected": True,
                "entry": existing,
                "warning": warning,
                "message": f"過去に却下済みの候補のため再登録しませんでした（ID: {existing['id']}）。",
            }

    # profile.md の該当場面・種別にすでに同じ項目が登録されている場合は重複登録しない
    already_in_profile = False
    existing_profile = store.read_profile_text()
    if existing_profile is not None:
        parsed_sec = parse_profile_structured(existing_profile).get(scene_norm) or {}
        needle = unicodedata.normalize("NFKC", _strip_outer_quotes(val)).strip(" \t\u3000〜～")
        if needle:
            if kind_norm == "forbidden":
                existing_items = {
                    unicodedata.normalize("NFKC", w).strip(" \t\u3000〜～")
                    for w in parsed_sec.get("forbidden", [])
                }
                already_in_profile = needle in existing_items
            elif kind_norm == "first_person":
                fp_raw = str(parsed_sec.get("first_person") or "")
                existing_fps = {
                    unicodedata.normalize("NFKC", p.strip())
                    for p in re.split(r"[／/、,]", fp_raw)
                    if p.strip()
                }
                already_in_profile = needle in existing_fps
            else:
                existing_rules = {
                    unicodedata.normalize("NFKC", r).strip()
                    for r in parsed_sec.get("rules", [])
                }
                already_in_profile = needle in existing_rules
    if already_in_profile and not allow_resubmit:
        return {
            "created": False,
            "duplicate": False,
            "previously_rejected": False,
            "already_in_profile": True,
            "entry": None,
            "warning": warning,
            "message": f"「{val}」はすでに profile.md に登録済みのため、受信箱へ重複追加しませんでした。",
        }

    existing_ids = {str(e.get("id", "")) for e in entries}
    entry: dict[str, Any] = {
        "id": _make_entry_id(existing_ids),
        "status": "pending",
        "scene": scene_norm,
        "kind": kind_norm,
        "value": val,
        "reason": _normalize_value(reason),
        "example_before": _normalize_value(example_before),
        "example_after": _normalize_value(example_after),
        "source": _normalize_value(source) or "chat",
        "created_at": _utc_now_iso(),
        "decided_at": None,
        "decision_note": "",
    }
    if warning:
        entry["warning"] = warning

    entries.append(entry)
    saved_path = save_inbox(entries, storage=store)
    return {
        "created": True,
        "duplicate": False,
        "already_in_profile": already_in_profile,
        "inbox_path": saved_path,
        "entry": entry,
        "warning": warning,
        "message": (
            f"受信箱（inbox）に候補を保存しました（ID: {entry['id']}）。"
            "profile.md はまだ変更されていません。本人承認後に反映されます。"
        ),
    }


def list_inbox(
    *,
    status: str | None = "pending",
    scene: str | None = None,
    inbox_path: str | None = None,
    storage: ProfileStorage | None = None,
) -> list[dict[str, Any]]:
    entries = load_inbox(inbox_path, storage=storage)
    out: list[dict[str, Any]] = []
    for item in entries:
        if status and status != "all" and item.get("status") != status:
            continue
        if scene and item.get("scene") != scene.lower():
            continue
        out.append(item)
    return out


def _find_section_bounds(lines: list[str], scene: str) -> tuple[int, int] | None:
    """`## [scene]` セクションの (見出し行index, セクション終端index) を返す。"""
    start_idx: int | None = None
    start_level = 2
    for i, line in enumerate(lines):
        m = _HEADING_RE.match(line)
        if not m:
            continue
        level = len(m.group(1))
        tag_m = _SCENE_TAG_RE.search(m.group(2))
        if start_idx is None:
            if tag_m and tag_m.group(1).lower() == scene:
                start_idx = i
                start_level = level
        else:
            if level <= start_level:
                return (start_idx, i)
    if start_idx is not None:
        return (start_idx, len(lines))
    return None


def _target_field_label(scene: str, kind: str) -> str:
    if kind == "forbidden":
        return "絶対に言わない表現"
    if kind == "first_person":
        return "一人称"
    if kind == "tone":
        return "口調・記号" if scene != "common" else "書く時の考え方"
    # kind == "rule"
    return "書く時の考え方" if scene == "common" else "口調・記号"


def apply_entry_to_profile_text(profile_text: str, entry: dict[str, Any]) -> tuple[str, bool, str]:
    """承認済みの 1 エントリを profile.md テキストへ外科的に反映する。

    Returns:
        (updated_text, changed, summary_line)
    """
    scene = str(entry.get("scene", "common")).lower()
    kind = str(entry.get("kind", "rule")).lower()
    value = _normalize_value(str(entry.get("value", "")))
    if not value:
        return (profile_text, False, "値が空のためスキップしました。")

    text = _normalize_newlines(profile_text)
    if not text.strip():
        text = DEFAULT_PROFILE_TEMPLATE
    lines = text.split("\n")

    bounds = _find_section_bounds(lines, scene)
    if bounds is None:
        # 末尾に空行を挟んで該当セクションを追加
        while lines and lines[-1] == "":
            lines.pop()
        if lines:
            lines.append("")
        lines.append(f"## [{scene}]")
        lines.extend(_SECTION_DEFAULTS[scene].split("\n"))
        lines.append("")
        bounds = _find_section_bounds(lines, scene)
        assert bounds is not None

    sec_start, sec_end = bounds
    label = _target_field_label(scene, kind)
    field_re = re.compile(rf"^(\s*[-*・]\s*(?:\*\*)?{re.escape(label)}(?:\*\*)?\s*[：:])(.*)$")

    # 既存フィールド行を探す
    field_idx: int | None = None
    for idx in range(sec_start + 1, sec_end):
        if field_re.match(lines[idx]):
            field_idx = idx
            break

    if kind == "forbidden":
        formatted = _format_forbidden_item(value)
        sep = "、"
    elif kind == "first_person":
        formatted = value
        sep = "／"
    else:
        formatted = value
        sep = "。"

    if field_idx is not None:
        m = field_re.match(lines[field_idx])
        assert m is not None
        prefix, rhs = m.group(1), m.group(2).strip()
        needle_norm = unicodedata.normalize("NFKC", _strip_outer_quotes(value)).strip(" \t\u3000〜～")
        if needle_norm:
            if kind == "forbidden":
                existing_toks = {
                    unicodedata.normalize("NFKC", _strip_outer_quotes(t)).strip(" \t\u3000〜～")
                    for t in _split_quoted_tokens(rhs)
                }
                dup_found = needle_norm in existing_toks
            elif kind == "first_person":
                existing_fps = {
                    unicodedata.normalize("NFKC", t.strip())
                    for t in re.split(r"[／/、,]", rhs)
                    if t.strip()
                }
                dup_found = needle_norm in existing_fps
            else:
                existing_parts = {
                    unicodedata.normalize("NFKC", p.strip())
                    for p in _split_quoted_sentences(rhs)
                    if p.strip()
                }
                dup_found = needle_norm in existing_parts
            if dup_found:
                return ("\n".join(lines).rstrip("\n") + "\n", False, f"[{scene}] {label} にはすでに含まれています。")

        if not rhs:
            new_rhs = formatted
        else:
            if sep == "。" and rhs.endswith(("。", "！", "!", "？", "?")):
                new_rhs = f"{rhs}{formatted}"
            elif sep == "、" and rhs.endswith(("、", ",")):
                new_rhs = f"{rhs}{formatted}"
            else:
                new_rhs = f"{rhs}{sep}{formatted}"
        lines[field_idx] = f"{prefix}{new_rhs}"
    else:
        # フィールド行が無ければセクション末尾（空行の直前）に追加
        insert_at = sec_end
        while insert_at > sec_start + 1 and lines[insert_at - 1].strip() == "":
            insert_at -= 1
        lines.insert(insert_at, f"- {label}：{formatted}")

    updated = "\n".join(lines).rstrip("\n") + "\n"
    return (updated, True, f"[{scene}] {label} に「{value}」を反映しました。")


def approve_entries(
    entry_ids: list[str] | None = None,
    *,
    approve_all: bool = False,
    dry_run: bool = False,
    force: bool = False,
    inbox_path: str | None = None,
    profile_path: str | None = None,
    storage: ProfileStorage | None = None,
) -> dict[str, Any]:
    """指定 ID（または --all）の保留候補を承認し、profile.md に反映する（唯一の profile.md 書き込み口）。"""
    store = _resolve_storage(storage, profile_path=profile_path, inbox_path=inbox_path)
    entries = load_inbox(storage=store)
    p_path = store.profile_location
    existing_profile = store.read_profile_text()
    current_text = existing_profile if existing_profile is not None else ""

    id_set = set(entry_ids or [])
    if not approve_all and not id_set:
        raise ValueError("承認する ID を指定するか、approve_all=True を指定してください。")

    matched: list[dict[str, Any]] = []
    not_found: list[str] = []
    skipped_warnings: list[dict[str, Any]] = []
    results: list[dict[str, Any]] = []

    by_id = {str(e.get("id", "")): e for e in entries}
    if not approve_all:
        for req_id in entry_ids or []:
            if req_id not in by_id:
                not_found.append(req_id)

    working_text = current_text
    now_iso = _utc_now_iso()
    any_profile_change = False

    for item in entries:
        item_id = str(item.get("id", ""))
        if approve_all:
            if item.get("status") != "pending":
                continue
        else:
            if item_id not in id_set:
                continue

        if item.get("status") != "pending":
            results.append({
                "id": item_id,
                "status": item.get("status"),
                "applied": False,
                "message": f"すでに {item.get('status')} です。",
            })
            continue

        warning = _check_formal_boundary(
            str(item.get("scene", "")),
            str(item.get("kind", "")),
            str(item.get("value", "")),
        )
        if warning and not force:
            skipped_warnings.append({"id": item_id, "warning": warning})
            results.append({
                "id": item_id,
                "status": "pending",
                "applied": False,
                "blocked_by_guard": True,
                "message": warning + "（強制反映する場合は force=True / --force を指定）",
            })
            continue

        matched.append(item)
        working_text, changed, summary = apply_entry_to_profile_text(working_text, item)
        if changed:
            any_profile_change = True
        if not dry_run:
            item["status"] = "approved"
            item["decided_at"] = now_iso
            item["decision_note"] = summary
        results.append({
            "id": item_id,
            "status": "approved" if not dry_run else "pending (dry-run)",
            "applied": changed,
            "message": summary,
        })

    if not dry_run and matched:
        if any_profile_change or existing_profile is None:
            store.write_profile_text(working_text)
        save_inbox(entries, storage=store)

    return {
        "dry_run": dry_run,
        "profile_path": p_path,
        "approved_count": len(matched),
        "profile_updated": any_profile_change and not dry_run,
        "not_found": not_found,
        "blocked_by_guard": skipped_warnings,
        "results": results,
        "preview_profile": working_text if dry_run else None,
    }


def reject_entries(
    entry_ids: list[str] | None = None,
    *,
    reject_all: bool = False,
    reason: str = "",
    inbox_path: str | None = None,
    storage: ProfileStorage | None = None,
) -> dict[str, Any]:
    """指定 ID（または reject_all=True）の保留候補を却下する（profile.md には一切触れない）。"""
    id_set = set(entry_ids or [])
    if not reject_all and not id_set:
        raise ValueError("却下する ID を指定するか、reject_all=True を指定してください。")
    store = _resolve_storage(storage, inbox_path=inbox_path)
    entries = load_inbox(storage=store)
    by_id = {str(e.get("id", "")): e for e in entries}
    not_found = [] if reject_all else [req_id for req_id in (entry_ids or []) if req_id not in by_id]

    now_iso = _utc_now_iso()
    rejected: list[str] = []
    results: list[dict[str, Any]] = []
    note = _normalize_value(reason)
    pii_err = _check_pii([note])
    if pii_err:
        raise ValueError(pii_err)

    for item in entries:
        item_id = str(item.get("id", ""))
        if reject_all:
            if item.get("status") != "pending":
                continue
        elif item_id not in id_set:
            continue
        if item.get("status") != "pending":
            results.append({
                "id": item_id,
                "status": item.get("status"),
                "rejected": False,
                "message": f"すでに {item.get('status')} です。",
            })
            continue
        item["status"] = "rejected"
        item["decided_at"] = now_iso
        item["decision_note"] = note
        rejected.append(item_id)
        results.append({
            "id": item_id,
            "status": "rejected",
            "rejected": True,
            "message": "却下しました（profile.md は変更していません）。",
        })

    if rejected:
        save_inbox(entries, storage=store)

    return {
        "rejected_count": len(rejected),
        "not_found": not_found,
        "results": results,
    }


MAX_PROJECT_PROFILE_BYTES = 256 * 1024


def find_project_profile(
    start_dir: str | None = None,
    *,
    global_profile_path: str | None = None,
) -> str | None:
    """作業ディレクトリから上位へ辿り、プロジェクト固有の `.nihongo/profile.md` を探す。

    セキュリティ対策:
    - 明示指定された start_dir が存在しない場合は None を返す。
    - `.nihongo` および `.nihongo/profile.md` のシンボリックリンク経由の外部ファイル読み取りを拒否する。
    - ホームディレクトリ（$HOME）より上、および共有 temp ディレクトリ直下は探索対象外とする。
    - グローバルの `~/.nihongo/profile.md`（または `global_profile_path`）と同一ファイルは除外する。
    """
    if start_dir is not None:
        raw_start = start_dir.strip()
        if not raw_start:
            return None
        cur = os.path.abspath(os.path.expanduser(raw_start))
        if not os.path.exists(cur):
            return None
    else:
        cur = os.path.abspath(os.getcwd())

    if os.path.isfile(cur):
        cur = os.path.dirname(cur)

    home_real = os.path.normcase(os.path.realpath(os.path.expanduser("~")))
    temp_real = os.path.normcase(os.path.realpath(tempfile.gettempdir()))
    if global_profile_path and "://" in global_profile_path:
        global_real: str | None = None
    elif global_profile_path:
        global_real = os.path.normcase(os.path.realpath(os.path.abspath(os.path.expanduser(global_profile_path))))
    else:
        global_real = os.path.normcase(os.path.realpath(default_profile_path()))

    start_real = os.path.normcase(os.path.realpath(cur))
    try:
        under_home = os.path.commonpath([home_real, start_real]) == home_real
    except ValueError:
        under_home = False

    visited: set[str] = set()
    while True:
        cur_real = os.path.normcase(os.path.realpath(cur))
        if cur_real in visited:
            break
        visited.add(cur_real)

        # ホームディレクトリ直下と共有 temp ルート直下はプロジェクト層から除外
        if cur_real != home_real and cur_real != temp_real:
            dot_dir = os.path.join(cur, ".nihongo")
            cand = os.path.join(dot_dir, "profile.md")
            if (
                not os.path.islink(dot_dir)
                and not os.path.islink(cand)
                and os.path.isfile(cand)
            ):
                try:
                    cand_real = os.path.normcase(os.path.realpath(cand))
                    inside_cur = os.path.commonpath([cur_real, cand_real]) == cur_real
                except (OSError, ValueError):
                    inside_cur = False
                    cand_real = ""
                if inside_cur and (global_real is None or cand_real != global_real):
                    return os.path.abspath(cand)

        if under_home and cur_real == home_real:
            break
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return None


def _split_profile_sections(raw_text: str) -> tuple[str, dict[str, list[str]], list[str], list[str]]:
    """profile.md を (先頭ヘッダ, 4場面セクション行マップ, 先頭のタグ無しルール行, その他末尾行) に分解する。"""
    text = _normalize_newlines(raw_text)
    if not text.strip():
        return ("# 私の書き方", {}, [], [])
    lines = text.split("\n")
    sections: dict[str, list[str]] = {}
    preamble_headers: list[str] = []
    preamble_rules: list[str] = []
    extra: list[str] = []
    current_scene: str | None = None
    current_level = 2
    seen_any_scene = False

    for line in lines:
        m = _HEADING_RE.match(line)
        if m:
            level = len(m.group(1))
            tag_m = _SCENE_TAG_RE.search(m.group(2))
            if tag_m:
                current_scene = tag_m.group(1).lower()
                current_level = level
                seen_any_scene = True
                sections.setdefault(current_scene, [])
                continue
            if current_scene is not None and level > current_level:
                # `## [work]` 配下の `### サブ見出し` はそのまま現セクションに保持
                sections[current_scene].append(line)
                continue
            if seen_any_scene:
                current_scene = None
        if current_scene is not None:
            sections[current_scene].append(line)
        elif not seen_any_scene:
            if m:
                preamble_headers.append(line)
            elif line.strip():
                preamble_rules.append(line)
        else:
            extra.append(line)

    header = "\n".join(preamble_headers).strip() or "# 私の書き方"
    return (header, sections, preamble_rules, extra)


def _merge_section_lines(base_lines: list[str], overlay_lines: list[str]) -> list[str]:
    """2層のセクション行をフィールド単位でマージする（絶対に言わない表現や口調を結合）。"""
    field_re = re.compile(r"^(\s*[-*・]\s*(?:\*\*)?([^：:]+?)(?:\*\*)?\s*[：:])(.*)$")
    result = [ln for ln in base_lines if ln.strip() != ""]
    label_to_idx: dict[str, int] = {}
    for i, ln in enumerate(result):
        m = field_re.match(ln)
        if m:
            label_to_idx[m.group(2).strip()] = i

    for ln in overlay_lines:
        if not ln.strip():
            continue
        m = field_re.match(ln)
        if m:
            lbl = m.group(2).strip()
            rhs = m.group(3).strip()
            if not rhs:
                continue
            if lbl in label_to_idx:
                idx = label_to_idx[lbl]
                bm = field_re.match(result[idx])
                assert bm is not None
                b_prefix, b_rhs = bm.group(1), bm.group(3).strip()
                if not b_rhs:
                    result[idx] = f"{b_prefix}{rhs}"
                elif unicodedata.normalize("NFKC", rhs) not in unicodedata.normalize("NFKC", b_rhs):
                    sep = "、" if lbl == "絶対に言わない表現" else ("／" if lbl == "一人称" else "。")
                    if sep == "。" and b_rhs.endswith(("。", "！", "!", "？", "?")):
                        result[idx] = f"{b_prefix}{b_rhs}{rhs}"
                    elif sep == "、" and b_rhs.endswith(("、", ",")):
                        result[idx] = f"{b_prefix}{b_rhs}{rhs}"
                    else:
                        result[idx] = f"{b_prefix}{b_rhs}{sep}{rhs}"
                continue
            label_to_idx[lbl] = len(result)
            result.append(ln)
        else:
            if ln not in result:
                result.append(ln)
    return result


def merge_profile_texts(base_text: str | None, overlay_text: str | None) -> str:
    """グローバル profile.md とプロジェクト固有 .nihongo/profile.md を2層マージする。"""
    base_raw = _normalize_newlines(base_text or "").strip()
    over_raw = _normalize_newlines(overlay_text or "").strip()
    if not base_raw and not over_raw:
        return ""
    if not over_raw:
        return base_raw + "\n"
    if not base_raw:
        return over_raw + "\n"

    header, base_secs, base_preamble_rules, base_extra = _split_profile_sections(base_raw)
    _, over_secs, over_preamble_rules, over_extra = _split_profile_sections(over_raw)

    if base_preamble_rules:
        base_secs["common"] = _merge_section_lines(base_preamble_rules, base_secs.get("common", []))
    if over_preamble_rules:
        over_secs["common"] = _merge_section_lines(over_preamble_rules, over_secs.get("common", []))

    out_parts: list[str] = [header]
    for sc in VALID_SCENES:
        if sc not in base_secs and sc not in over_secs:
            continue
        merged_lines = _merge_section_lines(base_secs.get(sc, []), over_secs.get(sc, []))
        block = [f"## [{sc}]", *merged_lines]
        out_parts.append("\n".join(block).rstrip())

    extras = [ln for ln in (*base_extra, *over_extra) if ln.strip()]
    if extras:
        out_parts.append("\n".join(extras))
    return "\n\n".join(out_parts).rstrip("\n") + "\n"


def _split_quoted_tokens(rhs: str) -> list[str]:
    """引用符「...」の内側を守りながら、外側の区切り（、,／/・）で分割する。"""
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


_STRUCT_PLACEHOLDER_RE = re.compile(r"[（(]\s*(?:例|記入例|未記入)\s*(?:[：:][^）)]*)?[）)]")
_STRUCT_SKIP_TOKENS = frozenset({"", "...", "…", "-", "—", "なし", "特になし"})
_KNOWN_PROFILE_LABELS = frozenset({"場面", "一人称", "絶対に言わない表現", "書く時の考え方", "口調・記号"})


def _split_quoted_sentences(text: str) -> list[str]:
    """引用符の内側を守りながら、外側の句点「。」で文を分割する。"""
    quote_pairs = {"「": "」", "『": "』", '"': '"', "'": "'", "“": "”"}
    parts: list[str] = []
    buf: list[str] = []
    closing: str | None = None
    for ch in text:
        if closing is not None:
            buf.append(ch)
            if ch == closing:
                closing = None
            continue
        if ch in quote_pairs:
            closing = quote_pairs[ch]
            buf.append(ch)
            continue
        if ch == "。":
            piece = "".join(buf).strip()
            if piece:
                parts.append(piece)
            buf = []
            continue
        buf.append(ch)
    tail = "".join(buf).strip()
    if tail:
        parts.append(tail)
    return parts


def parse_profile_structured(raw_text: str | None) -> dict[str, dict[str, Any]]:
    """profile.md を 4 場面（common/casual/work/formal）の構造化 dict に変換する。"""
    result: dict[str, dict[str, Any]] = {}
    for sc in VALID_SCENES:
        result[sc] = {
            "scene": sc,
            "first_person": "",
            "forbidden": [],
            "rules": [],
        }
    if not raw_text or not raw_text.strip():
        return result

    _, sections, preamble_rules, _ = _split_profile_sections(raw_text)
    if preamble_rules:
        sections["common"] = [*preamble_rules, *sections.get("common", [])]

    field_re = re.compile(r"^\s*[-*・]\s*(?:\*\*)?([^：:]+?)(?:\*\*)?\s*[：:]\s*(.*)$")
    for sc in VALID_SCENES:
        for line in sections.get(sc, []):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            m = field_re.match(stripped)
            if not m or m.group(1).strip() not in _KNOWN_PROFILE_LABELS:
                clean = stripped.lstrip("-*・ ").strip()
                if clean and clean not in result[sc]["rules"]:
                    result[sc]["rules"].append(clean)
                continue
            lbl = m.group(1).strip()
            rhs = m.group(2).strip()
            if lbl == "場面":
                continue
            if lbl == "一人称":
                if rhs and not rhs.startswith(("（例", "(例")):
                    result[sc]["first_person"] = rhs
                continue
            if lbl == "絶対に言わない表現":
                cleaned_rhs = _STRUCT_PLACEHOLDER_RE.sub("", rhs).strip()
                for tok in _split_quoted_tokens(cleaned_rhs):
                    v = _strip_outer_quotes(tok).strip(" \t\u3000〜～")
                    if v and v not in _STRUCT_SKIP_TOKENS and not v.startswith(("例：", "例:", "記入例")):
                        if v not in result[sc]["forbidden"]:
                            result[sc]["forbidden"].append(v)
                continue
            if rhs:
                cleaned = _STRUCT_PLACEHOLDER_RE.sub("", rhs).strip()
                if cleaned:
                    for part in _split_quoted_sentences(cleaned):
                        if part not in result[sc]["rules"]:
                            result[sc]["rules"].append(part)
    return result


def format_profile_summary(profile_info: dict[str, Any]) -> str:
    """チャット内でAIがそのまま読みやすく出力できる個人ルールの要約Markdownを返す。"""
    if not profile_info.get("exists"):
        pending = int(profile_info.get("pending_inbox_count") or 0)
        lines = ["個人ルール（`profile.md`）はまだ作成されていません。"]
        if pending > 0:
            lines.append(f"承認待ちの候補が {pending} 件あります。「承認待ち見せて」と声をかけると確認・反映できます。")
        else:
            lines.append("普段どおり文章を直しつつ、「〇〇は使わない」と伝えると少しずつ育ちます。")
        return "\n".join(lines)

    scene_labels = {
        "common": "共通（全場面）",
        "work": "社内・同僚",
        "formal": "社外・目上",
        "casual": "普段・雑談",
    }
    raw = str(profile_info.get("markdown") or profile_info.get("raw") or "")
    structured = parse_profile_structured(raw)
    filter_scene = profile_info.get("scene")
    target_scenes = (
        ["common", filter_scene]
        if filter_scene in ("work", "formal", "casual")
        else (["common"] if filter_scene == "common" else ["common", "work", "formal", "casual"])
    )

    lines: list[str] = ["### 今のあなたの日本語ルール"]
    if profile_info.get("project_profile_path"):
        lines.append("（共通ルール＋この作業フォルダの案件別ルールを2層で適用中）")

    any_content = False
    for sc in target_scenes:
        sec = structured.get(sc) or {}
        fp = str(sec.get("first_person") or "").strip()
        forb = list(sec.get("forbidden") or [])
        rules = list(sec.get("rules") or [])
        if not fp and not forb and not rules:
            continue
        any_content = True
        lines.append(f"\n**{scene_labels.get(sc, sc)}**")
        if sc == "common" and fp:
            lines.append(f"- 一人称：{fp}")
        if forb:
            joined = "、".join(f"「{w}」" for w in forb)
            lines.append(f"- 避ける表現：{joined}")
        for r in rules:
            lines.append(f"- {r}")

    if not any_content:
        lines.append("登録済みのルールはまだありません。")

    pending = int(profile_info.get("pending_inbox_count") or 0)
    if pending > 0:
        lines.append(f"\n承認待ちの候補が {pending} 件あります。「承認待ち見せて」で確認・承認できます。")
    return "\n".join(lines)


def remove_forbidden_from_profile(
    *,
    scene: str,
    value: str,
    storage: ProfileStorage | None = None,
    profile_path: str | None = None,
) -> dict[str, Any]:
    """指定場面の「絶対に言わない表現」から1語を外科的に削除する（他行は一切触らない）。"""
    sc = scene.strip().lower()
    if sc not in VALID_SCENES:
        raise ValueError(f"不正な scene です: {scene!r}")
    needle = unicodedata.normalize("NFKC", _strip_outer_quotes(_normalize_value(value))).strip(" \t\u3000〜～")
    if not needle:
        raise ValueError("削除する表現が空です。")

    store = _resolve_storage(storage, profile_path=profile_path)
    raw = store.read_profile_text()
    if not raw:
        return {"removed": False, "message": "profile.md がまだありません。"}

    lines = _normalize_newlines(raw).split("\n")
    bounds = _find_section_bounds(lines, sc)
    if bounds is None:
        return {"removed": False, "message": f"[{sc}] セクションが見つかりませんでした。"}

    sec_start, sec_end = bounds
    field_re = re.compile(r"^(\s*[-*・]\s*(?:\*\*)?絶対に言わない表現(?:\*\*)?\s*[：:])(.*)$")
    removed = False
    for idx in range(sec_start + 1, sec_end):
        m = field_re.match(lines[idx])
        if not m:
            continue
        prefix, rhs = m.group(1), m.group(2).strip()
        kept: list[str] = []
        for tok in _split_quoted_tokens(rhs):
            norm_tok = unicodedata.normalize("NFKC", _strip_outer_quotes(tok)).strip(" \t\u3000〜～")
            if norm_tok == needle:
                removed = True
                continue
            kept.append(tok)
        if removed:
            lines[idx] = f"{prefix}{'、'.join(kept)}" if kept else prefix
            break

    if removed:
        updated = "\n".join(lines).rstrip("\n") + "\n"
        store.write_profile_text(updated)
        return {"removed": True, "message": f"「{value}」を削除しました。"}
    return {"removed": False, "message": f"「{value}」は [{sc}] に見つかりませんでした。"}


def detect_sync_folders(home_dir: str | None = None) -> list[dict[str, str]]:
    """PC 内に既にある Google Drive / Dropbox / iCloud Drive / OneDrive の同期フォルダ候補を検出する。"""
    home = os.path.abspath(os.path.expanduser(home_dir or "~"))
    candidates: list[tuple[str, str]] = []

    # Google Drive (Windows の仮想ドライブレターは実機かつ home_dir 未指定時のみ探索)
    if os.name == "nt" and home_dir is None:
        for drive_letter in ("G", "H", "I"):
            for sub in ("マイドライブ", "My Drive"):
                candidates.append(("Google Drive", f"{drive_letter}:\\{sub}"))
    candidates.extend([
        ("Google Drive", os.path.join(home, "Google Drive", "My Drive")),
        ("Google Drive", os.path.join(home, "Google Drive", "マイドライブ")),
        ("Google Drive", os.path.join(home, "Google ドライブ")),
    ])
    cloud_storage = os.path.join(home, "Library", "CloudStorage")
    if os.path.isdir(cloud_storage):
        try:
            for name in sorted(os.listdir(cloud_storage)):
                if name.startswith("GoogleDrive-"):
                    for sub in ("マイドライブ", "My Drive"):
                        candidates.append(("Google Drive", os.path.join(cloud_storage, name, sub)))
        except OSError:
            pass

    # Dropbox / iCloud Drive / OneDrive
    candidates.extend([
        ("Dropbox", os.path.join(home, "Dropbox")),
        ("iCloud Drive", os.path.join(home, "Library", "Mobile Documents", "com~apple~CloudDocs")),
        ("iCloud Drive", os.path.join(home, "iCloudDrive")),
        ("OneDrive", os.path.join(home, "OneDrive")),
    ])

    found: list[dict[str, str]] = []
    seen_roots: set[str] = set()
    for provider, root in candidates:
        try:
            if not os.path.isdir(root):
                continue
            norm = os.path.normcase(os.path.realpath(root))
        except OSError:
            continue
        if norm in seen_roots:
            continue
        seen_roots.add(norm)
        found.append({
            "provider": provider,
            "root": os.path.abspath(root),
            "suggested_home": os.path.join(os.path.abspath(root), "nihongo"),
        })
    return found


def read_profile(
    *,
    profile_path: str | None = None,
    inbox_path: str | None = None,
    scene: str | None = None,
    storage: ProfileStorage | None = None,
    project_dir: str | None = None,
    include_project: bool = False,
) -> dict[str, Any]:
    """profile.md の生テキスト・セクション別内容・保留中 inbox 件数を返す（2層マージ対応）。"""
    store = _resolve_storage(storage, profile_path=profile_path, inbox_path=inbox_path)
    p_path = store.profile_location
    loaded = store.read_profile_text()
    global_exists = loaded is not None
    global_raw = _normalize_newlines(loaded) if loaded is not None else ""

    proj_path: str | None = None
    proj_raw = ""
    if project_dir is not None or include_project:
        cand_proj = find_project_profile(project_dir, global_profile_path=p_path)
        if cand_proj and os.path.isfile(cand_proj):
            try:
                if os.path.getsize(cand_proj) <= MAX_PROJECT_PROFILE_BYTES:
                    with open(cand_proj, encoding="utf-8-sig") as f:
                        proj_raw = _normalize_newlines(f.read())
                    proj_path = cand_proj
            except (OSError, UnicodeDecodeError):
                proj_path = None
                proj_raw = ""

    exists = global_exists or bool(proj_path)
    if proj_path:
        raw = merge_profile_texts(global_raw, proj_raw)
    else:
        raw = global_raw

    sections: dict[str, str] = {}
    if raw:
        lines = raw.split("\n")
        for sc in VALID_SCENES:
            bounds = _find_section_bounds(lines, sc)
            if bounds is not None:
                s, e = bounds
                sections[sc] = "\n".join(lines[s:e]).strip()

    pending_count = len(list_inbox(status="pending", storage=store))

    filtered_markdown = raw
    if scene:
        sc = scene.strip().lower()
        if sc not in VALID_SCENES:
            raise ValueError(f"不正な scene です: {scene!r}")
        parts: list[str] = []
        if "common" in sections:
            parts.append(sections["common"])
        if sc != "common" and sc in sections:
            parts.append(sections[sc])
        filtered_markdown = "\n\n".join(parts)

    layers: list[str] = []
    if global_exists:
        layers.append(p_path)
    if proj_path:
        layers.append(proj_path)

    return {
        "exists": exists,
        "global_exists": global_exists,
        "profile_path": p_path,
        "project_profile_path": proj_path,
        "layers": layers,
        "scene": scene.lower() if scene else None,
        "pending_inbox_count": pending_count,
        "sections": sections,
        "markdown": filtered_markdown,
        "raw": raw,
        "global_raw": global_raw,
    }
