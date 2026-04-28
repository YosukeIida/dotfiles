#!/usr/bin/env bash
# Claude Code プラグインを冪等にインストールするスクリプト
# settings.json の enabledPlugins / extraKnownMarketplaces を動的に読み取る
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo "settings.json not found, skipping"
  exit 0
fi

# extraKnownMarketplaces を登録
python3 - "$SETTINGS" <<'PYEOF'
import json, sys, subprocess
with open(sys.argv[1]) as f:
    s = json.load(f)
for name, config in s.get("extraKnownMarketplaces", {}).items():
    src = config.get("source", {})
    if src.get("source") == "github":
        subprocess.run(
            ["claude", "plugins", "marketplace", "add", name, f"github:{src['repo']}"],
            capture_output=True
        )
PYEOF

# 現在インストール済みのプラグイン
INSTALLED=$(claude plugins list 2>/dev/null | grep -oE '[a-z-]+@[a-z-]+' || true)

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
