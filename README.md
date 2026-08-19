# dotfiles

Yosuke の Mac 環境の本体 flake。nix-darwin / home-manager・Homebrew・agenix シークレットを
一元管理する。設計や運用の詳細は [`CLAUDE.md`](./CLAUDE.md) と [`docs/`](./docs/) を参照。

---

## セットアップ（自分の新しい Mac）

**完全な手順は [`docs/new-machine-setup.md`](./docs/new-machine-setup.md)。**
工場出荷状態からの前提レイヤ・順序・agenix 鍵の通し方・手動チェックリスト・
トラブルシュートまでまとまっている。以下は要約。

```sh
# 0. ホスト名を固定する（flake attribute 名と一致させる規約）
sudo scutil --set HostName Yosukes-Mac-Studio   # 例。新しいシェルで hostname -s を確認

# 1. 前提レイヤ（bootstrap が面倒を見きれない本体）
xcode-select --install
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
#    → 新しいシェルを開く
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. clone して bootstrap（Step 0〜5 を対話的に進める）
git clone https://github.com/YosukeIida/dotfiles \
  ~/workspace/github.com/YosukeIida/dotfiles
bash ~/workspace/github.com/YosukeIida/dotfiles/bootstrap.sh
```

引っかかりやすい 3 点:

- **ホスト名を先に固定する。** `hostname -s` は `HostName` 未設定だと DHCP / 逆引き DNS
  由来で動的に決まり、`LocalHostName` と一致する保証がない。
- **新しい機種は先に flake へ登録する**（既存機で `darwinConfigurations` に追加して push）。
- **Step 2 が終わるまで `gh` / `raycast` / `claude` は 1 つも入らない。**
  `Step 2 → 新しいシェル → gh auth login → Step 3/4 → Raycast 導入後に Step 5` の順。

日常運用:
```sh
darwin-switch        # nix 設定・homebrew を変更したあと
darwin-update        # nix flake update + switch
brew-upgrade-all     # brew の一括更新
```

---

## secrets（agenix）の仕組み

秘密値（SSH config・Cloudflare token・Headscale IP・プリンタ・Raycast パスワード・Figma PAT・
Anthropic API キー）は [`secrets/*.age`](./secrets/) に暗号化して置き、`darwin-switch` 時に
`~/.config` 等の安定パスへ復号配置する。詳細は [`nix/hosts/darwin/yosuke/secrets.nix`](./nix/hosts/darwin/yosuke/secrets.nix)。

- 復号 identity は `~/.ssh/id_ed25519` と `~/.config/agenix/key.txt`（Bitwarden 保管の共通鍵）の
  いずれか。2 台目を足すときはその公開鍵を [`secrets/secrets.nix`](./secrets/secrets.nix) の
  recipients に追記し `agenix -r` で全 `.age` を再暗号化する。
- 復号できない環境では該当ファイルを**配置しないだけ**（fail-soft）で switch は止まらない。

---

## 他の人がこのリポジトリを使う場合

このリポジトリは公開しているが、`nix/hosts/darwin/yosuke/` 以下（`Yosukes-MacBook-Air` /
`Yosukes-Mac-Studio`）は Yosuke 専用。他の人は **`darwinConfigurations.example`**
（agenix を import しない構成）を土台にし、fork して以下を自分の値に書き換える:

- [`flake.nix`](./flake.nix) の `example`: `username` / `homedir`
- [`nix/hosts/darwin/common/default.nix`](./nix/hosts/darwin/common/default.nix) 冒頭の
  `darwinPublicConfigDir` の既定パス（自分の clone 先に）
- git identity は [`git/gitconfig`](./git/gitconfig) が `~/.gitconfig.local` を `[include]` する
  形なので、`~/.gitconfig.local` に自分の `[user]` を書けばよい（Yosuke の identity は入らない）

agenix 暗号化ファイルは他人の鍵では復号できないが、`example` 構成はそもそも secret を import
しないため、**その人自身の `~/.ssh/config` 等がそのまま使われる**（回避不要）。個人 tap の
Homebrew cask（nimbus / pindrop / powerglance）は公開されているので解決はするが、不要なら
[`nix/profiles/darwin/homebrew.nix`](./nix/profiles/darwin/homebrew.nix) から外してよい。

> 注: `apply.sh` は `hostname -s` で構成を選ぶため、flake に同名の attr がない環境では
> 使えない。`darwin-switch` は flake attribute を埋め込み済み、`bootstrap.sh` は
> `DARWIN_HOST=...` で上書きできる。
