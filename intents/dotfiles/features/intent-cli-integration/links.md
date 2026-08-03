# intent-cli-integration — links

> See [overview.md](overview.md) for context.

## Reference links

### upstream

- リポジトリ: https://github.com/J-Tech-Japan/intent-system
- 公式サイト: https://www.intent-driven-development.com/
- v0.8.0 リリースノート（herdr-only モード追加）:
  https://github.com/J-Tech-Japan/intent-system/releases/tag/v0.8.0
- コンセプト解説（Zenn、日本語）:
  https://zenn.dev/jtechjapan_pub/articles/intent-cli-concept
- ライセンス: Apache-2.0

### 参照した公式ドキュメント

| doc | 何を確認したか |
|---|---|
| `docs/en/01-install.md` | `dotnet tool install -g` が第一推奨。self-contained binary は代替 → D-1 |
| `docs/ja/02-project-start.md` | トポロジー A / B の定義と比較表、G441（init → init-tree の2段構え）→ D-2 / D-4 |
| `docs/en/12-agent-message-orchestration.md` | 4スレッドの並行モデル、design は optional、transport は1チーム1つで混在禁止 |
| `docs/en/05-implementation-loop.md` | 3フォルダ役割（design / implementation / review）の分離 |

### 関連ツール

- herdr: https://herdr.dev/ — 導入済み（`HERDR_ENV=1`）。herdr-only transport の前提
- agmsg: 導入済み（plugin `agmsg@fujibee-agmsg`、`AGMSG_NODE` を設定済み）

### 導入時に使ったコマンド（記録）

```bash
# install（nix 経由。D-1）
# nix/home/packages.nix の custom derivation → darwin-switch

# dispatcher skill
intent-cli skill install --target claude --scope user

# host 初期化（トポロジー B。D-2 / D-4）
git worktree add --orphan -b main-metadata ~/workspace/github.com/YosukeIida/dotfiles-intent
intent-cli intent init --domain dotfiles --target-repo YosukeIida/dotfiles \
  --host-repo YosukeIida/dotfiles --write
intent-cli intent init-tree --domain dotfiles --target-repo YosukeIida/dotfiles \
  --project-type infrastructure --write
intent-cli intent add-feature --domain dotfiles --name intent-cli-integration --write
```

### 関連 ADR

- [0001 — public / private の分離](../../decisions/0001-public-private-split.md)
- [0002 — 外部 skill は vendor + sync に統一](../../decisions/0002-vendor-over-nix-for-skills.md)
- [0004 — パッケージの置き場所を用途で決める](../../decisions/0004-nix-first-packages.md)
