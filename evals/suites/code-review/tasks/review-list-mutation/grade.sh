#!/usr/bin/env bash
# 判定: remove_expired のリスト反復中変更バグ（要素がスキップされる）を種類まで正しく指摘し、
# 正常な count_by / first_match を誤検出しないこと
set -euo pipefail
[ "$(grep -c '^BUG:' "$ANSWER_FILE" || true)" -le 1 ] || { echo "extra BUG lines (false positives)"; exit 1; }
grep -Eq 'BUG:.*:remove_expired\b' "$ANSWER_FILE" || { echo "remove_expired bug not reported"; exit 1; }
grep -Eiq 'BUG:.*remove_expired.*(反復中|iterat|イテレート|スキップ|skip|インデックス|index|飛ばされ|要素.*(消え|抜け|漏れ)|削除漏れ|同一リスト.*変更)' "$ANSWER_FILE" \
  || { echo "bug type (mutate-while-iterating) not identified"; exit 1; }
echo "pass"
