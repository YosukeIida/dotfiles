#!/usr/bin/env bash
# PostToolUse (Edit|Write) hook: 書き込まれた Markdown を suiko で検査し、
# warn 以上の finding があれば stderr + exit 2 で Claude 本人に返す。
# 書き込み自体は止めない（PostToolUse なので既に成功している）。
# 直すか残すかの判断は style-notes skill（dotfiles-private）の作法に従う。
#
# 脱出口: SUIKO_LINT=off で全体を無効化。
set -u

[ "${SUIKO_LINT:-on}" = "off" ] && exit 0

# suiko が無い環境（darwin-switch 前・他マシン）では黙って素通し
command -v suiko >/dev/null 2>&1 || exit 0

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# 対象: .md のみ（.tex は suiko がマスク非対応のため対象外）
case "$file_path" in
  *.md) ;;
  *) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

# 除外: 規約ファイル・メモリー・ルール自身・vendored skill・作業ログ以外の生成物
base=$(basename "$file_path")
case "$base" in
  CLAUDE.md|AGENTS.md|MEMORY.md|HANDOVER.md|SKILL.md) exit 0 ;;
esac
# experience/ は判断ログ（速度・正確さ優先の書き物）なので文体検査しない。
# drafts の書き味が accepted の質を下げるようなら戻して様子を見る。
case "$file_path" in
  */claude-memory/*|*/agents/skills/*|*/\.claude/*|*/node_modules/*|*/experience/*) exit 0 ;;
esac

# 日本語がほぼ無いファイルは素通し（英語 README 等への誤検知を根元から絶つ）
ja_chars=$(LC_ALL=C.UTF-8 grep -o '[ぁ-んァ-ヶ一-龠]' "$file_path" 2>/dev/null | wc -l | tr -d ' ')
[ "${ja_chars:-0}" -lt 30 ] && exit 0

# 検査。warn 以上で exit 2（stderr が Claude に届く）。
# 検査ツールの不具合で本体の作業を止めないため、suiko 自体の異常終了(1)は握りつぶす。
out=$(suiko lint --genre tech --fail-on warn "$file_path" 2>/dev/null)
status=$?
if [ "$status" -eq 2 ]; then
  {
    echo "[suiko] ${file_path} に AI 臭の疑いが検出された。以下の finding を確認し、"
    echo "style-notes skill の作法で対応すること: 直すなら該当文を丸ごと書き直す"
    echo "（語だけの置換は禁止）。残すなら理由を報告する。"
    echo ""
    printf '%s\n' "$out" | head -60
  } >&2
  exit 2
fi
exit 0
