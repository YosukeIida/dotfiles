def create_user(name, email):
    """ユーザー辞書を作る。email は正規化して保存する。"""
    email = email.strip().lower()
    if "@" not in email or email.rsplit("@", 1)[1].count(".") == 0:
        raise ValueError(f"invalid email: {email}")
    return {"name": name, "email": email}


def update_email(user, new_email):
    """既存ユーザーの email を差し替えた新しい辞書を返す。"""
    new_email = new_email.strip().lower()
    if "@" not in new_email or new_email.rsplit("@", 1)[1].count(".") == 0:
        raise ValueError(f"invalid email: {new_email}")
    return {**user, "email": new_email}


def display_name(user):
    """表示名を返す。"""
    return f"{user['name']} <{user['email']}>"
