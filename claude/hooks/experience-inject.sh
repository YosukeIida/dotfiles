#!/usr/bin/env bash
# SessionStart hook: experience/（判断レシピの正本）から現在の作業 dir 向けの
# 1行索引を合成し、~/.claude/experience-index.md に生成する。
# context への注入はしない — 配送は ~/.claude/CLAUDE.md の @import 行が担う
# （Memory files 枠は compaction 後も disk から再注入されるため）。
#
# 他環境への導入（このスクリプトは self-contained）:
#   1. EXPERIENCE_DIR 環境変数に experience/ の絶対パスを設定（未設定なら何もしない）
#   2. settings.json の SessionStart（matcher: startup|resume|clear|compact）にこのスクリプトを登録
#   3. ~/.claude/CLAUDE.md に1行:「経験知の索引: @~/.claude/experience-index.md を意思決定の前に読むこと」
#   4. （任意）Codex: hooks の session_start に同スクリプトを登録すると同じ索引が使える
# dir 名の解決は $EXPERIENCE_MANIFEST（manifest.tsv 形式:
# "<repo相対パス>\t<短名>"）があればそれを、無ければ git root の basename を使う。
#
# 脱出口: EXPERIENCE_INJECT=off
set -u

[ "${EXPERIENCE_INJECT:-on}" = "off" ] && exit 0
EXP="${EXPERIENCE_DIR:-}"
[ -n "$EXP" ] && [ -d "$EXP" ] || exit 0

OUT="$HOME/.claude/experience-index.md"
LIMIT=60

# --- 現在の dir の短名を解決する ---
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
short=$(basename "$root")
manifest="${EXPERIENCE_MANIFEST:-}"
if [ -n "$manifest" ] && [ -f "$manifest" ]; then
  # manifest は "workspace/github.com/owner/repo<TAB>短名"。root のサフィックス一致で引く
  m=$(awk -F'\t' -v r="$root" 'index(r, $1) { print $2; exit }' "$manifest")
  [ -n "$m" ] && short="$m"
fi

# --- GROUPS.md から結合相手の dir を解決する（対称） ---
# HTML コメント（複数行含む）・見出し・フェンスを落とした残りの行を宣言として読む
dirs="global $short"
groups="$EXP/GROUPS.md"
if [ -f "$groups" ]; then
  decl=$(sed '/<!--/,/-->/d' "$groups" | grep -vE '^\s*(#|```)' | grep -v '^\s*$' || true)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case ",$(echo "$line" | tr -d ' ')," in
      *",$short,"*) dirs="$dirs $(echo "$line" | tr ',' ' ')" ;;
    esac
  done <<< "$decl"
fi
# 重複除去
dirs=$(printf '%s\n' $dirs | awk '!seen[$0]++')

# --- 索引を合成する ---
tmp=$(mktemp)
{
  echo "<!-- 機械生成: experience-inject.sh が SessionStart ごとに更新する。手で編集しない -->"
  echo "# 経験知の索引（現役レコードのみ・詳細は各ファイルを Read）"
  echo ""
} > "$tmp"

# 未 wrap-up セッションのキューがあれば冒頭で通知する（消し込みは /wrap-up の担当）
queue="$EXP/.queue.tsv"
if [ -s "$queue" ]; then
  n=$(wc -l < "$queue" | tr -d ' ')
  echo "> 未 wrap-up のセッションが ${n} 件ある（${queue}）。user に「前回分の wrap-up を今やるか」を一度だけ確認すること。" >> "$tmp"
  echo "" >> "$tmp"
fi

count=0
for d in $dirs; do
  dir="$EXP/$d"
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    # frontmatter から type、本文から 判断/確度 の1行を引く
    type=$(sed -n '/^---$/,/^---$/p' "$f" | awk -F': *' '$1=="type"{print $2; exit}')
    conf=$(grep -m1 -oE '\*\*確度\*\*: *[SAB]' "$f" | grep -oE '[SAB]$')
    desc=$(grep -m1 -E '^\*\*判断\*\*:' "$f" | sed 's/^\*\*判断\*\*: *//')
    [ -n "$desc" ] || desc=$(sed -n '/^---$/,/^---$/!p' "$f" | grep -m1 -vE '^\s*$|^#' | head -c 120)
    echo "- [${type:-note}/${conf:-B}] ${name} — ${desc}（${d}）" >> "$tmp"
    count=$((count + 1))
  done
done

if [ "$count" -gt "$LIMIT" ]; then
  echo "" >> "$tmp"
  echo "> 警告: 索引が ${count} 行あり上限 ${LIMIT} を超えている。/wrap-up で棚卸し（archive・supersede）せよ。" >> "$tmp"
fi

mkdir -p "$HOME/.claude"
mv "$tmp" "$OUT"
exit 0
