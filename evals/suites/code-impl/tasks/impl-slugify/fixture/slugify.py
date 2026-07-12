def slugify(text):
    """タイトル文字列を URL slug に変換する。

    仕様:
    - ASCII 英大文字は小文字化する
    - 空白（連続を含む）は1つのハイフンに置き換える
    - ASCII 英数字・ハイフン以外の文字はすべて除去する（日本語等の非ASCII文字も除去）
    - 連続するハイフンは1つにまとめる
    - 先頭・末尾のハイフンは除去する
    """
    raise NotImplementedError
