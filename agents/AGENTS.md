# Yosuke の環境メモ

## モデル別の作業スタイル（トークン節約）

> このセッションのモデルは、システムプロンプトの
> `You are powered by the model named ...` で判別できる。

**メインセッションが Fable 5 のときのみ** 以下に従う（コストが高いため）：

- **メイン（Fable 5）の役割は設計・タスク分解・レビュー・監査に専念する。**
- **設計が固まった実装は Agent tool で委譲する：**
  - 定型・機械的な作業（テスト追加、リネーム、定型 CRUD 等）→ `model: "sonnet"`
  - 中〜高難度の実装 → `model: "opus"`
- 委譲プロンプトには「対象ファイル・設計方針・完了条件・守る規約」を明記し、丸投げしない。
- サブエージェントの成果物（diff）はメインで必ずレビューしてから採用する。
- 設計と実装が不可分な特に高難度の箇所は、委譲せずメインで直接実装してよい。

**メインが Sonnet / Opus / Haiku のときはこの分担は適用しない**（無駄な再委譲を避ける）。

---

## Nix Darwin セットアップ

```bash
darwin-switch
# 実体: sudo darwin-rebuild switch --flake /Users/yosuke/workspace/github.com/YosukeIida/dotfiles#Yosukes-MacBook-Air
```

設定エントリ: `~/workspace/github.com/YosukeIida/dotfiles/flake.nix` の
`darwinConfigurations."Yosukes-MacBook-Air"`（host 固有設定は
`nix/hosts/darwin/yosuke-macbook-air.nix`、秘密値は agenix で `secrets/*.age`）。

> 2026-06 に単一 public repo 化。個人 skills だけ private overlay（dotfiles-private）
> にローカルパス symlink で取り込む。

---

## パッケージ管理の方針

- グローバル CLI ツール → `nix/home/packages.nix` の `home.packages`
- Homebrew formula/cask → `nix/profiles/darwin/homebrew.nix` の `brews` / `casks`
- プロジェクト固有のツール → `nix/flake.nix` の `packages`（nix devshell）
- `npm install -g` は使わない → `npx` か `nix/flake.nix` に追加する

新しい repo への devshell 追加・nixpkgs の存在確認・Nix GC の手順は
**devshell-setup スキル**を参照（Skill ツールで自動ロードされる）。

---

## Python 環境の方針

### 禁止事項

```bash
python3 -m pip install --user <package>  # ❌ macOS のシステム Python を汚す
pip install <package>                    # ❌ 同上
```

macOS の system Python（Xcode 由来）やユーザー領域（`~/Library/Python/`）には何も入れない。

### 正しい使い方

| 用途 | コマンド |
|---|---|
| 一時的なスクリプト実行 | `uvx --with <pkg> python script.py` |
| 複数パッケージが必要 | `uv run --with <pkg1> --with <pkg2> python script.py` |
| プロジェクト内（継続利用） | `uv add <pkg>` して `uv run python script.py` |
| HTTP サーバ（標準ライブラリ） | `python -m http.server 8080`（インストール不要） |

devshell が有効かの確認・direnv の手順は **devshell-setup スキル**を参照。
