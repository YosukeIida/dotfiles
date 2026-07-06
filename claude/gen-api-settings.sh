#!/usr/bin/env bash
# settings.api.json を settings.json（live）+ api-mode-overlay.json から生成する。
#
# - overlay のトップレベルキーが settings.json の同名キーを「丸ごと置換」する。
#   enabledPlugins は加算マージでは絞れない（Claude Code の仕様でスコープ間マージは
#   加算のみ）ため、API 従量課金モード用に plugin を最小セットへ置換する目的。
# - settings.api.json は生成物。手で編集しない（編集は api-mode-overlay.json へ）。
# - darwin-switch の postActivation から呼ばれる。手動実行も可。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

/usr/bin/python3 - "$DIR/settings.json" "$DIR/api-mode-overlay.json" "$DIR/settings.api.json" <<'PY'
import json, sys

base = json.load(open(sys.argv[1]))
overlay = json.load(open(sys.argv[2]))
base.update(overlay)  # トップレベルキー単位の置換

with open(sys.argv[3], "w") as f:
    json.dump(base, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo "generated: $DIR/settings.api.json"
