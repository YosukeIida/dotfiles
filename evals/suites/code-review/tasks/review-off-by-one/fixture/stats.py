def moving_average(values, window):
    """values の各位置で直近 window 件の移動平均のリストを返す。

    len(values) >= window を前提とし、返り値の長さは
    len(values) - window + 1 になるべきである。
    """
    result = []
    for i in range(len(values) - window):
        chunk = values[i:i + window]
        result.append(sum(chunk) / window)
    return result


def total(values):
    """合計を返す。空リストは 0。"""
    return sum(values)


def mean(values):
    """平均を返す。空リストは ValueError。"""
    if not values:
        raise ValueError("mean of empty list")
    return sum(values) / len(values)
