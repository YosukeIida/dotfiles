#!/usr/bin/env bash
# 判定: クリーンなコードに対して NO_BUGS を出し、バグをでっち上げないこと
# （両方向カバレッジ: audit.md「一方向だけの eval は一方向の最適化を生む」）
set -euo pipefail
[ "$(grep -c '^BUG:' "$ANSWER_FILE" || true)" -eq 0 ] || { echo "false positive BUG reported"; exit 1; }
grep -q 'NO_BUGS' "$ANSWER_FILE" || { echo "NO_BUGS not stated"; exit 1; }
echo "pass"
