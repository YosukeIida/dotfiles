def truncate(text, limit, suffix="..."):
    """limit 文字を超える場合に suffix 付きで切り詰める。

    返り値は suffix を含めて limit 文字以内。
    limit が suffix より短い場合は suffix なしで単純に切る。
    """
    if len(text) <= limit:
        return text
    if limit <= len(suffix):
        return text[:limit]
    return text[: limit - len(suffix)] + suffix


def count_words(text):
    """空白区切りの単語数を返す。空文字列は 0。"""
    return len(text.split())


def indent(text, prefix="  "):
    """各行の先頭に prefix を付ける。空行はそのまま。"""
    lines = text.splitlines(keepends=True)
    return "".join(prefix + line if line.strip() else line for line in lines)
