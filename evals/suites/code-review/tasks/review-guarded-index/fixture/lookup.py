def first_or_none(items):
    """items の先頭要素を返す。空なら None。"""
    return items[0] if items else None


def get_or_default(d, key, default=None):
    """d[key] があればその値、なければ default を返す。"""
    return d[key] if key in d else default


def last_two(items):
    """items の末尾2件を新しいリストで返す。2件未満ならあるだけ返す。"""
    return list(items[-2:])
