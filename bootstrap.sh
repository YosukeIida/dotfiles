#!/usr/bin/env bash
# 新しい Mac のセットアップスクリプト（単一 public repo + agenix 構成）
#
# 前提: このリポジトリ（public）は HTTPS で clone 済み:
#   git clone https://github.com/YosukeIida/dotfiles ~/workspace/github.com/YosukeIida/dotfiles
#   （git clone には Xcode Command Line Tools が必要: xcode-select --install）
#
# Step 0 が Nix / Homebrew 本体の有無を確認する。詳細な前提・移行手順は README.md 参照。
#
# 実行方法:
#   bash ~/workspace/github.com/YosukeIida/dotfiles/bootstrap.sh
#
# 各ステップは skip しながら続行する（公開リポジトリとして安全）。

set -uo pipefail # -e は外す（skip しながら続行するため）

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_DIR="$HOME/workspace/github.com/YosukeIida/dotfiles-private"
SKILLS_PUB_DIR="$HOME/workspace/github.com/YosukeIida/personal-agent-skills"

# flake attribute は各機の `hostname -s` と一致させる規約（flake.nix 参照）。
# HostName 未設定の macOS では hostname -s が DHCP/逆引き DNS 由来で動的に決まるため、
# Step 0 で固定を促す。DARWIN_HOST=... で明示的に上書きもできる。
DARWIN_HOST="${DARWIN_HOST:-$(hostname -s)}"

# ── ユーティリティ ─────────────────────────────────────────────────────
# 確認プロンプト。既定は No（y 以外は空 Enter も含めてすべて skip 扱い）。
ask() {
  local msg="$1" yn
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

# ── Step 0: 前提レイヤ（Xcode CLT / Nix / Homebrew / git filter）────────
# bootstrap 自体は clone 済みが前提だが、その先の darwin-switch には Nix 本体と、
# cask 導入のため Homebrew 本体が必要。工場出荷 Mac では未導入なのでここで確認する。
step 0 "前提レイヤの確認（Xcode CLT / Nix / Homebrew）"

# flake attr が存在しないホスト名のまま進むと Step 2 が必ず失敗するので、先に照合する。
if nix eval --raw "$DOTFILES_DIR#darwinConfigurations.$DARWIN_HOST.system" &>/dev/null; then
  ok "flake attribute が見つかりました: #$DARWIN_HOST"
else
  warn "flake attribute #$DARWIN_HOST が flake.nix にありません（hostname -s = $DARWIN_HOST）。"
  warn "  macOS の hostname -s は HostName 未設定だと DHCP/逆引き DNS 由来で動的に決まります。"
  warn "  新しいマシンでは先にホスト名を固定してください:"
  warn "     sudo scutil --set HostName <Yosukes-Mac-Studio 等>"
  warn "  そのうえで flake.nix の darwinConfigurations に同名の attr を追加してから再実行します。"
  warn "  （Nix 未導入の初回はこの照合自体ができないため、この警告は無視して構いません）"
fi

if xcode-select -p &>/dev/null; then
  ok "Xcode Command Line Tools は導入済み"
else
  warn "Xcode CLT が未導入。次を実行してから再実行してください: xcode-select --install"
fi

# **上流 Nix** であることが必要。Determinate Nix（Determinate Systems の fork）は
# 独自デーモン determinate-nixd で Nix 自身を管理するため nix-darwin と競合し、
# nix-darwin は activation でこれを検出して中断する（modules/system/checks.nix）。
# Step 2 まで進んでから失敗すると原因が分かりにくいので、ここで先に知らせる。
if command -v nix &>/dev/null; then
  if [ -e /usr/local/bin/determinate-nixd ]; then
    warn "Determinate Nix が入っています（$(nix --version 2>/dev/null)）。"
    warn "  nix-darwin と Nix 管理が競合するため Step 2 は必ず失敗します。上流 Nix に入れ替えてください:"
    warn "    sudo /nix/nix-installer uninstall"
    warn "    curl -fsSL https://install.determinate.systems/nix | sh -s -- install --prefer-upstream-nix"
    warn "  --prefer-upstream-nix が使えない場合（提供終了アナウンス済み）は公式インストーラ:"
    warn "    sh <(curl -L https://nixos.org/nix/install) --daemon"
    warn "  入れ替え後、nix --version に 'Determinate Nix' が出ないことを確認すること。"
  else
    ok "Nix は導入済み（$(nix --version 2>/dev/null)）"
  fi
else
  warn "Nix が未導入です。**上流 Nix** を入れてください（Determinate Nix は nix-darwin と競合する）:"
  warn "  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --prefer-upstream-nix"
  warn "  上記が使えない場合は公式インストーラ: sh <(curl -L https://nixos.org/nix/install) --daemon"
  warn "  導入後、新しいシェルを開いてから bootstrap を再実行してください。"
fi

# nix-darwin の homebrew モジュールは brew 本体を入れないため、ここで導入する。
if command -v brew &>/dev/null || [ -x /opt/homebrew/bin/brew ]; then
  ok "Homebrew は導入済み"
elif ask "Homebrew を公式インストーラで導入しますか？（全 cask/brew に必須）"; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && ok "Homebrew を導入しました" || warn "Homebrew 導入に失敗（続行します）"
else
  skip "Homebrew 導入（darwin-switch で cask/brew が入りません）"
fi

# strip-model の git clean filter を darwin-switch より前に設定する。
# これが無いと初回 switch 前の commit で settings.json の model キーが素通りする
# （通常は common/default.nix の activation が設定するが、それは初回 switch 後）。
if command -v git &>/dev/null; then
  git -C "$DOTFILES_DIR" config filter.strip-model.clean \
    "/usr/bin/python3 \"\$(git rev-parse --show-toplevel)/claude/git-filters/strip-model-clean.py\"" \
    && git -C "$DOTFILES_DIR" config filter.strip-model.smudge cat \
    && ok "git clean filter (strip-model) を設定" \
    || warn "git filter 設定に失敗"
fi

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
  warn "darwin-rebuild が未導入です（初回はこれが正常）。"
  if command -v nix &>/dev/null && ask "初回の nix-darwin 適用を実行しますか？（nix run 経由・初回のみ）"; then
    # ブランチは flake.nix の nix-darwin input と揃えること（ズレると別バージョンで初回適用される）。
    sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake "$DOTFILES_DIR#$DARWIN_HOST" \
      && ok "初回 nix-darwin 適用が完了（以後は darwin-switch コマンドが使えます）" \
      || warn "初回 nix-darwin 適用に失敗（Nix 導入・agenix 鍵・Homebrew を確認して再実行）"
  else
    skip "初回 nix-darwin 適用（Nix 未導入 or スキップ）"
  fi
fi

# ── Step 3: private overlay（個人 skills）の clone ────────────────────
step 3 "skills リポジトリの取得（dotfiles-private / personal-agent-skills）"
# gh は darwin-switch（Step 2）でしか入らないため、初回はここで未導入 or 未認証のことがある。
# Step 3/4 は gh を使うので、認証だけ先に済ませる。
if command -v gh &>/dev/null; then
  if gh auth status &>/dev/null; then
    ok "gh は認証済み"
  elif ask "gh auth login を実行しますか？（Step 3/4 と GitHub 操作に必要）"; then
    gh auth login || warn "gh auth login に失敗（後で手動実行してください）"
  else
    warn "gh 未認証のまま続行（private clone / SSH 鍵登録は後で再実行が必要）"
  fi
else
  warn "gh が未導入（Step 2 完了後に再実行すると使えます）"
fi
if [[ -d "$PRIVATE_DIR/.git" ]]; then
  ok "$PRIVATE_DIR は既に存在します"
elif command -v gh &>/dev/null && ask "gh で dotfiles-private を clone しますか？（HTTPS）"; then
  gh repo clone YosukeIida/dotfiles-private "$PRIVATE_DIR" \
    && ok "clone 完了。darwin-switch を再実行すると skills が symlink されます" \
    || warn "clone 失敗（gh auth login 済みか確認）"
else
  skip "private overlay の clone（個人 skills が無くても本体は動作します）"
fi

# 自作の公開 skills。activation（yosuke/common.nix）が skillsPubDir を symlink 元にするが、
# clone が無いと「リンク切れが自動掃除されるだけ」で静かに skills が丸ごと欠ける。
if [[ -d "$SKILLS_PUB_DIR/.git" ]]; then
  ok "$SKILLS_PUB_DIR は既に存在します"
elif command -v gh &>/dev/null && ask "gh で personal-agent-skills を clone しますか？（自作の公開 skills）"; then
  gh repo clone YosukeIida/personal-agent-skills "$SKILLS_PUB_DIR" \
    && ok "clone 完了。darwin-switch を再実行すると skills が symlink されます" \
    || warn "clone 失敗（gh auth login 済みか確認）"
else
  skip "personal-agent-skills の clone（自作の公開 skills が配備されません）"
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

# ── Step 5: ランチャー設定のインポート（手動）──────────────────────────
# 2026-07-30 に Asyar への移行を試したが、Clipboard History の画像プレビュー
# 不具合により Raycast をメインに戻した（Asyar は併用インストールのみ維持、
# 自動起動は無効化してグローバルホットキー(Option+Space)の衝突を回避）。
# .rayconfig はローカル履歴・デバイス固有データを含むため public では
# .gitignore 済み。実体は dotfiles-private に置くので、Step 3 の private
# clone 後にここが成立する。
step 5 "Raycast 設定のインポート（メイン） / Asyar 設定の反映（併用、任意）"
RAYCAST_RAYCONFIG=$(ls -t "$PRIVATE_DIR/raycast/"*.rayconfig 2>/dev/null | head -1)
if ! open -Ra "Raycast" &>/dev/null; then
  warn "Raycast 未インストール（Step 2 完了後に再実行してください）"
elif [[ -z "$RAYCAST_RAYCONFIG" ]]; then
  warn ".rayconfig が見つかりません: $PRIVATE_DIR/raycast/"
  warn "  → dotfiles-private を clone（Step 3）済みか、既存マシンで Raycast を export したか確認してください"
else
  ok "Raycast を開き、Settings → Advanced → Import で次のファイルを読み込んでください:"
  echo "      $RAYCAST_RAYCONFIG"
  ok "インポート時のパスワードは agenix 復号済み: ~/.config/raycast/export.env の RAYCAST_EXPORT_PW"
fi

if [[ -L "$HOME/Library/Application Support/org.asyar.app/settings.dat" ]]; then
  ok "(併用)Asyar の settings.dat は dotfiles 側から symlink 済み（Step 2 の postActivation が処理済み）"
fi
warn "(併用)Asyar は自動起動を無効化してある。手動起動時に Option+Space が Raycast と衝突する可能性に注意"

# ── 完了 ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  bootstrap 完了"
echo ""
echo "  初回の推奨順序（各ステップは前段の完了を前提とする）:"
echo "    Step 0 → Nix / Homebrew を導入 → 新しいシェルを開く"
echo "    Step 2 → 初回 nix-darwin 適用（darwin-rebuild が使えるようになる）"
echo "    → gh auth login → Step 3（private clone）→ Step 4（SSH 化）"
echo "    → Raycast 導入後に Step 5（.rayconfig import）を再実行"
echo ""
echo "  個別に再実行できます:"
echo "    Step 2: darwin-switch"
echo "    Step 3: gh repo clone YosukeIida/dotfiles-private $PRIVATE_DIR"
echo "            gh repo clone YosukeIida/personal-agent-skills $SKILLS_PUB_DIR"
echo "            → darwin-switch"
echo "    Step 4: gh ssh-key add ~/.ssh/id_ed25519.pub && git remote set-url ..."
echo ""
echo "  darwin-switch 後の手動ステップ（詳細は docs/new-machine-setup.md）:"
echo "    - TCC 権限付与（Hammerspoon / Karabiner / Raycast 等）"
echo "    - Claude/Codex/gh の再ログイン、Tailscale(headscale) 再認証"
echo "    - App Store にサインイン（Bitwarden 導入のため）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
