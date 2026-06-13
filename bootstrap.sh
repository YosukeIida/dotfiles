#!/usr/bin/env bash
# 新しい Mac のセットアップスクリプト（単一 public repo + agenix 構成）
#
# 前提: このリポジトリ（public）は HTTPS で clone 済み:
#   git clone https://github.com/YosukeIida/dotfiles ~/workspace/github.com/YosukeIida/dotfiles
#
# 実行方法:
#   bash ~/workspace/github.com/YosukeIida/dotfiles/bootstrap.sh
#
# 各ステップは skip しながら続行する（公開リポジトリとして安全）。

set -uo pipefail # -e は外す（skip しながら続行するため）

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_DIR="$HOME/workspace/github.com/YosukeIida/dotfiles-private"
DARWIN_HOST="Yosukes-MacBook-Air"

# ── ユーティリティ ─────────────────────────────────────────────────────
ask() {
  local msg="$1"
  read -rp "$msg [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]]
}

step() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Step $1: $2"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

ok()   { echo "  ✓ $*"; }
skip() { echo "  – skip: $*"; }
warn() { echo "  ! $*"; }

# ── Step 1: agenix identity の用意（darwin-switch より前に必須）─────────
# 新構成では秘密値（SSH config / cf token / Raycast PW / Headscale IP / プリンタ）を
# agenix で暗号化している。復号には ~/.ssh/id_ed25519 が必要で、かつその公開鍵が
# secrets/secrets.nix の recipient に含まれている必要がある。
step 1 "agenix の復号鍵（~/.ssh/id_ed25519）"
SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ -f "$SSH_KEY" ]]; then
  ok "~/.ssh/id_ed25519 が存在します"
  if grep -q "$(awk '{print $2}' "${SSH_KEY}.pub" 2>/dev/null)" "$DOTFILES_DIR/secrets/secrets.nix" 2>/dev/null; then
    ok "この鍵は secrets.nix の recipient に含まれています（復号できます）"
  else
    warn "この鍵は secrets.nix の recipient に未登録です。"
    warn "  → 既存マシンで secrets/secrets.nix にこの公開鍵を追記し、全 .age を再暗号化してください:"
    warn "     $(awk '{print $1" "$2}' "${SSH_KEY}.pub" 2>/dev/null)"
  fi
else
  warn "~/.ssh/id_ed25519 がありません。agenix が secret を復号できません。"
  warn "  選択肢:"
  warn "   (a) 既存マシンの ~/.ssh/id_ed25519 を持ち込む（最も簡単。recipient 済みなので即復号）"
  warn "   (b) ここで新規生成 → 既存マシンで secrets.nix に公開鍵を追記して再暗号化 → pull"
  warn "   (c) Bitwarden 保管の共通鍵を ~/.config/agenix/key.txt に置く運用へ移行"
  if ask "新規 ed25519 鍵を生成しますか？（選択肢 b）"; then
    read -rp "  鍵のコメント（例: macbook-2026）: " ssh_comment
    ssh_comment="${ssh_comment:-$(hostname -s)-$(date +%Y)}"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$ssh_comment" -f "$SSH_KEY"
    ok "生成しました。公開鍵（secrets.nix と GitHub に登録）:"
    echo ""
    cat "${SSH_KEY}.pub"
    echo ""
    warn "darwin-switch の前に、既存マシンで再暗号化 → push → ここで pull してください。"
  else
    skip "鍵生成（手動で用意してから再実行してください）"
  fi
fi

# ── Step 2: nix-darwin の適用 ─────────────────────────────────────────
step 2 "nix-darwin のビルドと適用（macOS defaults もここで適用）"
if command -v darwin-rebuild &>/dev/null; then
  if ask "darwin-switch を実行しますか？"; then
    sudo darwin-rebuild switch --flake "$DOTFILES_DIR#$DARWIN_HOST" \
      && ok "nix-darwin 完了（agenix が secret を ~/.config 等へ配置）" \
      || warn "nix-darwin 失敗（続行します）"
  else
    skip "nix-darwin"
  fi
else
  warn "darwin-rebuild が見つかりません"
  warn "  → https://github.com/nix-darwin/nix-darwin でインストールしてください"
fi

# ── Step 3: private overlay（個人 skills）の clone ────────────────────
step 3 "private overlay（dotfiles-private）の取得"
if [[ -d "$PRIVATE_DIR/.git" ]]; then
  ok "$PRIVATE_DIR は既に存在します"
elif command -v gh &>/dev/null && ask "gh で dotfiles-private を clone しますか？（HTTPS）"; then
  gh repo clone YosukeIida/dotfiles-private "$PRIVATE_DIR" \
    && ok "clone 完了。darwin-switch を再実行すると skills が symlink されます" \
    || warn "clone 失敗（gh auth login 済みか確認）"
else
  skip "private overlay の clone（個人 skills が無くても本体は動作します）"
fi

# ── Step 4: GitHub remote を SSH に切替 ───────────────────────────────
step 4 "git remote を HTTPS → SSH に切替"
if [[ -f "$SSH_KEY" ]] && command -v gh &>/dev/null; then
  if ask "公開鍵を GitHub に登録し、両 repo の remote を SSH にしますか？"; then
    gh ssh-key add "${SSH_KEY}.pub" -t "$(hostname -s)" 2>/dev/null \
      && ok "GitHub に公開鍵を登録しました" || warn "公開鍵の登録に失敗（既に登録済みかも）"
    git -C "$DOTFILES_DIR" remote set-url origin git@github.com:YosukeIida/dotfiles.git \
      && ok "dotfiles の remote を SSH に"
    [[ -d "$PRIVATE_DIR/.git" ]] && git -C "$PRIVATE_DIR" remote set-url origin git@github.com:YosukeIida/dotfiles-private.git \
      && ok "dotfiles-private の remote を SSH に"
  else
    skip "SSH 切替"
  fi
else
  skip "SSH 切替（id_ed25519 と gh が必要）"
fi

# ── Step 5: Raycast 設定のインポート（手動）──────────────────────────
step 5 "Raycast 設定のインポート"
RAYCAST_RAYCONFIG=$(ls -t "$DOTFILES_DIR/raycast/"*.rayconfig 2>/dev/null | head -1)
if ! open -Ra "Raycast" &>/dev/null; then
  warn "Raycast 未インストール（Step 2 完了後に再実行してください）"
elif [[ -z "$RAYCAST_RAYCONFIG" ]]; then
  warn ".rayconfig が見つかりません: $DOTFILES_DIR/raycast/"
else
  ok "Raycast を開き、Settings → Advanced → Import で次のファイルを読み込んでください:"
  echo "      $RAYCAST_RAYCONFIG"
  ok "インポート時のパスワードは agenix 復号済み: ~/.config/raycast/export.env の RAYCAST_EXPORT_PW"
fi

# ── 完了 ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  bootstrap 完了"
echo "  個別に再実行できます:"
echo "    Step 2: darwin-switch"
echo "    Step 3: gh repo clone YosukeIida/dotfiles-private $PRIVATE_DIR && darwin-switch"
echo "    Step 4: gh ssh-key add ~/.ssh/id_ed25519.pub && git remote set-url ..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
