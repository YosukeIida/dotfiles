#!/usr/bin/env python3
"""文より先にメモを残し、書き換えないバージョンを積む記録用 CLI。"""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
import time
import unicodedata


# references/tag-vocabulary.md の語だけを既定にする。
RELATIONS = set("順接 逆接 添加 対比 転換 同列 補足 連鎖 段落の始まり".split())
IMPORTANCE = {"核", "衛星"}
# 説明文の役割（木戸の6つ）。1文に3つ以上付いたら、分けられないかを確かめるよう警告する（1文が複数の性質を併せ持つことがあるため）
EXPOSITORY_ROLES = set("主張 評価 理由 根拠 解説 報告".split())
ROLES = set("主張 評価 理由 根拠 解説 報告 外面 感覚 内面 生の声 語り 直接話法 間接話法 自由間接話法 直接思考 自由間接思考".split())
# 工夫は文章の種類ごとに分かれる。説明文の役割の文に小説の工夫（またはその逆）が付いたら取り違えとして警告する
# （見本で「文長を揺らす」を説明文に付けていた）
NOVEL_TECHNIQUES = set("シャレード 描写 記号での回収 フォーカスの予告 五感 欠落を書く 文長を揺らす".split())
EXPOSITORY_TECHNIQUES = set("関係の明示 否定の根拠 対比定義 譲歩 命題の書き出し 誤解の先回り".split())
TECHNIQUES = set("シャレード 描写 記号での回収 フォーカスの予告 五感 欠落を書く 文長を揺らす 関係の明示 否定の根拠 対比定義 譲歩 命題の書き出し 誤解の先回り".split())
CONTAINERS = {"note", "list", "quote", "footnote"}
# 注記の箱の書き方は媒体ごとに違うので、記録は意味（info＝情報・warn＝注意・alert＝警告）で持ち、書き出しで方言に変える。
# 既定は GitHub の Markdown。Zenn の箱は2種類しかないので、注意と警告はどちらも alert にする
FLAVORS = ("gfm", "qiita", "zenn")
NOTE_OPEN = {
    "gfm": {"info": "> [!NOTE]", "warn": "> [!WARNING]", "alert": "> [!CAUTION]"},
    "qiita": {"info": ":::note info", "warn": ":::note warn", "alert": ":::note alert"},
    "zenn": {"info": ":::message", "warn": ":::message alert", "alert": ":::message alert"},
}
# ラベルは書き出す Markdown の [^ラベル] にそのまま入るので、空白や括弧を含めない
FOOTNOTE_LABEL = re.compile(r"[A-Za-z0-9_-]+")
# 呼び出しは広めに拾う。ラベルの規則に合わない呼び出しも「脚注が無い」として検出させるため。「]:」は脚注の定義側なので外す
FOOTNOTE_REFERENCE = re.compile(r"\[\^([^\]\s]+)\](?!:)")
# インラインコード（`…`）の中の [^ラベル] は呼び出しではなく、書き方の説明（SKILL.md 自身の記録で見つかった）
INLINE_CODE = re.compile(r"`[^`]*`")


def _identifier(value, prefix, width):
    if not isinstance(value, str) or not re.fullmatch(prefix + r"[0-9]+", value):
        raise ValueError(f"不正な ID: {value!r}")
    number = int(value[len(prefix):])
    if number < 1 or value != f"{prefix}{number:0{width}d}":
        raise ValueError(f"不正な ID: {value!r}")
    return value


def _sid(value):
    """文またはブロックの ID を検査する。"""
    return _identifier(value, "b" if isinstance(value, str) and value.startswith("b") else "s", 4)


def _unit_directory(root, sid):
    """文またはブロックの保存先を返す。"""
    return root / ("blocks" if _sid(sid).startswith("b") else "sentences") / sid


def _ver(value):
    return _identifier(value, "v", 3)


def _version_number(value):
    if not isinstance(value, str) or not re.fullmatch(r"[vrd][0-9]+", value):
        raise ValueError(f"不正なバージョン: {value!r}")
    return int(_identifier(value, value[0], 3)[1:])


def _comment_since(comment):
    return max((comment.get(field) or comment["ver"]
                for field in ("ver", "reopened_at_ver", "posted_latest")), key=_version_number)


def _read_json(path):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as error:
        raise ValueError(f"{path}: 壊れた JSON: {error}") from error
    except RecursionError as error:
        # 入れ子の深すぎる JSON。人から受け取った記録で命令ごと落ちないよう、壊れた JSON として扱う
        raise ValueError(f"{path}: 壊れた JSON: 入れ子が深すぎます") from error
    if not isinstance(value, dict):
        raise ValueError(f"{path}: JSON オブジェクトが必要です")
    return value


def _sync_directory(path):
    # Windows はフォルダを os.open できないが、ファイル自体の fsync は維持する。
    if os.name == "nt":
        return
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _atomic_write(path, text, *, immutable=False):
    # shortcut: ADR-0001 の単一ライターを前提とする、CLI を並行実行するときは排他を加える。
    if immutable and path.exists():
        raise ValueError(f"確定済みのバージョンは上書きできません: {path.name}")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="", prefix=".tmp-",
            dir=path.parent, delete=False,
        ) as stream:
            temporary = Path(stream.name)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        _sync_directory(path.parent)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _write_json(path, value, *, immutable=False):
    _atomic_write(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                  immutable=immutable)


def _numbered(directory, prefix, width, suffix):
    found = []
    for path in directory.glob(f"{prefix}*{suffix}"):
        name = path.name.removesuffix(suffix)
        if re.fullmatch(prefix + r"[0-9]+", name):
            _identifier(name, prefix, width)
            found.append(path)
    return sorted(found, key=lambda path: int(path.name.removesuffix(suffix)[len(prefix):]))


def _next_name(directory, prefix, width, suffix):
    paths = _numbered(directory, prefix, width, suffix)
    number = int(paths[-1].name.removesuffix(suffix)[len(prefix):]) + 1 if paths else 1
    return f"{prefix}{number:0{width}d}"


def _order(root):
    value = _read_json(root / "order.json")
    if (not isinstance(value.get("document"), str)
            or not isinstance(value.get("order"), list)
            or not isinstance(value.get("retired"), list)):
        raise ValueError("order.json: document・order・retired が必要です")
    for sid in value["order"]:
        _sid(sid)
    if len(set(value["order"])) != len(value["order"]):
        raise ValueError("order.json: 文 ID が重複しています")
    for entry in value["retired"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("into"), list):
            raise ValueError("order.json: retired の into は移行先 ID の配列です")
        # retire はブロックも外すが、分ける・まとめる（into）の元と先になれるのは文だけ
        if _sid(entry.get("sid")).startswith("b") and entry["into"]:
            raise ValueError(f"order.json: ブロック {entry['sid']} は分割・統合の元にできません")
        for sid in entry["into"]:
            _identifier(sid, "s", 4)
    return value


def _requirement_items(text):
    """要件定義書の `## <番号>. <項目名>` の見出しを検査し、番号と項目名の組を返す（ADR-0003）。

    見出しの形が崩れると、アプリが一文から項目を切り出せない。
    項目名が9項目と合うかは見ない（中身の基準はリファレンスが持ち、ここは形だけを見る）。
    """
    items = []
    for line in text.splitlines():
        if not line.startswith("## "):
            continue
        match = re.fullmatch(r"## ([0-9]+)\. (\S.*)", line.rstrip())
        if not match:
            raise ValueError(f"要件定義書の見出しは「## <番号>. <項目名>」にしてください: {line.strip()}")
        items.append((int(match[1]), match[2].strip()))
    if not items:
        raise ValueError("要件定義書に「## <番号>. <項目名>」の見出しがありません")
    if [number for number, _ in items] != list(range(1, len(items) + 1)):
        raise ValueError("要件定義書の項目の番号は 1 から順に振ってください")
    return items


def _design_paragraphs(text):
    """設計書の頭の `要件定義書: rNNN` と、`## p<番号> <主張>` の見出しを検査する（ADR-0003）。

    戻り値は（基づく要件定義書のバージョン, 段落の番号の一覧）。
    頭の1行の書式は ADR に無く、スクリプトの側で決めた。見出しより前の最初の行に置く。
    """
    lines = text.splitlines()
    head = next((line.strip() for line in lines if line.strip()), "")
    match = re.fullmatch(r"要件定義書: (r[0-9]+)", head)
    if not match:
        raise ValueError("設計書の最初の行に「要件定義書: rNNN」を書いてください")
    based_on = _identifier(match[1], "r", 3)
    paragraphs = []
    for line in lines:
        if not line.startswith("## "):
            continue
        heading = re.fullmatch(r"## (p[0-9]+) (\S.*)", line.rstrip())
        if not heading:
            raise ValueError(f"設計書の見出しは「## p<番号> <その段落の主張>」にしてください: {line.strip()}")
        paragraphs.append(heading[1])
    if not paragraphs:
        raise ValueError("設計書に「## p<番号> <その段落の主張>」の見出しがありません")
    if paragraphs != [f"p{number}" for number in range(1, len(paragraphs) + 1)]:
        raise ValueError("設計書の段落の番号は p1 から順に振ってください")
    return based_on, paragraphs


DOC_KINDS = {"requirements": ("r", 3), "design": ("d", 3)}


def _doc_versions(root, kind):
    """要件定義書（requirements）か設計書（design）のバージョンのパスを古い順に返す。"""
    prefix, width = DOC_KINDS[kind]
    directory = root / kind
    return _numbered(directory, prefix, width, ".md") if directory.is_dir() else []


def _doc_sections(text, kind):
    """要件定義書を項目の番号（"8"）ごとに、設計書を段落の id（"p2"）ごとに分け、{番号か id: 見出しと本文} を返す。

    コメントの宛先と、項目が直されたかの比べに使う。見出しの形の検査は _requirement_items・_design_paragraphs が受け取るときに済んでいる。
    """
    pattern = r"## ([0-9]+)\. \S.*" if kind == "requirements" else r"## (p[0-9]+) \S.*"
    sections, key = {}, None
    for line in text.splitlines():
        match = re.fullmatch(pattern, line.rstrip())
        if match:
            key = match[1]
            sections[key] = [line.rstrip()]
        elif key is not None:
            sections[key].append(line.rstrip())
    return {key: "\n".join(lines).strip() for key, lines in sections.items()}


def _doc_comment_target(root, kind, ver, item):
    """要件定義書・設計書へのコメントの宛先を確かめ、宛先の見出しと本文を返す（ADR-0005）。無い宛先は ValueError。"""
    if kind not in DOC_KINDS:
        raise ValueError(f"コメントの宛先の種類は requirements か design にしてください: {kind}")
    prefix, width = DOC_KINDS[kind]
    path = root / kind / f"{_identifier(ver, prefix, width)}.md"
    if not path.is_file():
        raise ValueError(f"{ver} がありません")
    sections = _doc_sections(path.read_text(encoding="utf-8"), kind)
    if not isinstance(item, str) or item not in sections:
        raise ValueError(f"{ver} に {item} の{'項目' if kind == 'requirements' else '段落'}がありません")
    return sections[item]


def _doc_comment(root, comment):
    """要件定義書・設計書へのコメントを、文のコメントと同じ形の読み方で返す（ADR-0005）。

    対応済みは、コメントの起点（投稿時・開き直し時の最新があればそれも含む）より新しいバージョンで、
    その項目（段落）の見出しと本文が変わったときだけにする。要件定義書は文書全体でバージョンが進むので、
    別の項目だけを直したバージョンで対応済みにすると、直していない項目へのコメントが黙って閉じる。
    """
    kind, item = comment.get("doc"), comment.get("item")
    if not isinstance(comment.get("text"), str):
        raise ValueError("コメントの text がありません")
    try:
        _doc_comment_target(root, kind, comment.get("ver"), item)
    except ValueError:
        return {**comment, "current_text": None, "note": "行き先の無いコメント"}
    paths = _doc_versions(root, kind)
    latest = paths[-1].stem
    current = _doc_sections(paths[-1].read_text(encoding="utf-8"), kind).get(item)
    since = _comment_since(comment)
    before = _doc_sections((root / kind / f"{since}.md").read_text(encoding="utf-8"), kind).get(item) \
        if (root / kind / f"{since}.md").is_file() else None
    addressed = (comment.get("status") == "open"
                 and _version_number(latest) > _version_number(since) and current != before)
    note = None if current is not None else "最新のバージョンに無い項目へのコメント"
    return {**comment, **({"status": "resolved", "addressed_by": latest} if addressed else {}),
            "current_text": current, "note": note}


def _sentence_path(root, sid, ver):
    """文またはブロックの確定版のパスを返す。"""
    return _unit_directory(root, sid) / f"{_ver(ver)}.json"


def _versions(root, sid):
    """文またはブロックの確定版を古い順に返す。"""
    return _numbered(_unit_directory(root, sid), "v", 3, ".json")


def _latest(root, sid):
    paths = _versions(root, sid)
    if not paths:
        raise ValueError(f"{sid}: 確定した文がありません")
    return _read_json(paths[-1])


def _next_version(root, sid):
    """未確定のメモが無いことを確かめ、次の版を返す。"""
    directory = _unit_directory(root, sid)
    memos = _numbered(directory, "v", 3, "-memo.json")
    if any(not (directory / path.name.replace("-memo", "")).exists() for path in memos):
        raise ValueError(f"{sid}: まだ文の無いメモがあります")
    return _next_name(directory, "v", 3, ".json")


def _vocabulary(root):
    vocabulary = {"relation": RELATIONS.copy(), "role": ROLES.copy(),
                  "importance": IMPORTANCE, "technique": TECHNIQUES}
    path = root / "vocab.json"
    if path.exists():
        extra = _read_json(path)
        for field in ("relation", "role"):
            words = extra.get(field, [])
            if not isinstance(words, list) or any(not isinstance(word, str) or not word for word in words):
                raise ValueError(f"vocab.json: {field} は語の配列にしてください")
            vocabulary[field].update(words)
    return vocabulary


def _validate_tags(tags, vocabulary, *, warn=False):
    if not isinstance(tags, dict):
        raise ValueError("tags は JSON オブジェクトにしてください")
    extra = tags.keys() - {"relation", "importance", "role", "technique", "place"}
    if extra:
        raise ValueError(f"文機能に許可されていないキーがあります: {', '.join(sorted(extra))}")
    for field in ("relation", "importance", "place"):
        if not isinstance(tags.get(field), str) or not tags[field].strip():
            raise ValueError(f"tags.{field} は空でない文字列にしてください")
    for field in ("role", "technique"):
        words = tags.get(field)
        if not isinstance(words, list) or any(not isinstance(word, str) or not word.strip() for word in words):
            raise ValueError(f"tags.{field} は語の配列にしてください")
    for field in ("relation", "importance"):
        if tags[field] not in vocabulary[field]:
            raise ValueError(f"tags.{field}: 語彙の外の語です: {tags[field]}")
    if warn:
        for field in ("role", "technique"):
            for word in tags[field]:
                if word not in vocabulary[field]:
                    print(f"警告: tags.{field}: 語彙の外の語です: {word}", file=sys.stderr)
        expository = [word for word in tags["role"] if word in EXPOSITORY_ROLES]
        novel = [word for word in tags["role"] if word in ROLES and word not in EXPOSITORY_ROLES]
        for word in tags["technique"]:
            if expository and word in NOVEL_TECHNIQUES:
                print(f"警告: tags.technique: 「{word}」は小説の工夫です。説明文の役割（{'・'.join(expository)}）の文に付いています", file=sys.stderr)
            if novel and word in EXPOSITORY_TECHNIQUES:
                print(f"警告: tags.technique: 「{word}」は説明文の工夫です。小説の役割（{'・'.join(novel)}）の文に付いています", file=sys.stderr)
        if len(expository) >= 3:
            print(f"警告: tags.role: 役割が3つ以上あります（{'・'.join(tags['role'])}）。文を分けられないか確認してください", file=sys.stderr)


def _validate_block(block, text):
    """ブロックの種類・属性と、種類に応じた本文を検査する。"""
    if not isinstance(block, dict) or not isinstance(block.get("kind"), str):
        raise ValueError("block.kind にブロックの種類を指定してください")
    kind = block["kind"]
    if kind not in CONTAINERS | {"heading", "code", "image", "table"}:
        raise ValueError(f"ブロックの種類が不正です: {kind}")
    if kind == "heading" and (type(block.get("level")) is not int or not 1 <= block["level"] <= 4):
        raise ValueError("block.level は 1〜4 の整数にしてください")
    if kind == "code" and not isinstance(block.get("lang"), str):
        raise ValueError("block.lang は文字列にしてください")
    if kind == "note" and block.get("type") not in ("info", "warn", "alert"):
        raise ValueError("block.type は info・warn・alert にしてください")
    if kind == "list" and type(block.get("ordered")) is not bool:
        raise ValueError("block.ordered は真偽値にしてください")
    if kind == "footnote" and not (isinstance(block.get("label"), str) and FOOTNOTE_LABEL.fullmatch(block["label"])):
        raise ValueError("block.label は英数字・ハイフン・下線だけの文字列にしてください")
    if kind in CONTAINERS:
        if text != "":
            raise ValueError("入れ物のブロックの本文は空文字列にしてください")
    elif not isinstance(text, str) or not text.strip():
        raise ValueError("ブロックの本文は空でない文字列にしてください")


def _validate_block_tags(tags):
    """ブロックには対応要件だけを付け、文のための文機能を拒む。"""
    if not isinstance(tags, dict):
        raise ValueError("tags は JSON オブジェクトにしてください")
    if not isinstance(tags.get("place"), str) or not tags["place"].strip():
        raise ValueError("tags.place は空でない文字列にしてください")
    if {"relation", "importance", "role", "technique"} & tags.keys():
        raise ValueError("ブロックの文機能には relation・importance・role・technique を付けないでください")
    if tags.keys() - {"place"}:
        raise ValueError("ブロックの文機能には place 以外のキーを付けないでください")


def _validate_container(root, bid):
    """指し先の最新ブロックが入れ物であることを確かめる。"""
    _identifier(bid, "b", 4)
    container = _latest(root, bid)
    _validate_block(container.get("block"), container.get("text"))
    if container["block"]["kind"] not in CONTAINERS:
        raise ValueError(f"{bid}: 入れ物のブロックではありません")


def _place_sentence(order, sid, after=None, origins=()):
    """文またはブロックを並べ、文の分割・統合では元の文を退役させる。"""
    if sid.startswith("b") and origins:
        raise ValueError("ブロックには --from を指定できません")
    if after and origins:
        raise ValueError("--after と --from は同時に指定できません")
    if after and _sid(after) not in order["order"]:
        raise ValueError(f"--after の文が order にありません: {after}")
    retired = {entry["sid"]: entry for entry in order["retired"]}
    for origin in origins:
        _identifier(origin, "s", 4)
        if origin == sid or (origin not in order["order"] and origin not in retired):
            raise ValueError(f"--from の元の文がありません: {origin}")
    if sid in retired:
        raise ValueError(f"{sid}: 置き換えられた文です。新しい ID を使ってください")
    if sid in order["order"]:
        if after or origins:
            raise ValueError("--after と --from は新しい文だけに指定できます")
        return
    if origins:
        positions = [order["order"].index(origin) for origin in origins if origin in order["order"]]
        # 分割の2文目以降は、同じ元の文から先に確定した移行先の後ろに置く。
        destinations = [target for origin in origins if origin in retired
                        for target in retired[origin]["into"] if target in order["order"]]
        if not positions and not destinations:
            raise ValueError("--from の移行先が order にありません")
        position = min(positions) if positions else max(order["order"].index(target) for target in destinations) + 1
        order["order"].insert(position, sid)
        order["order"] = [item for item in order["order"] if item not in origins]
        for origin in origins:
            if origin in retired:
                retired[origin]["into"].append(sid)
            else:
                # at は外した時刻。これより前に付いたコメントを、外したことで対応したとみなす（_comments）
                entry = {"sid": origin, "into": [sid], "at": time.time_ns()}
                order["retired"].append(entry)
                retired[origin] = entry
    elif after:
        order["order"].insert(order["order"].index(after) + 1, sid)
    else:
        order["order"].append(sid)


def _init(document):
    document = Path(document).absolute()
    if not document.parent.is_dir():
        raise ValueError(f"文書の親フォルダがありません: {document.parent}")
    # TSUZURI_NO_GITIGNORE=1 のときは .gitignore に触らない。外のモデルに書かせるワーカーは、文書のフォルダの外
    # （git のいちばん上）を書き換えさせないためにこれを立てる。除外の行は、親が記録を確かめてから足す
    result = None
    if os.environ.get("TSUZURI_NO_GITIGNORE") != "1":
        try:
            result = subprocess.run(["git", "-C", str(document.parent), "rev-parse", "--show-toplevel"],
                                    capture_output=True, text=True, check=False)
        except FileNotFoundError:
            result = None
    if result is not None and result.returncode == 0:
        ignore = Path(result.stdout.strip()) / ".gitignore"
        previous = ignore.read_text(encoding="utf-8") if ignore.exists() else ""
        if "*.tsuzuri/" not in previous.splitlines():
            _atomic_write(ignore, previous + ("\n" if previous and not previous.endswith("\n") else "") + "*.tsuzuri/\n")
    root = Path(str(document) + ".tsuzuri")
    for name in ("requirements", "design", "sentences", "blocks", "comments", "reviews"):
        (root / name).mkdir(parents=True, exist_ok=True)
    if not (root / "order.json").exists():
        _write_json(root / "order.json", {"document": str(document), "order": [], "retired": []}, immutable=True)
    else:
        _order(root)
    _sync_directory(root.parent)
    try:
        register_record(root)
    except (OSError, ValueError) as error:
        # 一覧に載らなくても記録は作れている。アプリでパスを入れれば開けるので、知らせるだけにする
        print(f"警告: 記録の一覧に足せませんでした: {error}", file=sys.stderr)
    print(root)


def registry_path():
    """作った記録の一覧のファイル。閲覧アプリがこの一覧から記録を開く（AI 経由でしか開けないと不便なため）。

    記録は文書の隣に散らばるので、毎回フォルダを探さず、作ったときと開いたときに足しておく。
    TSUZURI_REGISTRY で置き場を替えられる（試験が利用者の一覧を書き換えないため）。
    """
    custom = os.environ.get("TSUZURI_REGISTRY")
    if custom:
        return Path(custom)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "tsuzuri" / "records.json"


def _config_dir():
    """利用者の設定の置き場（XDG_CONFIG_HOME が無ければ ~/.config）の下の tsuzuri フォルダ。"""
    return Path(os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")) / "tsuzuri"


def user_dictionary_path():
    """利用者の校正辞書のパス。まだ無くても、置く場所として返す（アプリが置き場を案内するため）。

    TSUZURI_WORDS で置き場を替えられる（試験が利用者の校正辞書を読まないため）。
    """
    custom = os.environ.get("TSUZURI_WORDS")
    return Path(custom).expanduser() if custom else _config_dir() / "words.tsv"


def _default_words_path():
    return Path(__file__).resolve().parent.parent / "references" / "words.tsv"


def _compile_pattern(text):
    """校正辞書の探す形を正規表現にする。(パターン, None) か、読めないとき (None, 例外) を返す。

    re.error だけでなく、繰り返しの数が大きすぎる形（a{4294967296}）は OverflowError、
    括弧の入れ子が深すぎる形は RecursionError になる。利用者が書く表なので、どれも行の誤りとして扱う。
    """
    try:
        return re.compile(text), None
    except (re.error, OverflowError, RecursionError) as error:
        return None, error


def words_paths():
    """「語をそろえる」で読む校正辞書。同梱の既定の辞書と、利用者の辞書の順に返す（利用者の辞書が無ければ既定だけ）。

    既定の辞書は、定着した外来語を和訳しすぎた語だけを持つ（誰が書いても直したい語）。熟語寄りかどうかのような好みと、
    その文章だけの呼び名は利用者の辞書に置く。好みは配る相手ごとに違うので、配布物に入れない。
    """
    return [path for path in (_default_words_path(), user_dictionary_path()) if path.is_file()]


def dictionary_rows():
    """校正辞書の行を、アプリに見せる形（探す形・直す先・補足・出どころ・場所）で返す。

    _word_rules と違い、壊れた行でも止めずに error を付けて返す（見る画面が1行の誤りで全部出なくなるのを避ける）。
    """
    rows = []
    for path in words_paths():
        # 画面に出す札。使う人から見た呼び名にする（「同梱」は配る側の言い方だった）。
        # 置き場のフォルダ名で決めると、利用者の辞書を references という名のフォルダに置いたときに標準と出るので、パスで比べる
        source = "標準" if path == _default_words_path() else "自分"
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError) as error:
            rows.append({"pattern": "", "to": "", "note": "", "source": source, "where": str(path),
                         "error": f"ファイルを読めない（UTF-8 で保存されているか確認）: {error}"})
            continue
        for number, line in enumerate(lines, 1):
            if not line.strip() or line.startswith("#"):
                continue
            cells = (line.split("\t") + ["", ""])[:3]
            row = {"pattern": cells[0], "to": cells[1], "note": cells[2], "source": source, "where": f"{path}:{number}"}
            if not cells[0] or not cells[1]:
                row["error"] = "「探す形<TAB>直す先」の形になっていない"
            else:
                _pattern, error = _compile_pattern(cells[0])
                if error:
                    row["error"] = f"探す形が正規表現として読めない: {error}"
            rows.append(row)
    return rows


def template_dirs():
    """同梱のテンプレートの置き場と、利用者のテンプレートの置き場を返す。利用者の置き場はまだ無くても返す。

    TSUZURI_TEMPLATES で利用者の置き場を替えられる（試験が利用者のテンプレートを読まないため）。
    """
    custom = os.environ.get("TSUZURI_TEMPLATES")
    return Path(__file__).resolve().parent.parent / "references" / "templates", Path(custom).expanduser() if custom else _config_dir() / "templates"


def template_paths():
    """テンプレート（本文の見出しの骨組み）を、名前ごとに1つ返す（{名前: パス}）。同梱のテンプレートに利用者のものを重ね、同じ名前なら利用者のものを使う。

    同梱のテンプレートは誰に配っても通じる骨組みだけを持つ。会社名や筆名の入ったテンプレート（社内の記事のものなど）は配る相手ごとに違うので、
    利用者の置き場（~/.config/tsuzuri/templates/）に置く。
    """
    found = {}
    for folder in template_dirs():
        if folder.is_dir():
            for path in sorted(folder.glob("*.md")):
                if path.is_file():   # *.md という名前のフォルダは飛ばす
                    found[path.stem] = path
    return found


# テンプレートは見出しの骨組みだけで数 KB に収まる。これを超えるファイルは置き間違いとみなし、画面と AI に丸ごと渡さない
TEMPLATE_MAX_BYTES = 256 * 1024


def read_template(path):
    """テンプレートの中身を返す。大きすぎる・UTF-8 で読めないときは ValueError（OSError はそのまま）。"""
    if path.stat().st_size > TEMPLATE_MAX_BYTES:
        raise ValueError(f"{path} が大きすぎます（{TEMPLATE_MAX_BYTES // 1024} KB まで）")
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{path} を UTF-8 で読めません: {error}") from None


def template_scene(text):
    """テンプレートの中身から、見出しの次の1行（使う場面）を返す。テンプレートを選ぶときに中身を全部読まずに済むように。"""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return next((line for line in lines[1:] if not line.startswith("#")), "")


def _templates(name=None):
    """名前を省くとテンプレートの一覧（名前・使う場面・置き場）を、名前を渡すとそのテンプレートの中身を出す。"""
    paths = template_paths()
    if name is not None:
        if name not in paths:
            raise ValueError(f"テンプレートがありません: {name}（一覧は templates）")
        print(read_template(paths[name]), end="")
        return
    if not paths:
        print("テンプレートがありません")
    for stem, path in paths.items():
        try:
            scene = template_scene(read_template(path))
        except (ValueError, OSError) as error:
            scene = f"（読めない: {error}）"
        print(f"{stem}\t{scene}\t{path}")


def _word_rules():
    """校正辞書を (探す形, 直す先, 補足, 出どころ) の並びにする。1行は「探す形<TAB>直す先<TAB>補足」で、# の行は読まない。

    探す形は Python の正規表現。壊れた行は、どの表の何行目かを添えて ValueError にする（黙って飛ばすと、直したつもりの語が検査から漏れる）。
    """
    rules = []
    for path in words_paths():
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip() or line.startswith("#"):
                continue
            cells = line.split("\t")
            if len(cells) < 2 or not cells[0] or not cells[1]:
                raise ValueError(f"{path}:{number}: 「探す形<TAB>直す先」の形になっていません")
            pattern, error = _compile_pattern(cells[0])
            if error:
                raise ValueError(f"{path}:{number}: 探す形が正規表現として読めません: {error}")
            rules.append((pattern, cells[1], cells[2] if len(cells) > 2 else "", path.name if path == _default_words_path() else "利用者の校正辞書"))
    return rules


def _words(root, order):
    """最新のバージョンの文・執筆意図・ブロックの字に校正辞書を当て、当たった所を1行ずつ出す。当たった数を返す。

    直すかどうかは書き手が前後を読んで決める（「お題」の題や本物の窓のような、同じ字で別の意味の語があるため）。
    """
    rules = _word_rules()
    hits = 0
    for sid in order["order"]:
        unit = _latest(root, sid)
        memo_path = _sentence_path(root, sid, unit["ver"]).with_name(f"{unit['ver']}-memo.json")
        parts = [("見出しや箱の字" if sid.startswith("b") else "文", unit.get("text") or "")]
        if memo_path.is_file():
            parts.append(("執筆意図", _read_json(memo_path).get("text") or ""))
        for part, text in parts:
            for pattern, fix, note, source in rules:
                for found in pattern.finditer(text):
                    context = text[max(0, found.start() - 12):found.end() + 12]
                    print(f"{sid} {unit['ver']} {part}: 「{found.group(0)}」→ {fix}{f'（{note}）' if note else ''} [{source}] …{context}…")
                    hits += 1
    print(f"当たり {hits} 件（読んだ表: {', '.join(str(path) for path in words_paths()) or 'なし'}）")
    return hits


def read_registry():
    """一覧の記録フォルダのパスを、足した順に返す。一覧が無ければ空。"""
    path = registry_path()
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    return [entry["path"] for entry in data.get("records", []) if isinstance(entry, dict) and isinstance(entry.get("path"), str)]


def register_record(root):
    """記録フォルダを一覧に足す。すでにあれば何もしない。"""
    root = str(Path(root).resolve())
    with _registry_lock():
        paths = read_registry()
        if root not in paths:
            _write_registry([*paths, root])


def forget_record(root):
    """記録フォルダを一覧から外す。記録そのものは消さない（動かした・消した記録を一覧から片付けるため）。"""
    with _registry_lock():
        paths = read_registry()
        if root in paths:
            _write_registry([p for p in paths if p != root])


@contextmanager
def _registry_lock():
    path = registry_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    # records.json 自体は置換されるので、ロックは別の固定ファイルで共有する。
    with path.with_name(path.name + ".lock").open("a+b") as stream:
        if os.name == "nt":
            import msvcrt
            if stream.seek(0, os.SEEK_END) == 0:
                stream.write(b"\0")
                stream.flush()
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if os.name == "nt":
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def _write_registry(paths):
    path = registry_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    _atomic_write(path, json.dumps({"records": [{"path": p} for p in paths]}, ensure_ascii=False, indent=2) + "\n")


def _memo(root, args):
    """文またはブロックの本文より先に、次の版のメモを確定する。"""
    order = _order(root)
    folder, prefix = ("blocks", "b") if args.block else ("sentences", "s")
    sid = _sid(args.sid) if args.sid else _next_name(root / folder, prefix, 4, "")
    if args.block and not sid.startswith("b"):
        raise ValueError("文には --block を指定できません")
    if sid.startswith("b") and args.origins is not None:
        raise ValueError("ブロックには --from を指定できません")
    if args.sid and sid not in order["order"]:
        raise ValueError(f"{sid}: 書き直す文が order にありません")
    if (args.inferred or args.reported) and sid.startswith("b"):
        raise ValueError("ブロックには --inferred・--reported を指定できません")
    if args.inferred and args.reported:
        raise ValueError("--inferred と --reported は同時に指定できません")
    ver = _next_version(root, sid)
    origins = args.origins.split(",") if args.origins else []
    if len(set(origins)) != len(origins):
        raise ValueError("--from の元の文が重複しています")
    _place_sentence(order, sid, args.after, origins)
    directory = _unit_directory(root, sid)
    directory.mkdir(parents=True, exist_ok=True)
    _sync_directory(directory.parent)
    _write_json(directory / f"{ver}-memo.json", {
        "sid": sid, "ver": ver, "text": args.text, "memo_at": time.time_ns(),
        "after": args.after, "from": origins,
        # 人の文の執筆意図は、書き手のものでなく AI が文と前後から推測したもの（ADR-0002）。
        # 出どころを分けないと、推測が書き手の意図として記録に残る。by の無い古いメモは AI の執筆意図として読む
        # reported は、ほかのチャット AI が自分の書いた文について、あとから申告した執筆意図（同梱のプロンプトで書き出させたもの）。
        # 推測より確かだが、書く前に決めた意図とは限らないので、推測とも tsuzuri の執筆意図とも分けて残す
        **({"by": "inferred"} if args.inferred else {"by": "reported"} if args.reported else {}),
    }, immutable=True)
    print(sid, ver)


# tsuzuri の外で書かれた文の執筆意図の出どころ（推測・書いた AI の申告）。tsuzuri が書いた文の執筆意図は印を持たない
OUTSIDE_INTENT = ("inferred", "reported")


def _pending_memo(directory):
    """文がまだ書かれていないメモのバージョン（v001 など）を返す。無ければ None。"""
    if not directory.is_dir():
        return None
    for path in _numbered(directory, "v", 3, "-memo.json"):
        if not (directory / path.name.replace("-memo", "")).exists():
            return path.name.removesuffix("-memo.json")
    return None


def _designs(root):
    # 設計書を入れる前に作った記録には design/ 自体が無い
    directory = root / "design"
    return _numbered(directory, "d", 3, ".md") if directory.is_dir() else []


def _design_for_write(root, design, para):
    """文が属する段落と、照らした設計書のバージョンを決める。

    設計書が1つでもある記録では段落の番号を必須にする。1段落の文章・人の文・設計書より前の記録は
    設計書を持たないので、そのときは段落を付けさせない（requirements-and-design.md の仮の決まり）。
    """
    paths = _designs(root)
    if not paths:
        if design or para:
            raise ValueError("設計書がありません。先に design で設計書を入れてください")
        return None, None
    design = _identifier(design, "d", 3) if design else paths[-1].stem
    path = root / "design" / f"{design}.md"
    if not path.is_file():
        raise ValueError(f"設計書のバージョンがありません: {design}")
    if not para:
        raise ValueError("設計書のある記録では --para で文が属する段落（p1 など）を指してください")
    _, paragraphs = _design_paragraphs(path.read_text(encoding="utf-8"))
    if para not in paragraphs:
        raise ValueError(f"設計書 {design} に段落 {para} がありません")
    return design, para


# バージョンのタイトルの上限。git のコミットの件名と同じく、一覧の1行に収まる長さに抑える
TITLE_LIMIT = 40


def _version_title(title, sid, ver):
    """write --title を検査して返す。v002 以降で省くと、何を直した版かが履歴に残らないため警告する。"""
    if title is not None:
        title = title.strip()
        if "\n" in title or "\r" in title:
            raise ValueError("--title は1行で記述してください")
        if len(title) > TITLE_LIMIT:
            raise ValueError(f"--title は {TITLE_LIMIT} 字以内で記述してください（{len(title)} 字）")
    if not title and ver != "v001":
        print(f"警告: {sid} {ver}: --title がありません。何を直したバージョンかを1行で記述してください", file=sys.stderr)
    return title or None


def _write(root, args):
    """メモと入力を検査して文またはブロックの不変な版を確定する。"""
    order = _order(root)
    if not args.human and (not args.sid or not args.ver):
        raise ValueError("AI の write には --sid と --ver が必要です")
    folder, prefix = ("blocks", "b") if args.block is not None else ("sentences", "s")
    tracked = set(order["order"]) | {entry["sid"] for entry in order["retired"]}
    sid = _sid(args.sid) if args.sid else _next_name(root / folder, prefix, 4, "")
    if args.human and not args.sid:
        # 自動採番でも、中断した文を残して次の ID へ進めないようにする。
        # 推測した執筆意図だけを先に書いた文（memo --inferred）も、その ID で文を受け取る
        for directory in _numbered(root / folder, prefix, 4, ""):
            if directory.name not in tracked and (_versions(root, directory.name) or _pending_memo(directory)):
                sid = directory.name
                break
    is_block = sid.startswith("b")
    if is_block != (args.block is not None):
        raise ValueError("ブロックには --block を指定し、文には指定しないでください")
    block = json.loads(args.block) if is_block else None
    if is_block:
        _validate_block(block, args.text)
        if args.container is not None:
            raise ValueError("ブロックには --in を指定できません")
    elif args.container is not None:
        _validate_container(root, args.container)
    if args.cont and (is_block or args.container is None or _latest(root, args.container)["block"]["kind"] != "list"):
        raise ValueError("--cont は箇条書きの中の文にだけ指定できます（--in で箇条書きを指してください）")
    versions = _versions(root, sid)
    pending = _pending_memo(_unit_directory(root, sid)) if args.human else None
    if args.ver:
        ver = _ver(args.ver)
    elif pending:
        ver = pending
    elif sid not in tracked and versions:
        ver = versions[-1].stem
    else:
        ver = _next_version(root, sid)
    path = _sentence_path(root, sid, ver)
    existing = _read_json(path) if path.exists() else None
    if existing is not None and sid in tracked:
        raise ValueError(f"確定済みのバージョンは上書きできません: {sid} {ver}")
    memo_path = path.with_name(f"{ver}-memo.json")
    memo = _read_json(memo_path) if memo_path.exists() else None
    if memo is None and not args.human:
        raise ValueError(f"{sid} {ver}: 先にメモを確定してください")
    # 推測の執筆意図は人の文にだけ、AI の執筆意図は AI の文にだけ付ける（取り違えると、推測が書き手の意図として残る）
    if memo is not None and (memo.get("by") in OUTSIDE_INTENT) != bool(args.human):
        raise ValueError(f"{sid} {ver}: 人の文には memo --inferred か --reported、tsuzuri の文には印の無い memo を使ってください")
    if memo is not None:
        if memo.get("sid") != sid or memo.get("ver") != ver or type(memo.get("memo_at")) is not int:
            raise ValueError(f"{memo_path}: メモの ID または時刻が不正です")
        if not isinstance(memo.get("from"), list):
            raise ValueError(f"{memo_path}: from は元の ID の配列です")
    elif _unit_directory(root, sid).exists():
        _next_version(root, sid)
    title = _version_title(args.title, sid, ver)
    tags = json.loads(args.tags)
    if is_block:
        _validate_block_tags(tags)
    else:
        _validate_tags(tags, _vocabulary(root), warn=True)
    requirements = args.requirements
    if requirements is None:
        paths = _numbered(root / "requirements", "r", 3, ".md")
        if not paths:
            raise ValueError("先に req で要件を確定してください")
        requirements = paths[-1].stem
    _identifier(requirements, "r", 3)
    if not (root / "requirements" / f"{requirements}.md").is_file():
        raise ValueError(f"要件のバージョンがありません: {requirements}")
    design, para = _design_for_write(root, args.design, args.para)
    if memo:
        _place_sentence(order, sid, memo.get("after"), memo["from"])
    else:
        _place_sentence(order, sid)
    path.parent.mkdir(parents=True, exist_ok=True)
    _sync_directory(path.parent.parent)
    sentence = {
        "sid": sid, "ver": ver, "text": args.text, "tags": tags,
        "requirements": requirements, "design": design, "para": para, "deviation": args.deviation,
        "source": "human" if args.human else "ai",
        "memo_at": memo["memo_at"] if memo else None,
        "written_at": existing["written_at"] if existing is not None else time.time_ns(),
        **({"block": block} if is_block else {"in": args.container}),
        # 箇条書きの1項目に2文以上ある人の文は、2文目から前の文と同じ項目に続ける（AI の文は1項目1文のまま）
        **({"cont": True} if args.cont else {}),
        # タイトルは指定したときだけ持つ（常に null を入れると、タイトルの無い古い版と復旧の比較が食い違うため）
        **({"title": title} if title else {}),
    }
    if existing is not None:
        # 文だけ確定して並びの保存に失敗した場合も、不変の履歴を上書きせず復旧できるようにする。
        if existing != sentence:
            raise ValueError(f"確定済みのバージョンと入力が一致しません: {sid} {ver}")
    else:
        _write_json(path, sentence, immutable=True)
    _write_json(root / "order.json", order)
    print(sid, ver)


def _move(root, order, sid, after):
    """確定した文かブロックを、並びの上で after の直後へ動かす。文のバージョンは増やさない。

    並べ替えは order.json だけの変更で、文の中身も執筆意図も変わらないため（段落の頭の問いかけを先へ動かす必要が出た。--after は新しい文にしか使えなかった）。
    入れ物のブロックは中の文が直後に続く決まりがあり、ブロックだけ動かすと中の文が置いていかれるので断る。
    after に "start" を渡すと先頭へ動かす。新しい文は並びの末尾に足されるので、文章の題（見出しのレベル1）を
    あとから頭に置く手段が要った。
    """
    if after == "start":
        sid = _sid(sid)
        if sid not in order["order"]:
            raise ValueError(f"order にありません: {sid}")
        if sid.startswith("b") and _latest(root, sid)["block"]["kind"] in CONTAINERS:
            raise ValueError(f"{sid}: 入れ物のブロックは中の文と一緒にしか動かせないので、move では動かせません")
        order["order"].remove(sid)
        order["order"].insert(0, sid)
        _write_json(root / "order.json", order)
        return
    sid, after = _sid(sid), _sid(after)
    if sid == after:
        raise ValueError("動かす文と、その前に置く文が同じです")
    for item in (sid, after):
        if item not in order["order"]:
            raise ValueError(f"order にありません: {item}")
    unit = _latest(root, sid)
    if sid.startswith("b") and unit["block"]["kind"] in CONTAINERS:
        raise ValueError(f"{sid}: 入れ物のブロックは中の文と一緒にしか動かせないので、move では動かせません")
    order["order"].remove(sid)
    order["order"].insert(order["order"].index(after) + 1, sid)
    _write_json(root / "order.json", order)


def _retire(root, order, sid, reason):
    """文かブロックを本文から外す。中身は消さず、order.json の retired に移行先なしで移し、外した理由を review に残す。

    外す命令が無かったころ、書き手は消したい文を隣の文と「まとめる」形（memo --from）で外し、まとめた先の執筆意図に
    削った理由が混ざった。外すことと書き直すことを分けるために置く。
    見出し・コード・画像・表のブロックも外せる。表を表示しない媒体に向けて表を箇条書きへ置き換えるとき、
    元の表を記録から外す手段が無く、新旧の両方が本文に残ったため。
    入れ物（注記の箱・箇条書き・引用・脚注）は外さない。中の文だけが並びに残り、入れ物の直後に続くという決まりが崩れるため。
    """
    sid = _sid(sid)
    if sid not in order["order"]:
        raise ValueError(f"order にありません: {sid}")
    if not isinstance(reason, str) or not reason.strip():
        raise ValueError("外す理由を --text に書いてください")
    unit = _latest(root, sid)
    if sid.startswith("b") and unit["block"]["kind"] in CONTAINERS:
        raise ValueError(f"{sid}: 入れ物のブロックは外せません（中の文が入れ物から離れるため）")
    (root / "reviews").mkdir(exist_ok=True)   # git で配った記録は空の reviews/ を持たない
    version = _next_name(root / "reviews", "rv", 4, ".json")
    _write_json(root / "reviews" / f"{version}.json", {
        "sid": sid, "ver": unit["ver"], "aspect": "削除", "text": reason, "written_at": time.time_ns(),
    }, immutable=True)
    order["order"].remove(sid)
    order["retired"].append({"sid": sid, "into": [], "at": time.time_ns()})
    _write_json(root / "order.json", order)


# 公用文作成の考え方（文化審議会 2022）の「50〜60字ほどになったら見直す」の上の端。測った閾値ではなく見直しの目安
LONG_SENTENCE = 60
def _point_of(root):
    """最新の要件定義書の「8. 言いたいこと」の本文を1行にして返す。要件定義書が無ければ None、項目8が空なら空の文字列。"""
    folder = root / "requirements"
    # 番号で並べる（辞書順だと r1000 が r999 より前に来る）。r001-…md のような別名のファイルは _numbered が外す
    paths = _numbered(folder, "r", 3, ".md") if folder.is_dir() else []
    if not paths:
        return None
    lines, inside = [], False
    for line in paths[-1].read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = line[3:].lstrip().startswith("8.")
            continue
        if inside and line.strip():
            lines.append(line.strip())
    return " ".join(lines)


def _heading_material(root, order):
    """見出しのブロックごとに、その下（次の同じか上のレベルの見出しまで）の設計書の段落の主張と核の文を返す。

    見出しとタイトルのレビューは、言いたいことを書き出し、情報に優先順位を付け、最上位の情報から見出しを始める順で行う
    （AI らしいタイトルを直す手順。曖昧な一語に意味を詰め込み、優先順位を取り違える形を直す）。
    書き出しと優先順位の材料は記録にある（設計書の段落の主張と、文の核）ので、それを見出しの下に並べる。順位は書き手が決める。
    """
    claims = {}
    designs = _designs(root)
    if designs:
        for line in designs[-1].read_text(encoding="utf-8").splitlines():
            match = re.match(r"^## (p\d+)\s+(.*)", line)
            if match:
                claims[match.group(1)] = match.group(2).strip()
    found, stack = [], []
    # 脚注の中の文は本文の段落の主張でも核でもなく、出典の書誌なので材料に入れない
    footnotes = _footnote_blocks(root, order)
    for sid in order["order"]:
        unit = _latest(root, sid)
        if unit.get("in") in footnotes:
            continue
        block = unit.get("block") if sid.startswith("b") else None
        if isinstance(block, dict) and block.get("kind") == "heading":
            level = block.get("level", 1)
            entry = (f"{'#' * level} {unit['text']}（{sid}）", [], [], level)
            found.append(entry)
            stack = [item for item in stack if item[3] < level] + [entry]
            continue
        if not sid.startswith("s"):
            continue
        for _heading, paras, cores, _level in stack:
            para = unit.get("para")
            if para and para in claims and all(para != seen for seen, _ in paras):
                paras.append((para, claims[para]))
            if (unit.get("tags") or {}).get("importance") == "核":
                cores.append((sid, unit["text"]))
    return [(heading, paras, cores) for heading, paras, cores, _level in found]


def _load(root, order):
    """記録の構造から、読み手の負担を見直す候補を出す（references/review-load.md）。削るかどうかは書き手が決める。

    出すのは、衛星が核より多い段落と核の無い段落、衛星の文ごとの要否の問い、目安より長い文、読点の多い文、前の段落の言い直し、初めて出る語の主題、くり返す名詞、途中で変わる動作主、主題と述語の同じ語、見出しの下の主張と核、接続語と接続助詞を含む文。
    どれも見直す順番の材料で、閾値で合否を出さない。
    執筆意図の文字の重なり（2文字の組の Jaccard 係数）も試したが、クイックスタートガイド2本で実際に外した
    重なった呼びかけの組は 276組中40位・351組中104位以下で、拾えなかった。言い回しの違う言い直しは文字では似ないので、読んで判断する。
    """
    sentences = []
    for sid in order["order"]:
        if not sid.startswith("s"):
            continue
        unit = _latest(root, sid)
        memo_path = _sentence_path(root, sid, unit["ver"]).with_name(f"{unit['ver']}-memo.json")
        memo = _read_json(memo_path).get("text", "") if memo_path.is_file() else ""
        sentences.append((sid, unit, memo))

    print("## 段落の核と衛星（衛星に本筋と関係のない話が混ざっていないか）")
    paragraphs = {}
    for sid, unit, _ in sentences:
        paragraphs.setdefault(unit.get("para") or "-", []).append((sid, (unit.get("tags") or {}).get("importance")))
    for para, members in paragraphs.items():
        cores = [sid for sid, importance in members if importance == "核"]
        satellites = [sid for sid, importance in members if importance == "衛星"]
        if not cores or len(satellites) > len(cores):
            label = "核が無い" if not cores else "衛星が多い"
            print(f"{para} {label}: 核 {len(cores)}・衛星 {len(satellites)}（{' '.join(satellites)}）")

    # 読み手にとっての重要度を、衛星の文ごとに問う。点数は付けない（重要度の判定は人どうしでもそろいにくく、
    # 細かい点数にすると判定のぶれが削る判断に乗る）。問う基準は読み手にとっての重要度。
    print("## 衛星の要否（外すと、読み手は要件定義書の「6. 読んだあと」の何ができなくなるか）")
    for sid, unit, memo in sentences:
        if (unit.get("tags") or {}).get("importance") == "衛星":
            print(f"{sid} {unit.get('para') or '-'} ／ 執筆意図: {memo[:60]}")

    print(f"## 長い文（{LONG_SENTENCE}字を超える・一文に内容がいくつあるか）")
    # 長さと読点は、タグや URL を外した見える字で数える（_visible）
    for sid, unit, _ in sorted(sentences, key=lambda item: -len(_visible(item[1]["text"]))):
        shown = _visible(unit["text"])
        if len(shown) > LONG_SENTENCE:
            print(f"{sid} {len(shown)}字 読点 {shown.count('、')}")

    print("## 読点の多い文（3つ以上）")
    for sid, unit, _ in sentences:
        if _visible(unit["text"]).count("、") >= 3:
            print(f"{sid} 読点 {_visible(unit['text']).count('、')}")

    print(f"## 前の段落の言い直し（中心語の再利用 {RESTATE_THRESHOLD:.2f} 以上・references/cold-read.md の型5）")
    for group, core, count in _restate(sentences):
        if count >= RESTATE_MIN_TOKENS and core >= RESTATE_THRESHOLD:
            print(f"{group[0]}〜{group[-1]} 中心語の再利用 {core:.2f}（{count}語）")

    print("## 初めて出る語の主題（読み手が知らない語を、導入せずに「は」の主題にしていないか）")
    for sid, word in _new_topics(root, order):
        print(f"{sid} 「{word}は」")

    print("## くり返す名詞（指す先が同じ文か直前の文に1つだけなら、それ・その などのこそあど言葉で足りる）")
    for sid, note in _repeats(sentences):
        print(f"{sid} {note}")

    print("## 途中で変わる動作主（「〜し、〜すると、〜が…」。前半の省いた動作主と、後半の主語が同じ文に入っていないか）")
    for sid, unit, _ in sentences:
        if _ACTOR_SHIFT.match(unit["text"].strip()):
            print(f"{sid} {unit['text'][:40]}…")

    print("## 主題と述語の同じ語（「〇〇の××は、△△の××です」は、述語を動詞で言い切る形に直せないか）")
    for sid, word in _topic_echo(sentences):
        print(f"{sid} 「{word}は、…{word}です」")

    print("## 見出しと、その下の主張と核（見出しが最も重要な情報から始まっているか・曖昧な一語に意味を詰め込んでいないか）")
    for heading, claims, cores in _heading_material(root, order):
        print(f"{heading}")
        if heading.startswith("# "):
            # タイトルは文章全体を受けるので、段落を全部並べず要件定義書の「言いたいこと」と照らす
            point = _point_of(root)
            print(f"  要件定義書 8. 言いたいこと: {'（要件定義書が無い）' if point is None else point or '（項目8が空）'}")
            continue
        for para, claim in claims:
            print(f"  設計書 {para}: {claim}")
        for sid, text in cores:
            print(f"  核 {sid}: {text[:60]}")

    print("## 可能動詞の短い形（文語なら「〜することができる」か漢語の「使用できる」などにする。候補で、合否ではない）")
    for sid, word in _potential_hits(root, order):
        print(f"{sid} 可能動詞の短い形「{word}」")

    print("## 接続の確認（接続語・接続助詞の前と後が、本当にその関係になっているか）")
    for sid, unit, _ in sentences:
        relation = (unit.get("tags") or {}).get("relation", "-")
        for kind, word, start in _connectives(unit["text"]):
            snippet = unit["text"][max(0, start - 18):start + len(word) + 18]
            print(f"{sid} 接続 {relation} ／ {kind}「{word}」: …{snippet}…")


# くり返す名詞。「これ」「それ」といったこそあど言葉を使えていないと、まどろっこしくなる。
# 文脈の無い読み手の型1と主語の決まりが名詞を書き直す方向にだけ寄っていて、「項目や段落を選ぶと、その項目や段落を担う文が」
# 「tsuzuri は〜。tsuzuri は〜。」のような文が残った。本文は上から読まれるので、指す先が同じ文か同じ段落の直前の文に
# 1つだけなら、こそあど言葉で足りる。逆向きの候補として、同じ文で並べた語を「その〜」で受け直している所と、直前の文と同じ主題で始まる文を出す。
_PAIR_AGAIN = re.compile(r"その([^、。「」（）]{1,10}?[やと・][^、。「」（）]{1,10}?)(?=[をがはにでの])")
_LEADING_TOPIC = re.compile(r"^([^、。 ]{1,12}?) ?は")


def _repeats(sentences):
    """並べた語を「その〜」で受け直している所と、同じ段落の直前の文と同じ主題で始まる文を (文の ID, 説明) で返す。合否は出さない。"""
    found, previous = [], None
    for sid, unit, _ in sentences:
        text, para = unit["text"], unit.get("para")
        # 同じ語のくり返しを全部挙げると、別のものを指す同じ語（直す前のバージョンと新しいバージョン）まで拾い、
        # 「その文」のような短い受け直しは自然なこそあど言葉なので挙げない。並べた語ごと受け直す所（「項目や段落を選ぶと、
        # その項目や段落を」）だけを挙げる。「それ」の一語で足りる
        twice = [m.group(1) for m in _PAIR_AGAIN.finditer(text) if m.group(1) in text[:m.start()]]
        if twice:
            found.append((sid, "並べた語を「その」で受け直している: " + "・".join(f"「その{t}」" for t in twice)))
        topic = _LEADING_TOPIC.match(text)
        if topic and previous and previous[0] == para and previous[1] == topic.group(1):
            found.append((sid, f"直前の文と同じ主題: 「{topic.group(1)}は」"))
        previous = (para, topic.group(1) if topic else None)
    return found


# 途中で変わる動作主。「書き上がった文章は閲覧アプリで開き、文を選ぶと、その文の執筆意図と文機能が右の詳細パネルに出ます」は、
# 前半の「開き」の動作主（ユーザー）を省いたまま、主語の違う後半（執筆意図と文機能が出ます）を1文につないでいて、読み手が誰の話かを
# 取り違える。動作を連用形で連ね、条件（と・ば・たら・なら）で受け、最後に「〜が」の主語を出す形だけを拾う。
# 連用形の「に、」は助詞の「に、」と見分けられず、文頭の接続語（したがって、）も拾ったので、どちらも外した。
# 連用形と条件の間には読点をいくつ挟んでもよい。「〜読み、好みの語を校正辞書に、決まった構成をテンプレートに足しておけば、」を
# 挟んだ読点のせいで見逃したため。手元の記録 2,280 文に当てて、増えたのはこの文のバージョンだけだった。
_ACTOR_SHIFT = re.compile(r"^[^、。]{6,}?(?:き|し|ち|び|み|り|け|げ|せ|え|べ|め|れ|て|で)、(?:[^、。]*?、)*?[^、。]*?(?:と|ば|たら|なら)、"
                          r"[^。]*?[^、。]が[^、。]*(?:ます|ました|です|る|た)。?$")


# 主題と述語の同じ語。「決める順は、要件定義書、設計書、一文ずつの順です」のように、主題の末尾の語を述語でもう一度
# 言う形は、何も足さずに語を往復させるだけで、作文として拙い。「〜の順で進めます」のように動詞で言い切れる。
_TOPIC_HEAD = re.compile(r"^([^、。「」]{1,20}?)は、?")
_COPULA_END = re.compile(r"(です|だ|である)。?$")


def _topic_echo(sentences):
    """主題の末尾の語が、文末の「〜です」「〜だ」の直前にもう一度出る文を (文の ID, 語) で返す。合否は出さない。"""
    found = []
    for sid, unit, _ in sentences:
        text = unit["text"].strip()
        topic, copula = _TOPIC_HEAD.match(text), _COPULA_END.search(text)
        if not topic or not copula:
            continue
        body = text[:copula.start()]
        # 末尾の語の長さは決められないので、主題の末尾の1〜4字を長い順に試し、述語の直前と同じなら挙げる
        for size in (4, 3, 2, 1):
            word = topic.group(1)[-size:]
            if len(topic.group(1)) >= size and body.endswith(word) and len(body) > len(topic.group(0)) + size:
                found.append((sid, word))
                break
    return found


# 接続語・接続助詞の一覧。README で「意図からずれていても、どの文でずれたのかは分かりません」の逆接が
# 理由の無いまま残り、読み手に理由が分からないと指摘された。指摘レビューの観点に「接続」はあったが、
# 書き手が読み飛ばした。候補を並べて、前と後がその関係かを1つずつ言葉で確かめさせる。合否は出さない。
# 「が、」は主語の「が」と分けるため、用言の終わり（す・た・る・い・だ）に続くものだけを拾う。
_CONNECTIVE_PATTERNS = (
    # 「AでもBでもなく」の「でも、」は並べて打ち消す形で、逆接ではない（人の文の Issue で誤検知があった）
    ("逆接・譲歩", re.compile(r"^(?:しかし|だが|ところが|けれども|けれど|とはいえ|ただし|一方で|一方)|ても、|でも、(?![^。]*でもな[いく])|(?<!も)のに|けれど|ながら、|(?<=[すたるいだ])が、")),
    # 「もので」「ものに」の「ので」「のに」は形式名詞の「もの」に助詞が付いたもので、接続助詞ではない（クイックスタートで2件の誤検知があった）。
    # 「のである」「のです」「のでは」「のでしょう」の「ので」は、断定の「の＋で」で接続助詞ではない（AI の記事の「なったのである」で誤検知があった）
    ("順接・理由", re.compile(r"^(?:そのため|そこで|したがって|だから|それで|なので|つまり)|(?<!も)ので(?!あ|は|す|しょう)|(?<=[るたいだ])から、|ため、")),
)


# 初めて出る語の主題。読み手は文の前半を知っていることに結びつけてから後半を受け取るので、初めて出す語は
# 「〜がある」の形で導入してから主題にする（given-new。AoTofu/my-claude-system-prompt の決まり13 の考え方を借りた）。
# README で、文脈の無い読み手が拾った「定義の前に出る語」の多くがこの型だった。語の取り出しは
# 型5 と同じ近似（漢字・カタカナの連続・英単語）で、2字以上の語だけを見る。見出しとブロックの字も「既に出た語」に数える。
_TOPIC = re.compile(r"([㐀-鿿々〆]{2,}|[゠-ヺー]{2,}|[A-Za-z][A-Za-z0-9_\-\.]+)は(?![じず])")


# どの文章にも出る一般の語。読み手が止まる語ではないので主題でも挙げない（README で試して外した語）
_COMMON_TOPICS = {"場合", "対象", "効果", "判定", "書誌", "結果", "理由", "方法", "内容", "目的", "必要", "今回", "本文", "以下", "次回"}


def _new_topics(root, order):
    """並びの順に、その語が初めて出る文で「語は」の主題になっている所を (文の ID, 語) で返す。"""
    seen, found = set(), []
    for sid in order["order"]:
        text = _latest(root, sid).get("text") or ""
        for match in _TOPIC.finditer(text):
            word = match.group(1)
            earlier = text[:match.start(1)]
            # 「この文章は」のように指示語で指した語は、読み手の手元にある物を指すので導入は要らない
            deictic = earlier.endswith(("この", "その", "あの"))
            if sid.startswith("s") and not deictic and word not in _COMMON_TOPICS and word.lower() not in seen and word not in earlier:
                found.append((sid, word))
        seen.update(t.lower() for t in _RESTATE_TOKEN.findall(text))
    return found


# 意味の崩れの検査で比べる語。nihongo（AnIT012/nihongo）の revert_broken.py の考え方を借りた。推敲や語の直しで、
# 否定・数値・確かさ・強さが変わった文は、言い回しの直しではなく意味の直しになっている。語の一覧は tsuzuri で選んだ。
_DRIFT_KINDS = (
    ("否定", re.compile(r"ない|ません|ず[、。に]|ぬ|無い|無し|不[可要]|非")),
    ("数値", re.compile(r"[0-9０-９]+(?:\.[0-9]+)?|[一二三四五六七八九十百千万]+(?:つ|件|人|回|日|か月|年|字|行|段)")),
    ("確かさ", re.compile(r"かもしれ|はず|予定|推定|見込み|可能性|と思|らしい|ようだ|でしょう|場合があ|ことがあ")),
    ("強さ", re.compile(r"必ず|すべて|全部|全て|常に|絶対|だけ|しか|べき|ください|てはいけ|禁止|任意|推奨|大幅|かなり")),
)


def _drift(root, order, since=None):
    """各文の最新を指定バージョン（省略時は1つ前）と比べ、意味に関わる語の変化を挙げる。指定版の無い文は比べない。"""
    if since is not None:
        _ver(since)
    for sid in order["order"]:
        if not sid.startswith("s"):
            continue
        versions = _versions(root, sid)
        if len(versions) < 2:
            continue
        baseline = _sentence_path(root, sid, since) if since else versions[-2]
        if not baseline.is_file() or _version_number(baseline.stem) >= _version_number(versions[-1].stem):
            continue
        before, after = _read_json(baseline)["text"], _read_json(versions[-1])["text"]
        for kind, pattern in _DRIFT_KINDS:
            old, new = sorted(pattern.findall(before)), sorted(pattern.findall(after))
            if old != new:
                print(f"{sid} {baseline.stem}→{versions[-1].stem} {kind}: {old} → {new}")


def _examples():
    """ライブラリの全部の記録から、利用者のコメントと、それで直した前後の文を出す。書き手が利用者の直し方を読むため。

    nihongo の personal-profile（利用者が直した前後を一番の基準にする）の考え方を、tsuzuri の記録から自動で作る形にした。
    """
    for record in read_registry():
        root = Path(record)
        if not (root / "order.json").is_file():
            continue
        try:
            _examples_of(root)
        except (ValueError, OSError, KeyError, TypeError, RecursionError) as error:
            # 1つの壊れた記録で、ほかの記録の手本まで出なくならないようにする
            print(f"警告: {root} の手本を読めませんでした: {error}", file=sys.stderr)


def _examples_of(root):
    """1つの記録から、解決したコメントと直した前後の文を出す。人から受け取った記録（.tsz）は利用者の直し方ではないので出さない。"""
    order = _read_json(root / "order.json")
    if order.get("received"):
        return
    for comment in _comments(root, order):
        if comment.get("status") != "resolved" or "doc" in comment or not comment.get("addressed_by"):
            continue
        before = _read_json(_sentence_path(root, comment["sid"], comment["ver"]))["text"]
        # 文を外して対応したコメント（addressed_by が "retired"）は、直したあとの文が無い。外したことを after に書く
        # （retired をバージョンとして読んで「不正な ID」で止まったことがあった）
        if comment["addressed_by"] == "retired":
            after = "（文を外した）"
        else:
            after = _read_json(_sentence_path(root, comment["sid"], comment["addressed_by"]))["text"]
        print(json.dumps({"record": root.name, "comment": comment["text"], "before": before, "after": after}, ensure_ascii=False))


# 可能動詞の短い形（読める・使える）は口語寄りで、文語の文書では「〜することができる」か漢語にする。
# 五段動詞の可能形は語幹＋エ段で、一段動詞（考える・見える）と字面で区別できないので、よく使う五段動詞を名指しで並べる。
# 一段動詞の「〜られる」は受け身と同じ形で、可能かどうかを字面で決められないので探さない（書き手が読んで判断する）
_POTENTIAL_STEMS = (
    "読め", "書け", "使え", "言え", "作れ", "試せ", "選べ", "探せ", "戻せ", "残せ", "直せ", "消せ", "開け", "見張れ",
    "追え", "たどれ", "辿れ", "切り出せ", "行え", "照らせ", "気づけ", "増やせ", "減らせ", "抜き出せ", "拾え", "知れ",
    "読み取れ", "渡せ", "またげ", "押せ", "送れ", "動かせ", "話せ", "聞け", "待て", "持て", "取れ", "呼べ", "払え",
    "移せ", "隠せ", "外せ", "守れ", "許せ", "頼め", "思え", "買え", "通せ", "直せ", "並べ替えられ", "見つけ出せ",
)
_SHORT_POTENTIAL = re.compile("(?:" + "|".join(sorted(set(_POTENTIAL_STEMS), key=len, reverse=True)) + r")(?=る|な[いく]|ず|ます|ません|れば|た|て)")
_INLINE_CODE = re.compile(r"`[^`]*`")


def _potential_hits(root, order):
    """文・見出し・表の字から、可能動詞の短い形の候補を (ID, 語) で返す。コードの箱とインラインのコードは見ない。"""
    hits = []
    for sid in order["order"]:
        unit = _latest(root, sid)
        block = unit.get("block") if sid.startswith("b") else None
        if isinstance(block, dict) and block.get("kind") == "code":
            continue
        for match in _SHORT_POTENTIAL.finditer(_INLINE_CODE.sub("", unit.get("text") or "")):
            hits.append((sid, match.group(0)))
    return hits


def _connection_sids(root, order):
    """load の「接続の確認」に出る文の ID。"""
    return [sid for sid in order["order"] if sid.startswith("s") and _connectives(_latest(root, sid)["text"])]


# 確認項目の（候補: 名前）から、その項目を確認するときに必ず読む文の ID を返す関数へ。
# confirm はここで返る ID を全部含めないと記録しない（書き手が一部の文だけを挙げて印を付けることを防ぐ）
CANDIDATES = {
    "可能動詞の短い形": lambda root, order: list(dict.fromkeys(sid for sid, _ in _potential_hits(root, order))),
    "接続の確認": _connection_sids,
}

def _connectives(text):
    """文の中の接続語・接続助詞を (種類, 語, 位置) で返す。"""
    found = []
    for kind, pattern in _CONNECTIVE_PATTERNS:
        for match in pattern.finditer(text):
            found.append((kind, match.group(0), match.start()))
    return sorted(found, key=lambda item: item[2])


# 型5（前の段落の言い直し）の機械検査。ja-cold-reader の restate_check.py から移した（cold-reader を tsuzuri の段階に組み込んだ）。
# 段落の語のうち、それより前の段落で2回以上使われた語（文章の中心語）の割合。言い直しの段落は中心語を拾い集めて組み立てるので高くなる。
# 較正は架空の題材の正例 0.43・0.45 と負例の最大 0.22 の間の 0.40。語の取り出しは漢字・カタカナの連続と英単語の近似で、
# 形態素解析器を使わない（標準ライブラリだけで動かすため）。別の語で言い換えた要約は拾えない。
# 語は2字以上だけを数える。漢字の連続は送り仮名の前で切れるので、1字の語は動詞の語幹（問う→問・返る→返）や
# どの段落にも出る語（声・歌）になり、長い文書では後ろの段落がほとんど言い直しの候補になった（曲の構想で28段落→10段落）
RESTATE_THRESHOLD = 0.40
RESTATE_MIN_TOKENS = 15   # これより語の少ない段落は、1〜2語で割合が大きく動くので判定しない
_RESTATE_TOKEN = re.compile(r"[㐀-鿿々〆]{2,}|[゠-ヿー]{2,}|[A-Za-z][A-Za-z0-9_\-\.]+")


def _paragraph_groups(sentences):
    """文を段落ごとにまとめる。設計書の段落（para）が変わる所か、para が無ければ「段落の始まり」の文で区切る。"""
    groups, last = [], object()
    for sid, unit, _ in sentences:
        para = unit.get("para")
        start = para != last if para else (unit.get("tags") or {}).get("relation") == "段落の始まり"
        if start or not groups:
            groups.append([])
        groups[-1].append((sid, unit))
        last = para
    return groups


_TAG = re.compile(r"<[^>]+>")
_LINK = re.compile(r"\[([^\]]+)\]\([^)\s]+\)")
_URL = re.compile(r"https?://\S+")
_FN_REF = re.compile(r"\[\^[^\]]+\]")
# Obsidian の見出しへのリンク [[#見出し|表示名]]。数えるのは表示名（無ければ見出しの名前）。ハイライトの == も記号として外す
_WIKILINK = re.compile(r"\[\[#?([^\]|]+)(?:\|([^\]]+))?\]\]")


def _visible(text):
    """読み手に見える字だけを返す。HTML のタグ・リンクの URL・裸の URL・脚注の呼び出し・太字の記号を外す。

    長い文・読点・言い直しの中心語を数えるときに使う。色分けを span で書いた構想の文書で、タグの字（span・style・color と色の値）が
    長さと中心語に数えられ、長い文の上位と言い直しの候補が雑音で埋まった。
    """
    text = _LINK.sub(r"\1", _WIKILINK.sub(lambda m: m.group(2) or m.group(1), text))
    return _FN_REF.sub("", _URL.sub("", _TAG.sub("", text))).replace("**", "").replace("==", "")


def _restate(sentences):
    """段落ごとに (文の ID の並び, 中心語の再利用率, 語の数) を返す。最初の段落は比べる前が無いので 0。"""
    seen, rows = {}, []
    for index, group in enumerate(_paragraph_groups(sentences)):
        tokens = [t.lower() for _, unit in group for t in _RESTATE_TOKEN.findall(_visible(unit["text"]))]
        core = sum(1 for t in tokens if seen.get(t, 0) >= 2) / len(tokens) if tokens and index else 0.0
        rows.append(([sid for sid, _ in group], core, len(tokens)))
        for t in tokens:
            seen[t] = seen.get(t, 0) + 1
    return rows


COLD_PROMPT = Path(__file__).resolve().parent.parent / "references" / "cold-reader-prompt.md"


def _cold(root, order):
    """文脈の無い読み手に渡す指示を、記録から組んで出す（references/cold-read.md）。

    読み手には、要件定義書の「3. 公開する場所と読み手」と、文の ID を頭に付けた本文だけを渡す。執筆意図・設計書・
    文機能は渡さない。渡すと読み手が書き手の文脈で補って読み、指すものが決まらない語や定義していない呼び名を見落とす。
    """
    paths = _numbered(root / "requirements", "r", 3, ".md") if (root / "requirements").is_dir() else []
    if not paths:
        raise ValueError("要件定義書がありません。読み手は要件定義書の「3. 公開する場所と読み手」から渡します")
    reader = _doc_sections(paths[-1].read_text(encoding="utf-8"), "requirements").get("3")
    if not reader:
        raise ValueError(f"{paths[-1].stem} に「## 3.」の項目がありません")
    lines, footnotes = [], []
    starts = _paragraph_starts(root, order)
    footnote_ids = _footnote_blocks(root, order)
    containers, counts, inside = {}, {}, False   # 入れ物の ID → 中の文に付ける印
    for sid in order["order"]:
        unit = _latest(root, sid)
        if sid in footnote_ids:
            footnotes += ["", f"[{sid}] [^{unit['block']['label']}]:"]
            continue
        if unit.get("in") in footnote_ids:
            footnotes.append(f"[{sid}] {unit['text']}")
            continue
        if sid.startswith("b"):
            block = unit.get("block") or {}
            kind = block.get("kind", "ブロック")
            label = "#" * int(block.get("level", 2)) + " " if kind == "heading" else f"（{kind}）"
            if kind in ("list", "quote", "note"):
                # 中の文は入れ物の下に印を付けて並べる。印が無いと、読み手は入れ物を中身の見えない箱と読み、中の文を本文の言い直しと取り違える
                containers[sid] = {"list": "1. " if block.get("ordered") else "- ", "quote": "> ", "note": "> "}[kind]
                label += "中身は下の印の付いた行"
            lines += ["", f"[{sid}] {label}{unit.get('text', '')}".rstrip()]
            inside = False
            continue
        mark = containers.get(unit.get("in"), "")
        if mark == "1. ":
            counts[unit["in"]] = counts.get(unit["in"], 0) + 1
            mark = f"{counts[unit['in']]}. "
        # 入れ物を出た地の文は、export と同じく段落を区切る
        if (inside and not mark) or (not mark and starts[sid] and lines and lines[-1] != ""):
            lines.append("")
        inside = bool(mark)
        lines.append(f"[{sid}] {mark}{unit['text']}")
    lines.extend(footnotes)
    template = COLD_PROMPT.read_text(encoding="utf-8").split("\n---\n", 1)[1]
    # 見出しの行と、要件の段階の問い「読み手は、この項目から〜を受け取る」の行は外す（書き手が項目を確かめるための行で、読み手の像ではない）
    reader_text = "\n".join(line for line in reader.splitlines()[1:] if not line.startswith("読み手は、この項目から")).strip()
    print(template.replace("{{READER}}", reader_text).replace("{{TEXT}}", "\n".join(lines).strip()))


def _comments(root, order):
    retired_at = {entry["sid"]: entry.get("at") for entry in order["retired"]}
    retired_into = {entry["sid"]: entry.get("into") or [] for entry in order["retired"]}
    retired = set(retired_at)
    for path in sorted((root / "comments").glob("*.json")):
        if path.name.startswith(".tmp-"):
            continue
        try:
            comment = _read_json(path)
            if "doc" in comment:   # 要件定義書・設計書へのコメント（ADR-0005）
                yield _doc_comment(root, comment)
                continue
            target = _sentence_path(root, comment.get("sid"), comment.get("ver"))
            if not isinstance(comment.get("text"), str):
                raise ValueError("コメントの text がありません")
            versions = _versions(root, comment["sid"])
            current = _read_json(versions[-1]) if versions else None
            orphan = not target.is_file() or current is None or comment["sid"] not in set(order["order"]) | retired
            # 置き換え先の無い外し（retire だけ）には「置き換えられた」と書かない
            note = ("行き先の無いコメント" if orphan else None if comment["sid"] not in retired
                    else "置き換えられた元の文へのコメント" if retired_into.get(comment["sid"]) else "本文から外した文へのコメント")
            # 投稿時・開き直し時の最新より後の更新だけを対応とし、旧文への新しい指摘を黙って閉じない。
            # ファイルは書き換えない。comments/ はアプリだけが書く（ADR-0001 の「書き手を分ける」）。直っていなければアプリで開き直す
            # （蒸し返せる設計にしてあるので、解決を手作業で付けさせるほうが重い）
            latest = versions[-1].stem if versions else None
            since = _comment_since(comment)
            addressed = (comment.get("status") == "open" and not orphan and latest is not None
                         and _version_number(latest) > _version_number(since))
            # 外した文へのコメントは、文を外したことで対応したとみなす（文を外したあともコメントが開いたままになっていた）。投稿時の最新が無い旧コメントだけに適用し、開き直したものも保つ
            # 外した時刻（at）が記録にあれば、それより前に付いたコメントも同じく対応したとみなす。分けて外した文へのコメントが開いたまま残っていた
            # （at が無いのは時刻を記録する前に外した文で、コメントとの前後が分からないので、投稿時の最新が無い旧コメントだけにする）
            at = retired_at.get(comment["sid"])
            # 時刻は整数だけを信じる（JSON の true も Python では int として通るので、型を名指しで見る）
            at = at if type(at) is int else None
            if comment.get("reopened_at_ver"):
                # 開き直したコメントは、開き直した時刻（reopened_at）より後に文を外したときだけ閉じる。
                # 時刻を記録する前に開き直したものは前後が分からないので、開いたまま保つ
                reopened = comment.get("reopened_at")
                before = at is not None and type(reopened) is int and reopened < at
                legacy = False
            else:
                # 時刻も投稿時の最新も無いコメントは、それらを記録する前の旧形式で、外した文より前と読む
                created = comment.get("created_at")
                before = at is not None and (created < at if type(created) is int else not comment.get("posted_latest"))
                legacy = at is None and not comment.get("posted_latest")
            # 新しいバージョンで先に対応済みになったコメントは、そのバージョンを対応先のまま残す（あとで文を外しても上書きしない）
            if (not addressed and comment.get("status") == "open" and not orphan and comment["sid"] in retired
                    and (before or legacy)):
                addressed, latest = True, "retired"
            yield {**comment, **({"status": "resolved", "addressed_by": latest} if addressed else {}),
                   "current_text": current["text"] if current else None, "note": note}
        except (ValueError, OSError, KeyError) as error:
            yield {"file": path.name, "current_text": None, "note": f"壊れた JSON のコメント: {error}"}


def _footnote_blocks(root, order):
    """並びにある脚注のブロックの ID を返す。読めないブロックは _check が誤りとして数えるので外す。"""
    found = set()
    for sid in order["order"]:
        if not sid.startswith("b"):
            continue
        try:
            block = _latest(root, sid).get("block")
        except (ValueError, OSError):
            continue
        if isinstance(block, dict) and block.get("kind") == "footnote":
            found.add(sid)
    return found


def _paragraph_starts(root, order):
    """並びの各 ID について、文が段落を始めるかを共通の規則で返す。"""
    has_design = bool(_designs(root))
    footnotes = _footnote_blocks(root, order)
    starts, previous = {}, None
    for sid in order["order"]:
        unit = _latest(root, sid)
        if sid in footnotes or unit.get("in") in footnotes:
            # 脚注は書き出しで本文の末尾へ移るので、前後の本文の文のつながりを変えない
            starts[sid] = False
            continue
        starts[sid] = sid.startswith("s") and (
            previous is None or previous["sid"].startswith("b")
            or (unit.get("in") is not None and unit["in"] != previous.get("in"))
            or (unit.get("para") != previous.get("para") if has_design and unit.get("para") is not None
                else unit["tags"]["relation"] == "段落の始まり")
        )
        previous = unit
    return starts


def _meta(root):
    """最新の付帯情報の本文を返し、版が無ければ None を返す。"""
    paths = _numbered(root / "meta", "m", 3, ".md")
    return paths[-1].read_text(encoding="utf-8") if paths else None


def _check_containers(root, order):
    """入れ物の指し先と、その直後に文が連続していることを検査する。前の項目に続ける文（cont）は、同じ箇条書きの文のすぐ後ろにあること。"""
    problems, active, previous_in = [], None, None
    # 退役した文の所属は当時の履歴であり、現在の並びの連続性には影響しない。
    retired = {entry["sid"] for entry in order["retired"]}
    unlisted = [path.name for path in _numbered(root / "sentences", "s", 4, "")
                if path.name not in order["order"] and path.name not in retired]
    for sid in order["order"] + unlisted:
        if sid in unlisted:
            active = None
        try:
            unit = _latest(root, sid)
        except (ValueError, OSError):
            active = None
            continue
        if sid.startswith("b"):
            active, previous_in = sid, None
            continue
        bid = unit.get("in")
        if unit.get("cont") and (bid is None or previous_in != bid):
            problems.append(f"{sid}: 前の項目に続ける文（cont）が、同じ箇条書きの文のすぐ後ろにありません")
        previous_in = bid
        if bid is not None:
            try:
                _validate_container(root, bid)
            except (ValueError, OSError) as error:
                problems.append(f"{sid}: 入れ物の指し先が不正です: {error}")
            if bid != active:
                problems.append(f"{sid}: 入れ物 {bid} の直後に続いていません")
                active = None
        else:
            active = None
    return problems


def _check_footnotes(root, order):
    """脚注の呼び出しとラベルが1対1で対応し、脚注が呼ぶ文より後ろにあるかを検査する。"""
    problems, labels, references = [], {}, {}
    for index, sid in enumerate(order["order"]):
        try:
            unit = _latest(root, sid)
        except (ValueError, OSError):
            continue
        if sid.startswith("b"):
            block = unit.get("block")
            if isinstance(block, dict) and block.get("kind") == "footnote":
                label = block.get("label")
                if label in labels:
                    problems.append(f"{sid}: 脚注のラベル {label} が重複しています（{labels[label][0]}）")
                else:
                    labels[label] = (sid, index)
            continue
        for label in FOOTNOTE_REFERENCE.findall(INLINE_CODE.sub("", unit.get("text") or "")):
            references.setdefault(label, (sid, index))
    for label, (sid, _) in references.items():
        if label not in labels:
            problems.append(f"{sid}: [^{label}] を呼んでいますが、その脚注がありません")
    if not labels:
        # 脚注のブロックが無い記録は、脚注を文や記録の外に書いていた ADR-0004 の追記より前の書き方。
        # 「前の記録はそのまま読む」に合わせて誤りにせず、警告として標準エラーへ出す（アプリは標準出力だけを問題として数える）
        for problem in problems:
            print(f"警告: {problem}", file=sys.stderr)
        return []
    for label, (bid, index) in labels.items():
        if label not in references:
            problems.append(f"{bid}: 脚注 {label} はどの文からも呼ばれていません")
        elif references[label][1] > index:
            problems.append(f"{bid}: 脚注 {label} が呼ぶ文より前にあります")
    # 最後の文を外しても本文の参照を壊さないよう、空の脚注は空の定義として残す。
    return problems


def _article(root, order, flavor="gfm"):
    """付帯情報と文・ブロックを記事の Markdown にして返す。脚注は本文の末尾にまとめる。アプリの本文コピーも同じ中身を使う。

    flavor は書き出す媒体の方言（FLAVORS）。記録の形は媒体によらず同じで、注記の箱の書き方だけが変わる。
    """
    if flavor not in FLAVORS:
        raise ValueError(f"方言は {'・'.join(FLAVORS)} のどれかにしてください: {flavor}")
    problems = _check_containers(root, order) + _check_footnotes(root, order)
    if problems:
        raise ValueError("\n".join(problems))
    starts = _paragraph_starts(root, order)
    meta = _meta(root)
    chunks = ["---\n" + meta.rstrip("\n") + "\n---"] if meta is not None else []
    footnotes = []
    plain = False
    position = 0
    while position < len(order["order"]):
        sid = order["order"][position]
        unit = _latest(root, sid)
        position += 1
        if sid.startswith("s"):
            if not plain or starts[sid]:
                chunks.append(unit["text"])
            else:
                # 同じ段落の文は1行に1文で続ける。Qiita・Zenn は段落の中の改行をそのまま改行として描くので、
                # 記録の一文ずつの区切りが記事にも残る
                chunks[-1] += "\n" + unit["text"]
            plain = True
            continue
        block, text = unit["block"], unit["text"]
        _validate_block(block, text)
        kind = block["kind"]
        children = []
        if kind in CONTAINERS:
            while position < len(order["order"]):
                child_id = order["order"][position]
                child = _latest(root, child_id)
                if child_id.startswith("b") or child.get("in") != sid:
                    break
                children.append((child["text"], bool(child.get("cont"))))
                position += 1
        if kind == "footnote":
            # plain を保ったまま次へ進み、脚注の後ろの文が呼ぶ文と同じ段落に続くようにする
            footnotes.append(f"[^{block['label']}]: " + "".join(text for text, _ in children))
            continue
        # 空の入れ物は履歴に残すが、読み手に内容の無い箱を見せないよう書き出しでは省く。
        if kind in CONTAINERS and not children:
            continue
        plain = False
        if kind == "heading":
            chunks.append("#" * block["level"] + " " + text)
        elif kind == "code":
            chunks.append(f"```{block['lang']}\n{text}\n```")
        elif kind in ("image", "table"):
            chunks.append(text)
        elif kind == "note":
            opening = NOTE_OPEN[flavor][block["type"]]
            if flavor == "gfm":
                # GitHub の注記は引用の形なので、中の文も1行ずつ「> 」で続ける
                chunks.append("\n".join([opening, *(f"> {child}" for child, _ in children)]))
            else:
                chunks.append("\n".join([opening, *(child for child, _ in children), ":::"]))
        elif kind == "list":
            # 前の項目に続ける文（cont）は同じ行へ足す。和文は句読点のあとに空白を入れず、英文は空白で続ける
            items = []
            for text, cont in children:
                if cont and items:
                    items[-1] += ("" if items[-1][-1:] in "。．！？」）" else " ") + text
                else:
                    items.append(text)
            chunks.append("\n".join(f"{number}. {text}" if block["ordered"] else f"- {text}"
                                    for number, text in enumerate(items, 1)))
        else:
            chunks.append("\n".join(f"> {text}" for text, _ in children))
    chunks.extend(footnotes)
    return "\n\n".join(chunks) + ("\n" if chunks else "")


CHECKLIST = Path(__file__).resolve().parent.parent / "references" / "checklist.md"
# 項目の末尾の注記。（条件: 語）は要件定義書の「9. 文章の形」にその語があるときだけ出し、（判定: 名前）は書き手の確認の代わりに CHECKS の関数で判定する
_ITEM = re.compile(r"^- ([^:：]+)[:：]\s*(.+?)\s*$")
_NOTE = re.compile(r"[（(](条件|判定|候補)[:：]\s*([^）)]+)[）)]\s*$")


def checklist_items(text):
    """「## 確認項目」の節の箇条書きを (名前, 本文, 条件, 判定, 候補) の並びにする。節が無ければ空。"""
    items, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            inside = line[3:].strip() == "確認項目"
            continue
        match = _ITEM.match(line) if inside else None
        if not match:
            continue
        name, body, condition, check, candidates = match.group(1).strip(), match.group(2), None, None, None
        while (note := _NOTE.search(body)):
            kind, value = note.group(1), note.group(2).strip()
            if kind == "条件":
                condition = value
            elif kind == "判定":
                check = value
            else:
                candidates = value
            body = body[:note.start()].rstrip()
        items.append((name, body, condition, check, candidates))
    return items


def _template_of(root):
    """最新の要件定義書の「9. 文章の形」と、そこに書いたテンプレートの名前を返す（SKILL.md の決まりで「テンプレート「名前」」と書く）。"""
    folder = root / "requirements"
    paths = _numbered(folder, "r", 3, ".md") if folder.is_dir() else []
    if not paths:
        return "", None
    shape, inside = [], False
    for line in paths[-1].read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            inside = line[3:].lstrip().startswith("9.")
            continue
        if inside:
            shape.append(line)
    shape = "\n".join(shape)
    match = re.search(r"テンプレート「([^」]+)」", shape)
    return shape, match.group(1) if match else None


def _chapter_previews(root, order):
    """番号の付いた章（「N.」で始まる2段目の見出し）の最後の文が次の章の予告かを判定し、予告の無い章を返す。

    最後の番号の章（まとめの直前）は対象にしない。脚注の中の文は本文の最後の文ではないので数えない。
    """
    footnotes, chapters = _footnote_blocks(root, order), []
    for sid in order["order"]:
        unit = _latest(root, sid)
        block = unit.get("block") if sid.startswith("b") else None
        if isinstance(block, dict) and block.get("kind") == "heading" and block.get("level") == 2:
            chapters.append([unit["text"], None] if re.match(r"^\d+\.", unit["text"]) else None)
            continue
        if chapters and chapters[-1] is not None and sid.startswith("s") and unit.get("in") not in footnotes:
            chapters[-1][1] = (sid, unit["text"])
    numbered = [chapter for chapter in chapters if chapter is not None]
    return [f"「{title}」の最後の文 {last[0] if last else '（文が無い）'}"
            for title, last in numbered[:-1] if not last or not re.search(r"(次|最後)の章", last[1])]


# 判定の名前から、問題の一覧を返す関数へ。新しい判定を足すときは、確認項目の（判定: 名前）と同じ名前で登録する
CHECKS = {"章の予告": _chapter_previews}


def _fingerprint(root, order):
    """確認したときの本文の指紋。確認のあとで本文が1字でも変わったら、その確認は外れる。

    頭の frontmatter（meta）は除く。タイトルやタグを入れても本文の確認は変わらないため（含めると meta を入れただけで全項目が確認し直しになった）。
    """
    article = _article(root, order)
    if article.startswith("---\n"):
        end = article.find("\n---\n", 4)
        if end != -1:
            article = article[end + 5:]
    # frontmatter の後の空行の有無で指紋が変わらないよう、頭の改行は落とす
    return hashlib.sha256(article.lstrip("\n").encode("utf-8")).hexdigest()


def _checklist_sources(root):
    """要件定義書の「9. 文章の形」と、確認項目の出どころ（標準と、使ったテンプレート）の (名前, 中身) の並びを返す。"""
    shape, template = _template_of(root)
    sources = [("標準", CHECKLIST.read_text(encoding="utf-8"))]
    if template:
        path = template_paths().get(template)
        if path is None:
            raise ValueError(f"要件定義書のテンプレートが見つかりません: {template}（一覧は templates）")
        sources.append((template, read_template(path)))
    return shape, sources


def _checklist_rows(root, order):
    """標準とテンプレートの確認項目ごとに (出どころ, 名前, 本文, 状態, 詳細) を返す。状態は 確認済み・確認後に変更・候補の確認が不足・未確認・通過・不通過。"""
    shape, sources = _checklist_sources(root)
    confirmed = {}
    folder = root / "checks"
    for path in (_numbered(folder, "k", 4, ".json") if folder.is_dir() else []):
        entry = _read_json(path)
        confirmed[(entry["source"], entry["item"])] = entry   # 番号の順に読むので、同じ項目は新しい確認が残る
    now, rows = _fingerprint(root, order), []
    for source, text in sources:
        for name, body, condition, check, candidates in checklist_items(text):
            if condition and condition not in shape:
                continue
            if check:
                if check not in CHECKS:
                    raise ValueError(f"{source} の確認項目「{name}」の判定がありません: {check}")
                problems = CHECKS[check](root, order)
                rows.append((source, name, body, "不通過" if problems else "通過", "・".join(problems)))
                continue
            required = _required_sids(root, order, source, name, candidates)
            entry = confirmed.get((source, name))
            if entry is None:
                rows.append((source, name, body, "未確認", f"候補 {len(required)} 文" if candidates else ""))
                continue
            detail = f"{'・'.join(entry['sids'])}: {entry['text']}"
            missing = [sid for sid in required if sid not in entry["sids"]]
            if missing:
                # 候補を全部含める決まりより前の確認や、候補が増えたあとの確認は、読んでいない文があるので確認済みにしない
                rows.append((source, name, body, "候補の確認が不足", f"未確認の候補 {'・'.join(missing)}"))
            else:
                rows.append((source, name, body, "確認済み" if entry["fingerprint"] == now else "確認後に変更", detail))
    return rows


def _required_sids(root, order, source, name, candidates):
    """確認項目の（候補: 名前）が指す、確認で必ず読む文の ID を返す。候補の無い項目は空。"""
    if not candidates:
        return []
    if candidates not in CANDIDATES:
        raise ValueError(f"{source} の確認項目「{name}」の候補がありません: {candidates}")
    return CANDIDATES[candidates](root, order)


def _checklist(root, order):
    """確認項目を状態つきで出す。全部が確認済みか通過なら 0、残りがあれば 1 を返す。"""
    rows = _checklist_rows(root, order)
    for source, name, body, state, detail in rows:
        mark = "x" if state in ("確認済み", "通過") else " "
        print(f"- [{mark}] {source} / {name}: {body}（{state}{'・' + detail if detail else ''}）")
    return int(any(state not in ("確認済み", "通過") for *_, state, _ in rows))


def _confirm(root, order, item, sids, text):
    """確認項目を1つ確認したことを、確かめた文の番号と本文の指紋つきで checks/ に残す（書き換えない）。"""
    matches = [row for row in _checklist_rows(root, order) if row[1] == item]
    if not matches:
        raise ValueError(f"確認項目がありません: {item}（一覧は checklist）")
    source, _name, _body, state, _detail = matches[0]
    if state in ("通過", "不通過"):
        raise ValueError(f"「{item}」は機械で判定する項目なので、確認を記録しません")
    listed = [sid.strip() for sid in sids.split(",") if sid.strip()]
    present = set(order["order"])
    if not listed or any(sid not in present for sid in listed):
        raise ValueError(f"確かめた文の番号を、本文にある ID で渡してください: {sids}")
    _shape, sources = _checklist_sources(root)
    candidates = next((cand for src, text in sources if src == source
                       for name, _body, _cond, _check, cand in checklist_items(text) if name == item), None)
    required = _required_sids(root, order, source, item, candidates)
    missing = [sid for sid in required if sid not in listed]
    if missing:
        raise ValueError(f"「{item}」は候補の文を全部確認して ID に含めてください（load の該当の節）。足りない文: {'・'.join(missing)}")
    (root / "checks").mkdir(exist_ok=True)
    version = _next_name(root / "checks", "k", 4, ".json")
    _write_json(root / "checks" / f"{version}.json", {
        "source": source, "item": item, "sids": listed, "text": text,
        "fingerprint": _fingerprint(root, order), "written_at": time.time_ns(),
    }, immutable=True)
    print(version)


def _export(root, order, flavor="gfm"):
    """記事の Markdown を、媒体の方言で記録の text.md に書き出す。"""
    _atomic_write(root / "text.md", _article(root, order, flavor))
    # 書き出しは止めない（途中の確認のための書き出しもあるため）。残っている確認項目を知らせる
    try:
        left = [name for _source, name, _body, state, _detail in _checklist_rows(root, order) if state not in ("確認済み", "通過")]
    except (ValueError, OSError) as error:
        left = [f"確認項目を読めない: {error}"]
    if left:
        print(f"警告: 確認項目が {len(left)} 件残っています（{'・'.join(left)}）。checklist で一覧", file=sys.stderr)


def _check_design(root, order, confirmed):
    """設計書と、文の段落の指し先を検査する。壊れた指し先は誤りとして返し、古い記録で起こる抜けは警告に留める。

    警告は標準エラーへ出す。アプリは check の標準出力を「検査の問題」として数えるので（app/server.py）、
    ADR-0003 の「前の記録はそのまま読む」に合わせて、古い記録を誤りに見せない。
    """
    problems, warnings, paragraphs = [], [], {}
    requirements = _numbered(root / "requirements", "r", 3, ".md")
    latest_requirements = requirements[-1].stem if requirements else None
    for path in _designs(root):
        try:
            based_on, paragraphs[path.stem] = _design_paragraphs(path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as error:
            problems.append(f"{path.stem}: {error}")
            continue
        if not (root / "requirements" / f"{based_on}.md").is_file():
            problems.append(f"{path.stem}: 設計書が基づく要件定義書のバージョンがありません: {based_on}")
        elif path == _designs(root)[-1] and based_on != latest_requirements:
            warnings.append(f"警告: 最新の設計書 {path.stem} は {based_on} に基づいています。最新の要件定義書は {latest_requirements} です")
    missing_para = []
    for sid in sorted(confirmed):
        for path in _versions(root, sid):
            try:
                sentence = _read_json(path)
            except (ValueError, OSError):
                continue  # 壊れたファイルは _check が誤りとして数える
            design, para = sentence.get("design"), sentence.get("para")
            if design is None and para is None:
                if path == _versions(root, sid)[-1] and sid in order["order"]:
                    missing_para.append(sid)
                continue
            if design not in paragraphs:
                problems.append(f"{sid} {path.stem}: 文が照らした設計書のバージョンがありません: {design}")
            elif para not in paragraphs[design]:
                problems.append(f"{sid} {path.stem}: 設計書 {design} に段落 {para} がありません")
    if paragraphs and missing_para:
        warnings.append(f"警告: 段落の番号の無い文が {len(missing_para)} 文あります（{'・'.join(missing_para)}）")
    starts = 0
    for sid in order["order"]:
        try:
            starts += _latest(root, sid)["tags"]["relation"] == "段落の始まり"
        except (ValueError, OSError, KeyError, TypeError):
            pass
    if not paragraphs and starts > 1:
        warnings.append(f"警告: 段落が {starts} つありますが、設計書がありません")
    for warning in warnings:
        print(warning, file=sys.stderr)
    return problems


def _check(root):
    """文とブロックの版・並び・メモ・設計・コメントの整合を検査する。"""
    order = _order(root)
    vocabulary = _vocabulary(root)
    problems = []
    confirmed = set()
    # 人の文の最新バージョンの数と、そのうち推測の執筆意図が付いた数（ADR-0002 の「数える」）
    human_latest = inferred_latest = 0
    directories = (_numbered(root / "sentences", "s", 4, "")
                   + _numbered(root / "blocks", "b", 4, ""))
    for directory in directories:
        versions = _versions(root, directory.name)
        for path in versions:
            confirmed.add(directory.name)
            label = f"{directory.name} {path.stem}"
            try:
                sentence = _read_json(path)
                if sentence.get("sid") != directory.name or sentence.get("ver") != path.stem:
                    raise ValueError("文の ID がファイル名と一致しません")
            except (ValueError, OSError) as error:
                problems.append(f"{label}: {error}")
                continue
            try:
                if directory.name.startswith("b"):
                    _validate_block(sentence.get("block"), sentence.get("text"))
                    _validate_block_tags(sentence.get("tags"))
                else:
                    _validate_tags(sentence.get("tags"), vocabulary)
            except ValueError as error:
                # 確定したバージョンは書き換えられないので、余分なキーが古いバージョンにだけ残っている記録は
                # 新しいバージョンを積めば直る。誤りにすると直す手段が無いまま check が通らなくなるので、知らせるだけにする
                if str(error).startswith("文機能に許可されていないキー") and path != versions[-1]:
                    print(f"警告: {label}: {error}（最新のバージョンでは直っています）")
                else:
                    problems.append(f"{label}: {error}")
            try:
                requirements = _identifier(sentence.get("requirements"), "r", 3)
                if not (root / "requirements" / f"{requirements}.md").is_file():
                    problems.append(f"{label}: 文機能が指す要件のバージョンがありません: {requirements}")
            except ValueError as error:
                problems.append(f"{label}: {error}")
            try:
                memo_path = path.with_name(f"{path.stem}-memo.json")
                human = sentence.get("source") == "human"
                if human and path == versions[-1] and not directory.name.startswith("b"):
                    human_latest += 1
                    inferred_latest += memo_path.is_file()
                if sentence.get("source") == "ai" and not memo_path.is_file():
                    problems.append(f"{label}: AI のバージョンにメモがありません")
                elif memo_path.is_file():
                    memo = _read_json(memo_path)
                    if (memo.get("by") in OUTSIDE_INTENT) != human:
                        problems.append(f"{label}: {'人の文のメモが推測か申告の印（by: inferred・reported）を持ちません' if human else 'tsuzuri の文に推測か申告のメモが付いています'}")
                    if memo.get("sid") != directory.name or memo.get("ver") != path.stem:
                        raise ValueError("メモの ID がファイル名と一致しません")
                    if type(memo.get("memo_at")) is not int or type(sentence.get("written_at")) is not int:
                        raise ValueError("メモまたは文の時刻が不正です")
                    if sentence.get("memo_at") != memo["memo_at"]:
                        problems.append(f"{label}: メモの時刻が文の記録と一致しません")
                    if memo["memo_at"] > sentence["written_at"]:
                        print(f"{label}: メモの時刻が文より後です（時計のずれかもしれない）")
            except (ValueError, OSError) as error:
                problems.append(f"{label}: {error}")
    if human_latest > inferred_latest:
        # 推測の執筆意図より前に作った人の文の記録は書き換えないので、誤りにせず知らせるだけにする
        print(f"警告: 人の文 {human_latest} 文のうち {human_latest - inferred_latest} 文に、推測か申告の執筆意図がありません（memo --inferred・--reported）")
    problems.extend(_check_design(root, order, confirmed))
    problems.extend(_check_containers(root, order))
    problems.extend(_check_footnotes(root, order))
    for sid in order["order"]:
        if sid not in confirmed:
            problems.append(f"{sid}: order にあるのに確定した文がありません")
    tracked = set(order["order"]) | {entry["sid"] for entry in order["retired"]}
    for sid in sorted(confirmed - tracked):
        problems.append(f"{sid}: 確定した文が order にも retired にもありません")
    for comment in _comments(root, order):
        if comment["note"] and (comment["note"].startswith("壊れた JSON") or comment["note"] == "行き先の無いコメント"):
            where = comment.get("file") or comment.get("sid") or f"{comment.get('ver')} の {comment.get('item')}"
            problems.append(f"{where}: {comment['note']}")
    for problem in problems:
        print(problem)
    return int(bool(problems))


def _parser():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("init", "req", "design", "meta", "memo", "write", "review", "comments", "check", "export", "show", "move", "words", "retire", "load", "cold", "drift", "examples", "templates", "checklist", "confirm", "pack", "unpack"):
        child = commands.add_parser(command)
        if command == "templates":
            child.add_argument("name", nargs="?", help="中身を出すテンプレートの名前。省くと一覧を出す")
            continue
        child.add_argument("record", nargs="?" if command == "examples" else None,
                           help="文書のパス" if command == "init" else "記録フォルダのパス")
        if command == "pack":
            child.add_argument("--out", help="書き出す共有用のファイル（既定は文書の名前の .tsz）")
        if command == "unpack":
            child.add_argument("--dir", help="展開する先のフォルダ（既定は今のフォルダ）")
        if command == "drift":
            child.add_argument("--since", help="比べる起点のバージョン（そのバージョンのある文だけ）")
        if command in ("req", "design", "meta"):
            child.add_argument("--file")
        if command in ("memo", "write", "review"):
            child.add_argument("--text", required=True)
            child.add_argument("--sid", required=command == "review")
        if command == "memo":
            child.add_argument("--block", action="store_true")
            child.add_argument("--after")
            child.add_argument("--from", dest="origins")
            child.add_argument("--inferred", action="store_true", help="人の文の執筆意図を AI が推測したもの（write --human と組にする）")
            child.add_argument("--reported", action="store_true", help="ほかのチャット AI が自分の文について申告した執筆意図（write --human と組にする）")
        if command in ("write", "review"):
            child.add_argument("--ver", required=command == "review")
        if command == "write":
            child.add_argument("--block")
            child.add_argument("--in", dest="container")
            child.add_argument("--tags", required=True)
            child.add_argument("--deviation")
            child.add_argument("--requirements")
            child.add_argument("--design")
            child.add_argument("--para")
            child.add_argument("--human", action="store_true")
            child.add_argument("--cont", action="store_true", help="箇条書きの中で、この文を前の文と同じ項目に続ける")
            child.add_argument("--title", help="このバージョンのタイトル（コミットの件名のように、何を直したかを1行で。v002 以降は付ける）")
        if command == "review":
            child.add_argument("--aspect", required=True)
        if command == "retire":
            child.add_argument("--sid", required=True, help="本文から外す文の ID")
            child.add_argument("--text", required=True, help="外す理由（review に残る）")
        if command == "move":
            child.add_argument("--sid", required=True, help="動かす文かブロックの ID")
            child.add_argument("--after", required=True, help="この文かブロックの直後へ動かす。start なら先頭へ")
        if command == "confirm":
            child.add_argument("--item", required=True, help="確認項目の名前（checklist の「/」の右）")
            child.add_argument("--sids", required=True, help="確かめた文の ID をカンマ区切りで")
            child.add_argument("--text", required=True, help="何を確かめたか")
        if command == "export":
            child.add_argument("--flavor", choices=FLAVORS, default="gfm", help="書き出す媒体の方言（既定は GitHub の Markdown）")
    return parser


TSZ_LIMIT = 200 * 1024 * 1024   # 展開する中身の合計の上限。受け取ったファイルで、展開して膨らむ zip にディスクを埋められないため
TSZ_ENTRIES = 20000             # 中のファイルの数の上限。数百の文の記録で数千件。空のファイルを大量に並べた zip で止まらないため
TSZ_DEPTH = 6                   # 名前の階層の上限。記録の中は「<記録>/sentences/s0001/v001.json」の3段まで
# 名前の1段に使える字。区切り・ドライブのコロン・制御文字・先頭の点（隠しファイル）を通さない
_TSZ_PART = re.compile(r"[^\x00-\x1f\x7f/\\:*?\"<>|.][^\x00-\x1f\x7f/\\:*?\"<>|]{0,199}")
_TSZ_TYPES = (0o100000, 0o040000)   # UNIX の種類のビットがあるとき、通すのは通常のファイルとフォルダだけ（リンク・FIFO・デバイスを拒む）


def _pack(root, out):
    """記録のフォルダと本文の文書を、共有用の1つのファイル（.tsz・中身は zip）にまとめる。"""
    root = root.resolve()
    if not root.name.endswith(".tsuzuri") or not (root / "order.json").is_file():
        raise ValueError(f"記録のフォルダではありません: {root}")
    document = root.with_name(root.name[:-len(".tsuzuri")])
    out = (Path(out) if out else document.with_suffix(".tsz")).resolve()
    # 書き出し先が文書そのものか記録の中だと、読む前に zip が上書きして壊す
    if out == document or root in out.parents:
        raise ValueError(f"書き出し先が文書か記録の中です: {out}")
    order = _read_json(root / "order.json")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        # 文書がリンクなら入れない（リンク先の別のファイルを渡してしまうため）
        if document.is_file() and not document.is_symlink():
            archive.write(document, document.name)
        for path in sorted(root.rglob("*")):
            # 印を読むだけのロックと、記録の外へ向くリンクは入れない
            if not path.is_file() or path.is_symlink() or path.name == ".lock":
                continue
            name = str(Path(root.name) / path.relative_to(root))
            if path == root / "order.json":
                # 文書の場所は書き手の PC の絶対パス（ユーザー名を含む）なので、名前だけにして渡す
                archive.writestr(name, json.dumps({**order, "document": document.name}, ensure_ascii=False, indent=2) + "\n")
            else:
                archive.write(path, name)
    print(out)


def _unpack(source, directory):
    """共有用のファイル（.tsz）を展開してライブラリに足し、記録フォルダを表示する。"""
    print(unpack_archive(source, directory))


def _tsz_names(infos):
    """zip の中の名前を、書く前に全部検査し、記録の名前と、記録の中の (info, 段の並び) と文書の info を返す。"""
    if len(infos) > TSZ_ENTRIES:
        raise ValueError("共有用のファイルの中のファイルが多すぎます")
    entries, seen, total = [], set(), 0
    for info in infos:
        parts = info.filename.rstrip("/").split("/") if info.is_dir() else info.filename.split("/")
        if not parts or len(parts) > TSZ_DEPTH or not all(_TSZ_PART.fullmatch(p) and p.rstrip(" ") == p for p in parts):
            raise ValueError(f"展開できない名前が含まれています: {info.filename!r}")
        # 種類のビットが0の項目（Python の writestr など）は通常のファイルとして扱う
        kind = (info.external_attr >> 16) & 0o170000
        if info.create_system == 3 and kind and kind not in _TSZ_TYPES:
            raise ValueError(f"通常のファイルでないものが含まれています: {info.filename!r}")
        if info.flag_bits & 0x1:
            raise ValueError(f"暗号化されたファイルは展開できません: {info.filename!r}")
        # 大文字小文字と Unicode の正規化だけが違う名前は、Windows と macOS で同じファイルになる
        key = unicodedata.normalize("NFC", "/".join(parts)).casefold()
        if key in seen:
            raise ValueError(f"同じ名前が2つ含まれています: {info.filename!r}")
        seen.add(key)
        total += info.file_size
        entries.append((info, parts))
    if total > TSZ_LIMIT:
        raise ValueError("展開した中身が大きすぎます")
    records = {parts[0] for _, parts in entries if parts[0].endswith(".tsuzuri")}
    if len(records) != 1:
        raise ValueError("共有用のファイルは、1つの文書とその記録だけを含めてください")
    record = records.pop()
    document = record[:-len(".tsuzuri")]
    documents = [info for info, parts in entries if parts[0] == document]
    if not document or any(parts[0] not in (record, document) for _, parts in entries) or \
            any(info.is_dir() or len(parts) != 1 for info, parts in entries if parts[0] == document) or len(documents) > 1:
        raise ValueError("共有用のファイルは、1つの文書とその記録だけを含めてください")
    return record, [(info, parts) for info, parts in entries if parts[0] == record], (documents[0] if documents else None)


def _tsz_copy(archive, info, target, budget):
    """1つのファイルを、実際に展開した字数を数えながら書き、残りの上限を返す。

    zip の見出しの大きさは申告の値で偽れるので、上限は書いた字数で守る。
    """
    with archive.open(info) as data, open(target, "xb") as out:
        while chunk := data.read(1 << 16):
            budget -= len(chunk)
            if budget < 0:
                raise ValueError("展開した中身が大きすぎます")
            out.write(chunk)
    return budget


def unpack_archive(source, directory):
    """共有用のファイル（.tsz のパスか、読める file オブジェクト）を展開してライブラリに足し、記録フォルダを返す。

    中の名前は1つの文書と1つの記録だけを受け取る。閲覧アプリも、画面で選ばれたファイルをこれで展開する。
    受け取ったファイルは信頼しない。名前は書く前に全部検査し、展開は展開先の中に作った一時フォルダで行い、
    全部書けて記録として読めたときだけ、最後に文書と記録を本来の名前へ移す。途中で拒んだら一時フォルダごと消すので、何も残らない。
    受け取った記録は order.json に received の印を付け、examples（利用者の直し方の手本）に混ぜない。
    """
    directory = Path(directory or ".").resolve()
    try:
        archive = zipfile.ZipFile(source)
    except zipfile.BadZipFile as error:
        raise ValueError(f"共有用のファイルとして読めません: {error}") from error
    with archive:
        record, entries, document = _tsz_names(archive.infolist())
        root, doc_path = directory / record, directory / record[:-len(".tsuzuri")]
        if os.path.lexists(root) or os.path.lexists(doc_path):
            raise ValueError(f"同じ名前の文書か記録がすでにあります: {root}")
        # 一時フォルダは本人だけが読み書きでき、展開先と同じ場所に置く（最後の移動を rename で済ませるため）
        staging = Path(tempfile.mkdtemp(prefix=".tsz-", dir=directory))
        moved = []
        try:
            budget = TSZ_LIMIT
            staged_root = staging / record
            staged_root.mkdir()
            for info, parts in entries:
                target = staging.joinpath(*parts)
                if info.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                budget = _tsz_copy(archive, info, target, budget)
            if document is not None:
                budget = _tsz_copy(archive, document, staging / document.filename, budget)
            # 記録として読めるかを、登録の前に確かめる。読めない記録が一覧に入ると、ほかの記録を読む命令まで止まる
            order = _order(staged_root)
            (staged_root / "order.json").unlink()
            _write_json(staged_root / "order.json", {**order, "document": str(doc_path), "received": True}, immutable=True)
            # 最後の移動。mkdir と link は既にある名前（リンクを含む）で失敗するので、確かめたあとに作られた名前も上書きしない
            root.mkdir()
            moved.append(root)
            for child in staged_root.iterdir():
                child.rename(root / child.name)
            if document is not None:
                os.link(staging / document.filename, doc_path)
                moved.append(doc_path)
        except (zipfile.BadZipFile, RuntimeError, NotImplementedError, EOFError) as error:
            _tsz_undo(moved)
            raise ValueError(f"共有用のファイルを展開できません: {error}") from error
        except BaseException:
            _tsz_undo(moved)
            raise
        finally:
            shutil.rmtree(staging, ignore_errors=True)
    register_record(root)
    return root


def _tsz_undo(paths):
    """途中で拒んだとき、本来の場所へ移し始めた文書と記録を消す（自分で作ったものだけ）。"""
    for path in reversed(paths):
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink(missing_ok=True)


def main(argv=None):
    """サブコマンドを実行し、利用者が直せる誤りは理由だけを返す。"""
    args = _parser().parse_args(argv)
    try:
        if args.command == "init":
            _init(args.record)
            return 0
        if args.command == "examples":
            _examples()
            return 0
        if args.command == "templates":
            _templates(args.name)
            return 0
        if args.command == "pack":
            _pack(Path(args.record), args.out)
            return 0
        if args.command == "unpack":
            _unpack(args.record, args.dir)
            return 0
        root = Path(args.record)
        order = _order(root)
        if args.command == "req":
            text = Path(args.file).read_text(encoding="utf-8") if args.file else sys.stdin.read()
            _requirement_items(text)
            version = _next_name(root / "requirements", "r", 3, ".md")
            _atomic_write(root / "requirements" / f"{version}.md", text, immutable=True)
            print(version)
        elif args.command == "design":
            text = Path(args.file).read_text(encoding="utf-8") if args.file else sys.stdin.read()
            based_on, _ = _design_paragraphs(text)
            if not (root / "requirements" / f"{based_on}.md").is_file():
                raise ValueError(f"設計書が基づく要件定義書のバージョンがありません: {based_on}")
            (root / "design").mkdir(exist_ok=True)
            version = _next_name(root / "design", "d", 3, ".md")
            _atomic_write(root / "design" / f"{version}.md", text, immutable=True)
            print(version)
        elif args.command == "meta":
            text = Path(args.file).read_text(encoding="utf-8") if args.file else sys.stdin.read()
            (root / "meta").mkdir(exist_ok=True)
            version = _next_name(root / "meta", "m", 3, ".md")
            _atomic_write(root / "meta" / f"{version}.md", text, immutable=True)
            print(version)
        elif args.command == "memo":
            _memo(root, args)
        elif args.command == "write":
            _write(root, args)
        elif args.command == "review":
            target = _sentence_path(root, args.sid, args.ver)
            if not target.is_file():
                raise ValueError(f"レビュー対象の文のバージョンがありません: {args.sid} {args.ver}")
            (root / "reviews").mkdir(exist_ok=True)   # git で配った記録は空の reviews/ を持たない
            version = _next_name(root / "reviews", "rv", 4, ".json")
            _write_json(root / "reviews" / f"{version}.json", {
                "sid": args.sid, "ver": args.ver, "aspect": args.aspect,
                "text": args.text, "written_at": time.time_ns(),
            }, immutable=True)
            print(version)
        elif args.command == "comments":
            for comment in _comments(root, order):
                print(json.dumps(comment, ensure_ascii=False))
        elif args.command == "check":
            return _check(root)
        elif args.command == "show":
            for sid in order["order"]:
                sentence = _latest(root, sid)
                memo_path = _sentence_path(root, sid, sentence["ver"]).with_name(f"{sentence['ver']}-memo.json")
                memo = _read_json(memo_path)["text"] if memo_path.is_file() else None
                keys = ("sid", "ver", "para", "text", "tags", "block" if sid.startswith("b") else "in")
                # タイトルは持つ版だけに出す（タイトルの無い最初のバージョンや古い記録の出力の形を変えないため）
                title = {"title": sentence["title"]} if sentence.get("title") else {}
                print(json.dumps({"sid": sentence.get("sid"), "ver": sentence.get("ver"), **title,
                                  **{key: sentence.get(key) for key in keys[2:]}, "memo": memo}, ensure_ascii=False))
        elif args.command == "move":
            _move(root, order, args.sid, args.after)
            print(args.sid)
        elif args.command == "export":
            _export(root, order, args.flavor)
        elif args.command == "retire":
            _retire(root, order, args.sid, args.text)
            print(args.sid)
        elif args.command == "load":
            _load(root, order)
        elif args.command == "cold":
            _cold(root, order)
        elif args.command == "drift":
            _drift(root, order, args.since)
        elif args.command == "words":
            _words(root, order)
        elif args.command == "checklist":
            return _checklist(root, order)
        elif args.command == "confirm":
            _confirm(root, order, args.item, args.sids, args.text)
        return 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"誤り: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
