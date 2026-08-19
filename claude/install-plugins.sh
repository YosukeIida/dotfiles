#!/usr/bin/env bash
# Claude Code プラグインを冪等にインストールするスクリプト
# settings.json の enabledPlugins / extraKnownMarketplaces を動的に読み取る
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

# claude CLI 未導入時（新マシンの初回 darwin-switch では cask がまだ入っていない）は
# 何もせず終了する。codex/install-plugins.sh と同じガード。導入後の再 switch で入る。
if ! command -v claude >/dev/null 2>&1; then
  echo "claude command not found, skipping plugin installation (re-run darwin-switch after install)" >&2
  exit 0
fi

if [ ! -f "$SETTINGS" ]; then
  echo "settings.json not found, skipping"
  exit 0
fi

# extraKnownMarketplaces を登録
# `claude plugin marketplace add` は <source> 一つだけを取り、marketplace名は
# 相手の marketplace.json の name フィールドから自動的に決まる(この dict の
# key は決定に関与しない、あくまで人間向けのラベル)。
python3 - "$SETTINGS" <<'PYEOF'
import json, sys, subprocess
with open(sys.argv[1]) as f:
    s = json.load(f)
for name, config in s.get("extraKnownMarketplaces", {}).items():
    src = config.get("source", {})
    if src.get("source") == "github":
        subprocess.run(
            ["claude", "plugins", "marketplace", "add", src["repo"]],
            capture_output=True
        )
PYEOF

# marketplace add は登録するだけで、ローカルの索引が古いままのことがある。その状態だと
# enabledPlugins にあるプラグインが「marketplace に見つからない」で落ちる
# （新マシンの初回 darwin-switch で agmsg@fujibee-agmsg が実際に失敗した。上流の
# marketplace.json には存在していた）。install の前に全 marketplace を上流に合わせる。
# 名前を省略すると全件が対象。
claude plugins marketplace update >/dev/null 2>&1 || true

# 現在インストール済みのプラグイン。
# 文字クラスに大文字・数字を含めること: 小文字だけだと lualatex-pdf@YosukeIida のような
# 大文字を含む ID が既存判定から漏れ、毎回インストールを試みる無駄が出る。
INSTALLED=$(claude plugins list 2>/dev/null | grep -oE '[A-Za-z0-9._-]+@[A-Za-z0-9._-]+' || true)

# enabledPlugins を順にインストール
python3 -c "
import json, sys
with open('$SETTINGS') as f:
    s = json.load(f)
for plugin, enabled in s.get('enabledPlugins', {}).items():
    if enabled:
        print(plugin)
" | while IFS= read -r plugin; do
  if echo "$INSTALLED" | grep -qF "$plugin"; then
    echo "already installed: $plugin"
  else
    echo "installing: $plugin"
    claude plugins install "$plugin"
  fi
done
