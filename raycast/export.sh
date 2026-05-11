#!/usr/bin/env bash
# Raycast 設定を settings.json に展開する
#
# 実行方法:
#   bash ~/workspace/github.com/YosukeIida/dotfiles/raycast/export.sh
#
# 除外キー（端末固有データ・使用統計）:
#   raycast_user_activity   使用統計 (~1MB)
#   raycast_app_defaults    インストール日・匿名IDなど端末固有
#   raycast_version         バージョン文字列
#
# フィルタリング（キーは残すがデータ部分のみ除去）:
#   builtin_package_rootSearch  hotkey/shortcut のない履歴エントリを除去
#   builtin_package_emoji       frecencyDate（使用頻度）のみ除去

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_OUT="$SCRIPT_DIR/settings.json"

EXCLUDE_KEYS=(
  raycast_user_activity
  raycast_app_defaults
  raycast_version
)

# ── パスワード（.env の RAYCAST_EXPORT_PW、なければ対話入力）──────────
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
[[ -f "$DOTFILES_ROOT/.env" ]] && source "$DOTFILES_ROOT/.env"

PASSWORD="${RAYCAST_EXPORT_PW:-}"
if [[ -z "$PASSWORD" ]]; then
  echo -n "Export password: "
  read -rs PASSWORD
  echo
fi

# ── エクスポート手順を表示 ────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  Raycast エクスポート設定                            │"
echo "├─────────────────────────────────────────────────────┤"
echo "│  ✅ チェックを入れるもの（設定）                     │"
echo "│    • Settings (aliases, hotkeys & favorites)         │"
echo "│    • Extensions                                      │"
echo "│    • MCP Servers                                     │"
echo "│    • Quicklinks                                      │"
echo "│    • Script Directories                              │"
echo "│    • Snippets                                        │"
echo "│    • Raycast Focus Categories                        │"
echo "├─────────────────────────────────────────────────────┤"
echo "│  ❌ チェックを外すもの（データ）                     │"
echo "│    • Clipboard History                               │"
echo "│    • AI Chats, Presets & Commands                    │"
echo "│    • Raycast Notes                                   │"
echo "├─────────────────────────────────────────────────────┤"
echo "│  保存先: $SCRIPT_DIR/"
echo "│  ファイル名はそのままで OK（日付入りでも自動検出）   │"
echo "└─────────────────────────────────────────────────────┘"
echo ""

# ── Raycast エクスポートダイアログを開く ─────────────────────────────
open "raycast://extensions/raycast/raycast/export-settings-data"

# ── 新しい .rayconfig が保存されるのを待つ（最大90秒）────────────────
echo -n "新しい .rayconfig の保存を待っています..."
FOUND=""
for i in $(seq 1 90); do
  # 過去5秒以内に更新された .rayconfig を探す
  FOUND=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.rayconfig" -newer "$0" 2>/dev/null | head -1)
  if [[ -n "$FOUND" ]]; then
    echo " 検出: $(basename "$FOUND")"
    break
  fi
  echo -n "."
  sleep 1
  [[ $i -eq 90 ]] && { echo ""; echo "Error: タイムアウト（90秒）"; exit 1; }
done

# ── JSON に変換（除外キーをフィルタリング）───────────────────────────
echo "変換中..."
TMP_JSON="${TMPDIR%/}/raycast_export_$$.json"
openssl enc -d -aes-256-cbc -nosalt \
  -in "$FOUND" -k "$PASSWORD" 2>/dev/null \
  | tail -c +17 \
  | gunzip > "$TMP_JSON"

python3 << PYEOF > "$JSON_OUT"
import json
EXCLUDE = {$(printf "'%s'," "${EXCLUDE_KEYS[@]}" | sed 's/,$//')}
with open('$TMP_JSON') as f:
    data = json.load(f)
filtered = {k: v for k, v in data.items() if k not in EXCLUDE}

# builtin_package_rootSearch: 履歴は除外し、ホットキー設定だけ残す
if 'builtin_package_rootSearch' in filtered:
    rs = filtered['builtin_package_rootSearch']
    rs['rootSearch'] = [
        entry for entry in rs.get('rootSearch', [])
        if entry.get('hotkey') or entry.get('shortcut')
    ]

# builtin_package_emoji: frecencyDate（使用頻度）だけ除去し、customKeywords は保持
if 'builtin_package_emoji' in filtered:
    emoji_pkg = filtered['builtin_package_emoji']
    emoji_pkg['emojis'] = [
        {k: v for k, v in e.items() if k != 'frecencyDate'}
        for e in emoji_pkg.get('emojis', [])
    ]

print(json.dumps(filtered, indent=2, ensure_ascii=False))
PYEOF

rm -f "$TMP_JSON"

# ── 古い .rayconfig を削除して最新5件だけ残す ────────────────────────
KEEP=5
ls -t "$SCRIPT_DIR"/*.rayconfig 2>/dev/null | tail -n +$((KEEP + 1)) | while IFS= read -r f; do
  rm -f "$f"
  echo "古いバージョンを削除: $(basename "$f")"
done

echo "完了: $JSON_OUT ($(wc -c < "$JSON_OUT" | awk '{printf "%.0f KB", $1/1024}'))"
VERSIONS=$(ls -t "$SCRIPT_DIR"/*.rayconfig 2>/dev/null | wc -l | tr -d ' ')
echo "保存済みバージョン: $VERSIONS 件"
echo "次: git diff dotfiles/raycast/settings.json → git add . → git commit"
