# ディレクトリ規約（2026-07-06 監査で策定）

方針: **「コードは workspace、書類は Documents、Downloads は一時置き場」**

## 理想構成

```
~/
├── workspace/
│   ├── github.com/<owner>/<repo>/   # 唯一のコード置き場（ghq 型）
│   │                                # owner は remote origin の実所有者に一致させる
│   └── overleaf/<project>/          # 非 GitHub の明示的ルートはこれのみ許可（git 管理推奨）
├── Documents/
│   ├── scans/
│   │   ├── receipts/<year>/         # 領収書（旧 ScanSnap Receipts）
│   │   ├── certificates/            # 証明書類（旧 ScanSnap Docs）
│   │   └── misc/                    # その他スキャン（旧 ScanSnap Home folder）
│   ├── tax/<year>/                  # 源泉徴収票・扶養控除申告書等
│   └── archives/                    # slack_data 等の過去エクスポート
├── Downloads/                       # 一時置き場のみ
└── texmf/                           # TeX 標準位置（現状維持）
```

## ルール

1. **Downloads は 30 日で空にする**。恒久保存するものは種別に応じて
   workspace / Documents へ移す。
2. **Downloads に機密ファイルを置かない**（秘密鍵・サービスアカウント JSON・
   パスワードファイル・DB ダンプ）。鍵・トークンは agenix（`secrets/*.age`）か
   Keychain、パスワードは パスワードマネージャへ。
3. **コード・ノートブックは必ず workspace 配下**。Downloads・Documents に
   .py / .ipynb を恒久保存しない。
4. **リポジトリの owner ディレクトリは remote origin に一致させる**
   （fork 元を追うだけなら fork 元 owner、自分で push するなら fork して自分の owner）。
5. **同一 repo の複数チェックアウトは `git worktree` を使う**か、
   ディレクトリ名にブランチ由来の suffix を付けて意図を明示する（例: s-code-etsuzan）。
6. **新規 repo 作成時**: 初回 commit を早期に行い（unborn 状態で作業を溜めない）、
   remote が無いものは private repo を作って push しておく。

## 移動マッピング（未実施・手動実行用）

| 現在 | 移動先 |
|---|---|
| `workspace/RaTeX/` | `workspace/github.com/erweixin/RaTeX/`（fork して push するなら YosukeIida/） |
| `workspace/overleaf-projects/` | `workspace/overleaf/`（+ git 化） |
| `Documents/Documents/` | 中身を `tax/` `archives/` `scans/` へ解体して解消 |
| `Documents/ScanSnap Receipts/` | `Documents/scans/receipts/<year>/` |
| `Documents/ScanSnap Docs/` | `Documents/scans/certificates/` |
| `Documents/ScanSnap Home folder/` | `Documents/scans/misc/` |
| `Documents/Codex/` | 不要なら削除（Codex 作業ログ） |
| Downloads 内の .py/.ipynb | 対応する workspace プロジェクトへ |

## 削除候補（実行前に要確認）

- `~/Claude`（空ディレクトリ、2026-06-17 以降未使用）
- `~/.th-client`（Thunder Client の誤配置残骸、2025-07 から放置）
- `~/.nimbus`（バイナリ消失済みの実験ツール設定、2026-05 から停止）
- `~/.cagent`（同上、2026-02 から停止）

## GitHub アーカイブ候補（最終コミット 1 年以上前）

NUTFES-Account (2024-10) / nutmeg-dashboard (2024-02) / settings (2024-05) /
nutfes-db-gui (2025-06) / karabiner (2025-02) /
MultiObjectiveOptimization-MyRepo (2021-04) / workspace-satysfi (2023-10)

→ 現役でなければ GitHub 側で archive し、ローカルからは削除してよい。
