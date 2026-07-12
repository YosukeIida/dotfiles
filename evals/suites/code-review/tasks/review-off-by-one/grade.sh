#!/usr/bin/env bash
# 判定: moving_average の off-by-one を「種類まで正しく」指摘し、余計な BUG をでっち上げないこと
set -euo pipefail
[ "$(grep -c '^BUG:' "$ANSWER_FILE" || true)" -le 1 ] || { echo "extra BUG lines (false positives)"; exit 1; }
grep -q 'BUG:.*moving_average' "$ANSWER_FILE" || { echo "moving_average bug not reported"; exit 1; }
grep -Eiq 'BUG:.*moving_average.*(off.?by.?one|最後|末尾|欠け|足りない|少ない|抜け|\+ ?1|window \+|- window \+)' "$ANSWER_FILE" \
  || { echo "bug type (off-by-one / missing last window) not identified"; exit 1; }
echo "pass"
