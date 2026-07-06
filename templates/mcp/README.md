# MCP サーバーテンプレート

プロジェクトスコープで必要時のみ MCP サーバーをロードするためのテンプレート集。
ツール数の多いサーバーを user スコープに常駐させるとコンテキストを圧迫するため、
使うリポジトリの直下に `.mcp.json` として配置する。

## figma-console（約130ツール）

デザイン作業をするリポジトリで:

```bash
cp ~/workspace/github.com/YosukeIida/dotfiles/templates/mcp/figma-console.mcp.json <repo>/.mcp.json
```

既に `.mcp.json` がある場合は `mcpServers` にキーをマージする。
バイナリ本体は nix（home.packages の figma-console-mcp 自前ビルド）で供給される。

> 経緯: 2026-07-06 の監査で user スコープ（~/.claude.json）から撤去し、
> 需要時ロードに切替（Figma 系 3 重複の解消。常時は figma plugin のみ残す）。
