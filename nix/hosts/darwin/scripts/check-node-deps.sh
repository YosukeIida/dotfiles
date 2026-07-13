#!/usr/bin/env bash
# darwin-switch の直前に homebrew.nix の brews を検査し、node に依存する formula が
# 混入していたら警告して確認を求める。node をローカルに入れたくない方針
# （cctag / backlog-md は nodeless native binary に置き換え済み）を維持するための
# 早期検知。誤検知で switch を止めたくないので、eval/brew に失敗したら黙って通す。

FLAKE_DIR="/Users/yosuke/workspace/github.com/YosukeIida/dotfiles"
HOST="Yosukes-MacBook-Air"

brews_json="$(nix eval --json "${FLAKE_DIR}#darwinConfigurations.${HOST}.config.homebrew.brews" 2>/dev/null || echo '[]')"

formula_names="$(echo "$brews_json" | python3 -c '
import json, sys
try:
    brews = json.load(sys.stdin)
except Exception:
    brews = []
# nix-darwin homebrew.brews は文字列のリストではなく、
# {"name": "...", "brewfileLine": "...", ...} のリスト
names = [b["name"] if isinstance(b, dict) else b for b in brews]
print(" ".join(names))
' 2>/dev/null || true)"

if [ -z "$formula_names" ]; then
  exit 0
fi

# NOTE: 裸の formula 名（例: "backlog-md"）で brew deps を呼ぶと、たとえその名前が
# 自分の custom tap からインストール済みでも homebrew/core 側の定義に解決されてしまう
# （実機で確認済みの Homebrew の挙動）。なので homebrew.nix に書いた tap-qualified 名
# （例: "yosukeiida/casks-personal/backlog-md"）をそのまま渡し、正しい定義を見る。
deps_output="$(HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew deps --for-each $formula_names 2>/dev/null || true)"

flagged=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  formula="${line%%:*}"
  rest="${line#*:}"
  for d in $rest; do
    if [ "$d" = "node" ]; then
      flagged="$flagged $formula"
    fi
  done
done <<< "$deps_output"

if [ -n "$flagged" ]; then
  echo ""
  echo "警告: 以下の brew formula が node に依存しています:$flagged"
  echo "  node をローカルに入れたくない方針のはずです。nodeless な代替 formula"
  echo "  （custom tap で native binary を直接 install する等）を検討してください。"
  echo ""
  read -r -p "このまま darwin-switch を続行しますか？ [y/N] " ans
  case "$ans" in
    [yY]*) ;;
    *)
      echo "中止しました。"
      exit 1
      ;;
  esac
fi
