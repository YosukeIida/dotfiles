def remove_expired(items, is_expired):
    """items から is_expired(item) が True のものを取り除いた結果を返す。

    残った要素の順序は保たれるべきである。
    """
    for item in items:
        if is_expired(item):
            items.remove(item)
    return items


def count_by(items, key):
    """key(item) ごとの件数を返す。"""
    counts = {}
    for item in items:
        k = key(item)
        counts[k] = counts.get(k, 0) + 1
    return counts


def first_match(items, predicate):
    """predicate を満たす最初の要素を返す。なければ None。"""
    for item in items:
        if predicate(item):
            return item
    return None
