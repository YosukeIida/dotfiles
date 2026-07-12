#!/usr/bin/env bash
# 判定: register の mutable default 引数を「種類まで正しく」指摘し、余計な BUG をでっち上げないこと
set -euo pipefail
[ "$(grep -c '^BUG:' "$ANSWER_FILE" || true)" -le 1 ] || { echo "extra BUG lines (false positives)"; exit 1; }
grep -Eq 'BUG:.*:register\b' "$ANSWER_FILE" || { echo "register bug not reported"; exit 1; }
grep -Eiq 'BUG:.*register.*(mutable|ミュータブル|デフォルト引数|default (arg|argument|parameter)|共有|使い回|同じリスト|蓄積|残り続け)' "$ANSWER_FILE" \
  || { echo "bug type (mutable default) not identified"; exit 1; }
echo "pass"
