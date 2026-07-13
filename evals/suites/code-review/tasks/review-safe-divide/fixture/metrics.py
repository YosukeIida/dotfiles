def success_rate(successes, total):
    """成功率を返す。total が 0 の場合は 0.0 を返す（成功率は定義できないため）。"""
    if total == 0:
        return 0.0
    return successes / total


def clamp(value, lo, hi):
    """value を [lo, hi] の範囲に収める。"""
    if value < lo:
        return lo
    if value > hi:
        return hi
    return value


def average(values):
    """values の平均を返す。空リストは None。"""
    if not values:
        return None
    return sum(values) / len(values)
