# 新しい Mac のセットアップ手順

工場出荷状態の Mac（デスクトップ / ラップトップ問わず）を、この dotfiles で運用している
環境に持っていくまでの完全な手順。**上から順に実行する。順序に意味がある。**

`README.md` はこの文書の要約。詰まったらこちらを見る。

---

## 0. 先にホスト名を固定する

**最初にやること。** flake の attribute 名は各機の `hostname -s` と一致させる規約
（`apply.sh` がこの値で構成を引く）。

```sh
sudo scutil --set HostName Yosukes-Mac-Studio   # 例
```

新しいシェルを開いて確認する:

```sh
hostname -s   # → Yosukes-Mac-Studio
```

### なぜ先にやるのか

macOS のホスト名は 3 系統あり、`hostname -s` が返すのは**カーネルのホスト名**。
これは `HostName` が設定されていればその値、**未設定なら DHCP / 逆引き DNS 由来で
動的に決まる**（`LocalHostName` と一致する保証はない）。

実例（2026-08-19、Mac Studio の初期状態）:

| 種類 | 値 |
|---|---|
| `hostname -s` | **`Mac-Studio`** ← ネットワーク由来 |
| `scutil --get ComputerName` | `Yosuke’s Mac Studio` |
| `scutil --get LocalHostName` | `Yosukes-Mac-Studio` |
| `scutil --get HostName` | 未設定 |

`scutil --set HostName` を打つと 3 系統が揃って固定される。これをやらないと、
研究室と自宅で `hostname -s` が変わって `apply.sh` の解決先がぶれる。

---

## 1. flake に新しいホストを登録する（新機種のときだけ）

**既存機（Air 等）で**先に済ませて push しておく。Studio が届く前にできる。

`flake.nix` の `darwinConfigurations` に 1 行足し、機種固有モジュールを作る:

```nix
// builtins.mapAttrs mkYosukeHost {
  "Yosukes-MacBook-Air" = ./nix/hosts/darwin/yosuke/macbook-air.nix;
  "Yosukes-Mac-Studio"  = ./nix/hosts/darwin/yosuke/mac-studio.nix;   # ← 追加
}
```

`nix/hosts/darwin/` の層構造:

| ディレクトリ / ファイル | 役割 |
|---|---|
| `common/` | **他人も fork して使える層**（`darwinConfigurations.example` が import） |
| `yosuke/common.nix` | Yosuke の全 Mac 共通（`{ darwinHost }` を引数で受ける） |
| `yosuke/macbook-air.nix` | 蓋のある機種だけ（sleepctl 一式） |
| `yosuke/mac-studio.nix` | 常設機だけ（sleep never・停電後の自動起動） |
| `yosuke/secrets.nix` | agenix の宣言（全機共通） |

**機種固有に何を置くかの判断基準**: その機種にハードウェアが無いと意味をなさないもの。
例えば sleepctl は `AppleClamshellState`（蓋）を監視するので、蓋のない Mac Studio に
入れても発火せず 0.25 秒ループが常駐するだけになる。

CI（`.github/workflows/nix-check.yml`）にも新しい attr の `nix eval` を追加すること。

登録できたか確認:

```sh
nix eval --raw .#darwinConfigurations.Yosukes-Mac-Studio.system
```

---

## 2. 前提レイヤを入れる（新マシン側）

工場出荷 Mac に無く、`bootstrap.sh` が面倒を見きれない 3 つ。

### 2-1. Xcode Command Line Tools

```sh
xcode-select --install
```

GUI のダイアログが出るので進める（数分〜十数分）。

**なぜ必要か**: macOS には `git` が同梱されていない。`/usr/bin/git` はスタブで、
実行すると CLT のインストールを促すダイアログが出るだけ。リポジトリを clone できないと
何も始まらない。Nix のインストーラもビルドツールを前提にする。

Xcode 本体（数十 GB）は不要。

### 2-2. Nix 本体

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

**導入後は必ず新しいシェルを開く**（PATH が反映されないため）。

### 2-3. Homebrew 本体

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**nix-darwin の homebrew モジュールは brew 自体をインストールしない。**
宣言した cask / formula を `brew bundle` に流すだけなので、本体は手で入れる必要がある。

---

## 3. clone して bootstrap

この時点では SSH 鍵が無いので HTTPS で clone する。

```sh
git clone https://github.com/YosukeIida/dotfiles \
  ~/workspace/github.com/YosukeIida/dotfiles

bash ~/workspace/github.com/YosukeIida/dotfiles/bootstrap.sh
```

`bootstrap.sh` は各ステップを skip しながら進むので、**途中で止まっても同じコマンドで
何度でも再実行できる**。

| Step | 内容 |
|---|---|
| 0 | flake attr の照合、Xcode CLT / Nix / Homebrew の確認・導入、git filter 設定 |
| 1 | agenix 復号鍵（`~/.ssh/id_ed25519`）の確認 or 新規生成 |
| 2 | nix-darwin の初回適用（`nix run nix-darwin#darwin-rebuild -- switch`） |
| 3 | `gh auth login` → `dotfiles-private` と `personal-agent-skills` を clone |
| 4 | GitHub に公開鍵を登録・remote を SSH に切替 |
| 5 | Raycast 設定（`.rayconfig`）の import |

### 順序の注意

**Step 2 が終わるまで `gh` / `raycast` / `claude` 等の cask・CLI は 1 つも入らない。**
したがって実際にはこう進む:

```
Step 2（初回適用）→ 新しいシェル → gh auth login → Step 3 → Step 4
→ darwin-switch 再実行（skills が symlink される）
→ Raycast が入ってから Step 5 を再実行
```

Step 2 以降は `darwin-switch` コマンドが使えるようになる（初回だけ `nix run` 経由）。

---

## 4. agenix の鍵を通す

秘密値（SSH config・Cloudflare token・Headscale IP・プリンタ・Raycast パスワード・
Figma PAT 等）は `secrets/*.age` に暗号化されており、復号鍵が無いと配置されない。

### 仕組み

`.age` は本体をランダム共通鍵で 1 回だけ暗号化し、**その共通鍵を recipient ごとに
包んだ行**をヘッダに並べる:

```
age-encryption.org/v1
-> ssh-ed25519 v2vkcA ...     # Air の ~/.ssh/id_ed25519.pub
-> X25519 untXriAS ...        # Bitwarden 保管のバックアップ age 鍵
--- SVNzHrlj...
<暗号化された本体>
```

台数を足すと `-> ssh-ed25519` の行が増えるだけ。**SSH の ed25519 公開鍵はそのまま
age の recipient に使える**（専用の age 鍵を作る必要はない）。

### 手順（既存機との往復が 1 回入る）

1. **新マシン**で `ssh-keygen -t ed25519`（bootstrap Step 1 の選択肢 (b) が実行する）
2. 公開鍵を控えて **既存機**（Air 等）で:
   ```sh
   $EDITOR secrets/secrets.nix      # let の all に公開鍵を追記
   agenix -r                        # 全 .age を再暗号化
   git commit -am 'feat(secrets): <新マシン> を recipient に追加' && git push
   ```
3. **新マシン**で `git pull` → `darwin-switch`

### 注意点

- **`agenix -r` は復号できるマシンでしか実行できない**（一度復号してから再暗号化するため）。
  新マシン側では打てない。必ず既存機で。
- `agenix` CLI は nixpkgs に無いため flake input から `environment.systemPackages` で
  入れている。既存機で `darwin-switch` 済みなら PATH にある。
- **往復を待たずに先に `darwin-switch` してよい。** 復号できない secret は配置を
  スキップするだけ（fail-soft）で switch は止まらない。
- デバイスを外すときは recipient から消して `agenix -r` するが、**git 履歴に古い暗号文が
  残る**。本当に失効させたいなら秘密の値そのものをローテーションする。

### 緊急時（既存機が無い / 壊れた）

Bitwarden 保管の共通 age 鍵を `~/.config/agenix/key.txt` に置けば単独で復号できる。
`age.identityPaths` に配線済み（`nix/hosts/darwin/yosuke/secrets.nix`）。

### `secrets.nix` が 2 つあるので注意

| ファイル | 誰が読むか | 役割 |
|---|---|---|
| `secrets/secrets.nix` | **agenix CLI だけ**（`agenix -e` / `-r`）。nix build では評価されない | recipient 一覧。**公開鍵を足すのはこちら** |
| `nix/hosts/darwin/yosuke/secrets.nix` | nix-darwin モジュール | `age.secrets.*` の宣言と `age.identityPaths` |

---

## 5. 手動ステップ（dotfiles では再現できない）

nix / agenix で再現できない、マシン固有の状態・権限・データ。

### 旧マシンを消す前（置き換えの場合のみ・最優先）

- [ ] すべての git リポジトリの未 push / 未 commit / stash を退避（`~/workspace` 配下）
- [ ] FileVault の**回復キー**の保管場所を確認・記録
- [ ] iCloud / git 外のローカルデータ（`~/Documents`・`~/Pictures` のルーズファイル等）

### 新マシンで

- [ ] **FileVault を有効化**（agenix の復号鍵 `~/.ssh/id_ed25519` は mode 600 の平文で、
      at-rest 保護は FileVault 依存。共用スペースに置く機ほど重要）
- [ ] **App Store にサインイン** → Bitwarden が入る（agenix バックアップ鍵の回収に必要）
- [ ] **TCC 権限の付与**（システム設定 → プライバシーとセキュリティ）:
      Hammerspoon = アクセシビリティ / Raycast = アクセシビリティ /
      Karabiner-Elements = 入力監視 + **ドライバ拡張（システム機能拡張）の承認**
- [ ] **各 CLI の再ログイン**: `gh auth login` / Claude Code は各アカウントで `/login`
      （OAuth は Keychain 保存でファイル移行不可）/ `codex login` / `codex mcp login exa`
- [ ] **Tailscale (headscale)** の認証（`tailscale login --login-server <URL>`）と旧ノードの失効
- [ ] GUI アプリ（Slack / Notion / Google Drive 等）の再ログイン
- [ ] 入力ソース（Kotoeri Romaji / ABC）の再設定
- [ ] **VSCode**: Settings Sync の「設定」「キーボードショートカット」を**オフ**にする
      （dotfiles が管理するため。拡張機能等の同期は維持してよい）
- [ ] 画面ロックの待ち時間を実機で確認（`system.defaults.screensaver.*` が書き込む
      defaults ドメインは近年の macOS で無視されつつあり、no-op の可能性がある）

private overlay の `docs/notes-to-self.md` にも手動状態の備忘があるので、
**この一覧と両方**見ること。

---

## トラブルシュート

### `darwin-switch` が成功したように見えて何も適用されない

`/run/current-system` が更新されているか確認する:

```sh
readlink /run/current-system
nix eval --raw .#darwinConfigurations.<host>.config.system.build.toplevel.drvPath
```

かつては `check-node-deps.sh` のトップレベル `exit 0` が原因でこれが起きた
（`darwin-switch` に readFile で貼り込まれるため、検査を通過した時点でスクリプト全体が
終了し `sudo darwin-rebuild` に到達しない）。現在は関数化して塞いである。

### `brew bundle` が `exists in multiple taps` で止まる

upstream が tap 名を変えたのに旧 tap がローカルに残っていると、裸の cask 名が
両方に解決して bundle 全体が止まる。

```sh
brew tap | grep <owner>            # 重複を確認
diff <両方の .rb>                   # 定義が同一か確認
brew untap --force <owner>/<旧tap>  # 注意: cask 本体もアンインストールされる
```

`homebrew.nix` 側は **tap 修飾した名前**で書くと再発しない（例:
`"solarphlare/airmute/airmute"`）。

### `brew bundle` が失敗すると cleanup も走らない

`onActivation.cleanup = "zap"` は bundle の後段なので、bundle が止まっている間は
未宣言パッケージの掃除が一切行われない。**久しぶりに bundle が通ると溜まっていた掃除が
まとめて実行される**ので、意図しないアンインストールに見えることがある。

消えたものが `homebrew.nix` に宣言されているか確認する。宣言が無ければ、それは
`brew install` で命令的に入れた残骸を設定どおり掃除しただけ。

### 適用前に差分を確認したい

```sh
nix build --no-link --print-out-paths .#darwinConfigurations.<host>.config.system.build.toplevel
nix store diff-closures /run/current-system <上の出力>
```

---

## 日常運用

```sh
darwin-switch        # nix 設定・homebrew を変更したあと
darwin-update        # nix flake update + switch
brew-upgrade-all     # brew の一括更新
```
