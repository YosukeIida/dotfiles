#!/usr/bin/env bash
# figma-pat.age（agenix 管理の Figma PAT）の失効前通知。
# launchd（figmaPatExpiryCheck、週次月曜 10:00）から実行される。
#
# PAT を再発行したら EXPIRY を書き換えること（agenix 再暗号化とセットで）。
# secrets/secrets.nix のコメントの期限とも整合させる。
set -euo pipefail

EXPIRY="2026-09-21"
NOTIFY_BEFORE_DAYS=14

now=$(date +%s)
exp=$(date -j -f "%Y-%m-%d" "$EXPIRY" +%s 2>/dev/null)
days=$(( (exp - now) / 86400 ))

echo "$(date '+%Y-%m-%d %H:%M') figma-pat expiry check: ${days} days left (expires ${EXPIRY})"

if [ "$days" -le "$NOTIFY_BEFORE_DAYS" ]; then
  /usr/bin/osascript -e "display notification \"figma-pat が ${days} 日後（${EXPIRY}）に失効します。再発行して agenix 再暗号化と本スクリプトの EXPIRY 更新を。\" with title \"dotfiles: PAT 失効警告\""
fi
