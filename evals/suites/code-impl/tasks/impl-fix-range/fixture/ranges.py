def parse_range(spec):
    """"1-3,5,7-9" のような範囲指定を整数リストに展開する。

    範囲は両端を含む: "1-3" -> [1, 2, 3]
    """
    out = []
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-")
            out.extend(range(int(a), int(b)))
        else:
            out.append(int(part))
    return out
