#!/usr/bin/env bash
# agent の指示ファイルの中の `@~/...` の参照を、本文の後ろにそのファイルの中身として付けて標準出力に出す。
# `@` を展開しない harness（Codex・opencode）に、Claude Code と同じ中身を渡すために使う。
# 使い方: render-instructions.sh [--attachments-only] <指示ファイル>
#   --attachments-only: 本文を出さず、参照先の中身だけを出す（本文を別の経路で読む harness 向け）
set -euo pipefail

only=0
if [ "${1:-}" = --attachments-only ]; then
  only=1
  shift
fi
src=$1

[ "$only" = 1 ] || cat "$src"
grep -oE '@~/[^[:space:])`]+' "$src" | awk '!seen[$0]++' | while IFS= read -r ref; do
  f="$HOME/${ref#@~/}"
  [ -f "$f" ] || continue
  printf '\n\n<!-- %s の中身 -->\n\n' "${ref#@}"
  cat "$f"
done
