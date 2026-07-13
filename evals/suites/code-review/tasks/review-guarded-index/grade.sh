#!/usr/bin/env bash
# 判定: すべて境界をガード済みのクリーンなコード。BUG をでっち上げないこと
set -euo pipefail
[ "$(grep -c '^BUG:' "$ANSWER_FILE" || true)" -eq 0 ] || { echo "false positive BUG reported"; exit 1; }
grep -q 'NO_BUGS' "$ANSWER_FILE" || { echo "NO_BUGS not stated"; exit 1; }
echo "pass"
