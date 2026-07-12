def register(name, tags=[]):
    """名前をタグ付きで登録エントリに変換する。

    呼び出しごとに独立したエントリを返すべきである。
    """
    tags.append("registered")
    return {"name": name, "tags": tags}


def merge_entries(entries):
    """エントリのリストを {name: tags} の辞書にまとめる。"""
    merged = {}
    for entry in entries:
        merged[entry["name"]] = list(entry["tags"])
    return merged


def format_entry(entry):
    """表示用の文字列を返す。"""
    return f"{entry['name']} [{', '.join(entry['tags'])}]"
