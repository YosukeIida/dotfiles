# dotfiles

Yosuke の Mac 環境の本体 flake。nix-darwin / home-manager・Homebrew・agenix シークレットを
一元管理する。設計や運用の詳細は [`CLAUDE.md`](./CLAUDE.md) と [`docs/`](./docs/) を参照。

---

## 前提（工場出荷状態の Mac で最初に必要なもの）

`bootstrap.sh` は「このリポジトリが clone 済み」から始まる。その手前と、bootstrap が
面倒を見きれない本体レイヤは以下。`bootstrap.sh` の **Step 0** が存在確認と導入案内を行う。

1. **Xcode Command Line Tools**（`git` に必要）
   ```sh
   xcode-select --install
   ```
2. **Nix 本体**（Determinate Systems installer 推奨）
   ```sh
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```
   導入後は**新しいシェルを開く**（PATH 反映のため）。
3. **Homebrew 本体**（nix-darwin の homebrew モジュールは brew 自体を入れない。cask 群に必須）
   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
   （bootstrap Step 0 が未導入時にインストールを提案する）

---

## セットアップ（自分の新しい Mac）

```sh
# 0. 前提を満たす（上記）。リポジトリを clone:
git clone https://github.com/YosukeIida/dotfiles \
  ~/workspace/github.com/YosukeIida/dotfiles

# 1. bootstrap を実行（Step 0〜5 を対話的に進める）
bash ~/workspace/github.com/YosukeIida/dotfiles/bootstrap.sh
```

`bootstrap.sh` が進める内容:

| Step | 内容 |
|---|---|
| 0 | Xcode CLT / Nix / Homebrew の確認・導入、git filter 設定 |
| 1 | agenix 復号鍵（`~/.ssh/id_ed25519`）の確認 or 新規生成 |
| 2 | nix-darwin の初回適用（`nix run nix-darwin#darwin-rebuild -- switch`）。以後は `darwin-switch` |
| 3 | `gh auth login` → `dotfiles-private`（個人 skills）を clone |
| 4 | GitHub に公開鍵登録・両 repo の remote を SSH に切替 |
| 5 | Raycast 設定（`.rayconfig`）の import（メイン。要 dotfiles-private・Raycast 導入済み）。Asyar は併用インストールのみ（settings.dat は symlink 済みなら自動反映、自動起動は無効化済み） |

**初回の順序に注意**: Step 2（初回適用）が終わるまで `gh` / `raycast` / `claude` 等の
cask/CLI は入らない。`Step 2 → 新しいシェル → gh auth login → Step 3/4 → Raycast 導入後に Step 5`
の順で進める（bootstrap 完了メッセージにも表示される）。

日常運用:
```sh
darwin-switch        # nix 設定・homebrew を変更したあと
darwin-update        # nix flake update + switch
brew-upgrade-all     # brew の一括更新
```

---

## darwin-switch 後の手動ステップ（新マシン移行チェックリスト）

dotfiles / agenix では再現できない、マシン固有の状態・権限・データ。**旧マシンを初期化する前**に
上段（データ退避）を必ず済ませること。

### 旧マシンを消す前（データ消失を防ぐ・最優先）
- [ ] すべての git リポジトリの未 push / 未 commit / stash を push・退避（`~/workspace` 配下）
- [ ] FileVault の**回復キー**の保管場所を確認・記録（agenix identity の at-rest 保護が FileVault 依存）
- [ ] iCloud / git 外のローカルデータ（`~/Documents`・`~/Pictures` のルーズファイル等）を退避

### 新マシンで（認証・権限。多くはアプリ導入後）
- [ ] **App Store にサインイン** → Bitwarden が入る（agenix バックアップ鍵の回収に必要）
- [ ] **agenix 鍵**: 既存マシンの `~/.ssh/id_ed25519` を持ち込む、または Bitwarden 保管の共通鍵を
      `~/.config/agenix/key.txt` に置く（`identityPaths` に配線済み・どちらでも復号できる）
- [ ] **TCC 権限の付与**（システム設定 → プライバシーとセキュリティ）:
      Hammerspoon = アクセシビリティ / Raycast = アクセシビリティ /
      Karabiner-Elements = 入力監視 + **ドライバ拡張（システム機能拡張）の承認**
- [ ] **各 CLI の再ログイン**: `gh auth login` / Claude Code は各アカウントで `/login`
      （OAuth は Keychain 保存でファイル移行不可）/ Codex は `codex login`・MCP は `codex mcp login exa` 等
- [ ] **Tailscale(headscale)** の再認証（`tailscale login --login-server <URL>`）と旧ノードの失効
- [ ] GUI アプリ（Slack / Notion / Google Drive 等）の再ログイン
- [ ] 入力ソース（Kotoeri Romaji / ABC）の再設定
- [ ] **VSCode**: Settings Sync の「設定」「キーボードショートカット」カテゴリを**オフ**にする
      （settings/keybindings は dotfiles が管理するため。拡張機能等の同期は維持してよい）

---

## secrets（agenix）の仕組み

秘密値（SSH config・Cloudflare token・Headscale IP・プリンタ・Raycast パスワード・Figma PAT・
Anthropic API キー）は [`secrets/*.age`](./secrets/) に暗号化して置き、`darwin-switch` 時に
`~/.config` 等の安定パスへ復号配置する。詳細は [`nix/hosts/darwin/secrets.nix`](./nix/hosts/darwin/secrets.nix)。

- 復号 identity は `~/.ssh/id_ed25519` と `~/.config/agenix/key.txt`（Bitwarden 保管の共通鍵）の
  いずれか。2 台目を足すときはその公開鍵を [`secrets/secrets.nix`](./secrets/secrets.nix) の
  recipients に追記し `agenix -r` で全 `.age` を再暗号化する。
- 復号できない環境では該当ファイルを**配置しないだけ**（fail-soft）で switch は止まらない。

---

## 他の人がこのリポジトリを使う場合

このリポジトリは公開しているが、`darwinConfigurations."Yosukes-MacBook-Air"` は Yosuke 専用。
他の人は **`darwinConfigurations.example`**（agenix を import しない構成）を土台にし、fork して
以下を自分の値に書き換える:

- [`flake.nix`](./flake.nix) の `example`: `username` / `homedir`
- [`nix/hosts/darwin/common/default.nix`](./nix/hosts/darwin/common/default.nix) 冒頭の
  `darwinPublicConfigDir` の既定パス（自分の clone 先に）
- git identity は [`git/gitconfig`](./git/gitconfig) が `~/.gitconfig.local` を `[include]` する
  形なので、`~/.gitconfig.local` に自分の `[user]` を書けばよい（Yosuke の identity は入らない）

agenix 暗号化ファイルは他人の鍵では復号できないが、`example` 構成はそもそも secret を import
しないため、**その人自身の `~/.ssh/config` 等がそのまま使われる**（回避不要）。個人 tap の
Homebrew cask（nimbus / pindrop / powerglance）は公開されているので解決はするが、不要なら
[`nix/profiles/darwin/homebrew.nix`](./nix/profiles/darwin/homebrew.nix) から外してよい。

> 注: `apply.sh` は `hostname -s` で構成を選ぶため、ホスト名が
> `Yosukes-MacBook-Air` 以外の環境では使えない。`bootstrap.sh` / `darwin-switch` は
> flake attribute を明示指定するので影響しない。
