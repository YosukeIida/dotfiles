#!/usr/bin/env bash
# darwin-switch の直前に homebrew.nix の brews を検査し、node に依存する formula が
# 混入していたら警告して確認を求める。node をローカルに入れたくない方針
# （cctag / backlog-md は nodeless native binary に置き換え済み）を維持するための
# 早期検知。誤検知で switch を止めたくないので、eval/brew に失敗したら黙って通す。

# darwin-switch にそのまま貼り込まれる（builtins.readFile）ので、**関数として定義し**
# 呼び出し側が `check_node_deps || exit 1` する形にしてある。トップレベルに `exit 0` を
# 書くと、検査を通過した時点で darwin-switch 本体（sudo darwin-rebuild）に到達せず
# 「成功したように見えて何も適用されない」事故になる（2026-08-12 に類例が発生している）。
#
# HOST は darwin-switch が DARWIN_HOST として渡す。未設定でも nix eval が失敗して
# 検査をスキップするだけ（fail-open）。
check_node_deps() {
  local FLAKE_DIR="/Users/yosuke/workspace/github.com/YosukeIida/dotfiles"
  local HOST="${DARWIN_HOST:-}"

  local brews_json
  brews_json="$(nix eval --json "${FLAKE_DIR}#darwinConfigurations.${HOST}.config.homebrew.brews" 2>/dev/null || echo '[]')"

  # nix-darwin homebrew.brews は文字列のリストではなく、
  # {"name": "...", "brewfileLine": "...", ...} のリスト。
  # python3 は使わない: system python 使用禁止方針（CLAUDE.md）を Claude Code の
  # Bash hook が強制しており、python3 呼び出しがブロックされて formula_names が
  # 常に空になり、この if で早期 return して検査がまるごと空振りする、という事故が
  # 実際に起きた（2026-08-12）。jq は home.packages で常に入っている前提。
  local formula_names
  formula_names="$(echo "$brews_json" | jq -r '[.[] | if type == "object" then .name else . end] | join(" ")' 2>/dev/null || true)"

  if [ -z "$formula_names" ]; then
    return 0
  fi

  # NOTE: 裸の formula 名（例: "backlog-md"）で brew deps を呼ぶと、たとえその名前が
  # 自分の custom tap からインストール済みでも homebrew/core 側の定義に解決されてしまう
  # （実機で確認済みの Homebrew の挙動）。なので homebrew.nix に書いた tap-qualified 名
  # （例: "yosukeiida/casks-personal/backlog-md"）をそのまま渡し、正しい定義を見る。
  local deps_output
  deps_output="$(HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew deps --for-each $formula_names 2>/dev/null || true)"

  local flagged="" line formula rest d
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
    # 非対話実行（Claude Code 等、stdin が tty でない）では read が永久に
    # ブロックするだけなので、警告を出した上でそのまま続行する（このスクリプト
    # 自体が「誤検知で switch を止めたくない」fail-open 方針のため、対話不能な
    # 場面でもブロックより通知を優先する）。
    if [ -t 0 ]; then
      local ans
      read -r -p "このまま darwin-switch を続行しますか？ [y/N] " ans
      case "$ans" in
        [yY]*) ;;
        *)
          echo "中止しました。"
          return 1
          ;;
      esac
    else
      echo "  (非対話実行のため確認をスキップして続行します)"
    fi
  fi

  return 0
}
