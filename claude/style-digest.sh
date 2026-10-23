#!/usr/bin/env bash
# セッションの transcript（jsonl）の未処理の範囲から、user が表現を直した箇所を拾い、
# style-guide の references/phrasing.md に 1 行ずつ追記する。commit はしない。
# 未 commit の行が、user がまだ確かめていない分になる。
# 処理した行は $STATE/cursor.tsv、トークンと時間は $STATE/log.tsv に残す。
#
# 使い方: style-digest.sh <transcript.jsonl> [--dry-run]
#   --dry-run: claude に渡す抜き書きを $STATE/dry-run.txt に書き出すだけで、claude は呼ばない
set -euo pipefail

G="${STYLE_GUIDE_DIR:-$HOME/.claude/skills/style-guide}"
OUT="$G/references/phrasing.md"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/style-digest"
MODEL="${STYLE_DIGEST_MODEL:-sonnet}"
# 直前の返答と user の発言を、それぞれ何文字まで渡すか。返答は末尾を残す（直されるのは最後の文面が多い）
TRUNC="${STYLE_DIGEST_TRUNC:-3000}"

jsonl="${1:?transcript の jsonl を渡す}"
dry=0; [ "${2:-}" = "--dry-run" ] && dry=1
[ -f "$jsonl" ] || { echo "見つからない: $jsonl" >&2; exit 1; }
[ -f "$OUT" ] || { echo "見つからない: $OUT" >&2; exit 1; }
sid=$(basename "$jsonl" .jsonl)
mkdir -p "$STATE"
touch "$STATE/cursor.tsv" "$STATE/log.tsv"

start=$(awk -F'\t' -v s="$sid" '$1==s{n=$2} END{print n+0}' "$STATE/cursor.tsv")
total=$(wc -l < "$jsonl" | tr -d ' ')
[ "$start" -ge "$total" ] && { echo "$sid: 未処理の行なし"; exit 0; }

advance() {
  awk -F'\t' -v s="$sid" '$1!=s' "$STATE/cursor.tsv" > "$STATE/cursor.tmp"
  printf '%s\t%s\n' "$sid" "$total" >> "$STATE/cursor.tmp"; mv "$STATE/cursor.tmp" "$STATE/cursor.tsv"
}

# user の発言ごとに、その直前の agent の返答（テキストだけ）と組にして並べる。
# tool の結果・hook や command の出力・compaction の要約は user の発言として数えない
excerpt=$(tail -n +"$((start + 1))" "$jsonl" | jq -nrR --argjson base "$start" --argjson t "$TRUNC" '
  foreach (inputs | [(try fromjson catch null), input_line_number]) as [$e, $ln]
    ({a: "", out: null};
     .out = null
     | if $e == null or ($e.isSidechain // false) or ($e.isMeta // false) then .
       elif $e.type == "assistant" then
         .a += ([$e.message.content[]? | select(.type == "text") | .text] | join("\n"))
       elif $e.type == "user" and (($e.isCompactSummary // false) | not) then
         ($e.message.content) as $c
         | ((if ($c|type) == "string" then $c else ([$c[]? | select(.type == "text") | .text] | join("\n")) end)
            | gsub("<system-reminder>[\\s\\S]*?</system-reminder>"; "") | gsub("^\\s+|\\s+$"; "")) as $u
         | if $u == "" or ($u | test("^(<local-command|<command-|<task-notification|<bash-|Base directory for this skill|\\[Request interrupted|This session is being continued)")) then .
           else .out = "@@ L\($ln + $base)\n[直前の返答]\n\(.a[-$t:])\n[user]\n\($u[0:$t])\n" | .a = "" end
       else . end;
     .out // empty)')

if [ "$dry" = 1 ]; then printf '%s' "$excerpt" > "$STATE/dry-run.txt"; wc -c "$STATE/dry-run.txt"; exit 0; fi
[ -n "$excerpt" ] || { advance; echo "$sid: user の発言なし"; exit 0; }

prompt=$(cat <<'EOF'
あなたは文体の規則集の手入れ役である。stdin は coding agent との会話の抜き書きで、「@@ L<行番号>」ごとに [直前の返答]（agent の返答の末尾）と [user]（その次の user の発言）が並ぶ。

user が agent の文章の表現・言い回し・用語・文体・構成を具体的に直した箇所、または直す方向を示した箇所だけを拾い、場面ごとの書き方の規則にする。次は拾わない。
- 内容・事実・数値の訂正、作業の指示、user の判断
- その文脈でしか成り立たず、ほかの文章に当てはめられない言い換え
- 下の既存の規則と同じもの
- agent が提案し、user が受け入れただけのもの

出力は 1 件 1 行で、次の形だけにする。前置きや説明は書かない。拾うものが無ければ「なし」とだけ出力する。
- 【場面】どう書くかを肯定の形で書く（直される前の言い方は括弧で添える）。理由を 1 文。〔transcript:SID8#L<根拠にした @@ の行番号>〕

既存の規則:
EOF
)
prompt="${prompt//SID8/${sid:0:8}}"$'\n'"$(cat "$OUT")"

t0=$(date +%s)
# 子の claude は道具を持たず、transcript を残さず、user の設定と hook を読まない
out=$(cd "$STATE" && echo "$excerpt" | claude -p "$prompt" \
        --model "$MODEL" --tools "" --no-session-persistence --output-format json \
        --setting-sources project --strict-mcp-config)
secs=$(( $(date +%s) - t0 ))
[ "$(echo "$out" | jq -r '.is_error')" = "false" ] || { echo "$out" >&2; exit 1; }

added=$(echo "$out" | jq -r '.result' | grep -E '^- 【.+〕$' | grep -F '〔transcript:' || true)
[ -n "$added" ] && printf '%s\n' "$added" >> "$OUT"
n=$(printf '%s' "$added" | grep -c . || true)
printf '%s\t%s\tL%s-L%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M)" "$sid" "$((start + 1))" "$total" \
  "${#excerpt}" \
  "$(echo "$out" | jq -r '[.usage.input_tokens, .usage.cache_creation_input_tokens, .usage.cache_read_input_tokens]|map(.//0)|add')" \
  "$(echo "$out" | jq -r '.usage.output_tokens // 0')" "$(echo "$out" | jq -r '.total_cost_usd // 0')" "$secs" >> "$STATE/log.tsv"
advance
echo "$sid: ${n} 件を追記"
