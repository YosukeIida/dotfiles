#!/usr/bin/env bash
# 新しい Mac のセットアップスクリプト
#
# 実行方法:
#   cp .env.example .env   # .env にパスワードを記入してから
#   bash bootstrap.sh
#
# .env がなくてもスキップしながら続行します（GitHub公開用dotfilesとして安全）

set -uo pipefail  # -e は外す（skipしながら続行するため）

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# ── .env の読み込み ────────────────────────────────────────────────────
if [[ -f "$DOTFILES_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/.env"
  ok ".env を読み込みました"
else
  warn ".env が見つかりません（秘密情報が必要なステップはスキップされます）"
  warn "  → cp .env.example .env で作成してください"
fi

# ── Step 1: nix-darwin ────────────────────────────────────────────────
step 1 "nix-darwin のビルドと適用"
if command -v darwin-rebuild &>/dev/null; then
  if ask "darwin-switch を実行しますか？"; then
    darwin-switch && ok "nix-darwin 完了" || warn "nix-darwin 失敗（続行します）"
  else
    skip "nix-darwin"
  fi
else
  warn "darwin-rebuild が見つかりません"
  warn "  → https://github.com/LnL7/nix-darwin でインストールしてください"
fi

# ── Step 2: macOS defaults ────────────────────────────────────────────
step 2 "macOS デフォルト設定"
ok "macOS defaults は nix-darwin に統合済みです（Step 1 の darwin-switch で適用されます）"

# ── Step 3: SSH 鍵の生成 ──────────────────────────────────────────────
step 3 "SSH 鍵の生成（この Mac 専用）"
SSH_KEY="$HOME/.ssh/id_ed25519"

if [[ -f "$SSH_KEY" ]]; then
  skip "~/.ssh/id_ed25519 はすでに存在します"
elif ask "SSH 鍵を新規生成しますか？"; then
  read -rp "  鍵のコメント（例: macbook-2026）: " ssh_comment
  ssh_comment="${ssh_comment:-$(hostname -s)-$(date +%Y)}"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$ssh_comment" -f "$SSH_KEY"
  ok "SSH 鍵を生成しました: $SSH_KEY"
  echo ""
  echo "  ── 公開鍵（GitHub / サーバーに登録してください）──────────────"
  cat "${SSH_KEY}.pub"
  echo "  ────────────────────────────────────────────────────────────"
  echo ""
  echo "  登録先:"
  echo "    GitHub: https://github.com/settings/ssh/new"
  echo "    その他のサーバーには ssh-copy-id または手動で authorized_keys に追加"
  echo ""
  read -rp "  登録が完了したら Enter を押してください（スキップは Ctrl+C）..."
  ok "SSH 鍵のセットアップ完了"
else
  skip "SSH 鍵生成"
fi

# ── Step 4: Raycast 設定のインポート ──────────────────────────────────
step 4 "Raycast 設定のインポート"
RAYCAST_RAYCONFIG=$(ls -t "$DOTFILES_DIR/dotfiles/raycast/"*.rayconfig 2>/dev/null | head -1)

if ! open -Ra "Raycast" &>/dev/null; then
  warn "Raycast がインストールされていません（Step 1 完了後に再実行してください）"
elif [[ -z "$RAYCAST_RAYCONFIG" ]]; then
  warn ".rayconfig が見つかりません: $DOTFILES_DIR/dotfiles/raycast/"
elif ask "Raycast の設定をインポートしますか？"; then
  bash "$DOTFILES_DIR/dotfiles/raycast/import.sh" && ok "Raycast インポート完了（ダイアログでパスワードを入力してください）"
else
  skip "Raycast インポート"
fi

# ── 完了 ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  bootstrap 完了"
echo "  スキップされたステップは個別に再実行できます:"
echo "    Step 1: darwin-switch"
echo "    Step 2: darwin-switch  # macOS defaults も適用"
echo "    Step 3: ssh-keygen -t ed25519 -C \"comment\""
echo "    Step 4: bash dotfiles/raycast/import.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
