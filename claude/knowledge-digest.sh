#!/usr/bin/env bash
# セッションの transcript（jsonl）の未処理の範囲を読み、repo をまたぐ理解を knowledge に
# 下書き（status: draft）として書く。区切りは compaction ごと、大きすぎれば CHUNK_BYTES ごと。
# 処理した行は $STATE/cursor.tsv、トークンと時間は $STATE/log.tsv に残す。
#
# 使い方: knowledge-digest.sh <transcript.jsonl> [--dry-run]
#   --dry-run: 区切った入力を $STATE/dry-run/ に書き出すだけで、claude は呼ばない
# 環境変数 KNOWLEDGE_DIGEST_MAX_7D=<%> を渡すと、7日の使用率がそこに達した時点で止まる（終了コード 3）
set -euo pipefail

K="${KNOWLEDGE_DIR:?KNOWLEDGE_DIR が未設定}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/knowledge-digest"
CHUNK_BYTES="${KNOWLEDGE_DIGEST_CHUNK_BYTES:-300000}"
TRUNC="${KNOWLEDGE_DIGEST_TRUNC:-1500}"
MODEL="${KNOWLEDGE_DIGEST_MODEL:-sonnet}"
# これより小さい区切りは、ほとんど何も書かれないので claude を呼ばずに処理済みにする
MIN_CHUNK="${KNOWLEDGE_DIGEST_MIN_CHUNK:-8000}"

jsonl="${1:?transcript の jsonl を渡す}"
dry=0; [ "${2:-}" = "--dry-run" ] && dry=1
[ -f "$jsonl" ] || { echo "見つからない: $jsonl" >&2; exit 1; }
sid=$(basename "$jsonl" .jsonl)
mkdir -p "$STATE"
touch "$STATE/cursor.tsv" "$STATE/log.tsv"

start=$(awk -F'\t' -v s="$sid" '$1==s{n=$2} END{print n+0}' "$STATE/cursor.tsv")
total=$(wc -l < "$jsonl" | tr -d ' ')
[ "$start" -ge "$total" ] && { echo "$sid: 未処理の行なし"; exit 0; }

# 行番号つきで会話の中身だけに絞る。compaction の区切りは "@@COMPACT@@" の行にする
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tail -n +"$((start + 1))" "$jsonl" | jq -rR --argjson base "$start" --argjson t "$TRUNC" '
  (input_line_number + $base) as $n
  | (try fromjson catch null) as $e
  | if $e == null or ($e.isSidechain // false) then empty
    elif $e.type == "system" and $e.subtype == "compact_boundary" then "@@COMPACT@@\t\($n)"
    elif $e.type == "user" or $e.type == "assistant" then
      ($e.message.content) as $c
      | (if ($c|type) == "string" then [ (if $e.isCompactSummary then "[compaction の要約] " else "" end) + $c ]
         else [ $c[]? |
           if .type == "text" then .text
           elif .type == "tool_use" then "[tool_use \(.name)] " + (.input|tostring|.[0:$t])
           elif .type == "tool_result" then "[tool_result] " + ((.content|if type=="string" then . else tostring end)|.[0:$t])
           else empty end ]
         end)[]
      | select(length > 0)
      | "L\($n) \($e.type): " + gsub("\n"; "\n    ")
    else empty end' > "$work/all.txt"

# 区切る。各区切りの最後の行番号をファイル名に入れる
awk -v max="$CHUNK_BYTES" -v dir="$work" -v start="$start" '
  function flush() { if (buf != "") { f = sprintf("%s/chunk-%06d-%06d.txt", dir, first, last); printf "%s", buf > f; close(f) } buf = ""; first = 0 }
  /^@@COMPACT@@\t/ { split($0, a, "\t"); last = a[2]; flush(); next }
  /^L[0-9]+ / { n = substr($1, 2) + 0; if (length(buf) + length($0) > max && buf != "") flush(); if (!first) first = n; last = n }
  { buf = buf $0 "\n" }
  END { flush() }' "$work/all.txt"

if [ "$dry" = 1 ]; then
  rm -rf "$STATE/dry-run"; mkdir -p "$STATE/dry-run"; cp "$work"/chunk-* "$STATE/dry-run/" 2>/dev/null || true
  ls -l "$STATE/dry-run"; exit 0
fi

prompt=$(cat <<'EOF'
あなたは knowledge（今の作業ディレクトリ）の手入れ役である。stdin に、ある coding agent のセッションの記録の一部がある（各行の先頭が L<行番号>）。

1. 先に CONVENTIONS.md と index.md を読む。規約に従って書く
2. 記録から「repo をまたいで使う理解」だけを拾う。事実・仕組み・比較・手順のうち、別の repo の作業でも役に立つものである。次は拾わない
   - その repo の中だけで使う理解、作業の経過、作業記録
   - 道具を作るときにしか使わない理解（その道具の内部の処理の直し方など）。道具を使う側の理解は拾う
   - agent の行動の規則（「〜する」「〜しない」という指示の形のもの）
   - user の判断や好み（agent の行動を変える判断は experience が受け持つ）
   - 記録の中でまだ結論が出ていない議論、後の行で覆された結論
   - 秘密の値（token・パスワード・個人の連絡先）
3. 拾ったものごとに、既存の概念ノートを Grep で探す。あれば書き直し（名前は変えない）、無ければ新しく作る。書いたノートは新規も書き直しも `status: draft` にする
   - generated: { by: claude-code/claude-sonnet-5-5, at: NOW }
   - sources: 記録に出てきた一次資料（URL、repo の docs の GitHub URL）と、この記録そのもの `transcript:SID#L<最初>-L<最後>`（根拠にした行の範囲）
4. index.md の目録を更新する。今の index.md は INDEX_BYTES バイトある。書き足すと CONVENTIONS の上限を超えるなら、規約どおり行を外して上限の内に収める
5. 書くものが無ければ何もしない。迷ったら書かない。数を増やすことが目的ではない
6. git は操作しない
7. 最後に、作った・書き直したノートの名前と、拾った理由を1行ずつだけ出力する。何も書かなかったら「なし」とだけ出力する
EOF
)
prompt=${prompt//SID/$sid}; prompt=${prompt//NOW/$(date +%Y-%m-%dT%H:%M:%S%z | sed -E "s/([0-9]{2})([0-9]{2})\$/\\1:\\2/")}

for chunk in "$work"/chunk-*.txt; do
  [ -f "$chunk" ] || continue
  if [ -n "${KNOWLEDGE_DIGEST_MAX_7D:-}" ]; then
    # 使用率はステータスラインの取得とキャッシュ（5分）に任せる
    echo '{}' | bash "$(dirname "$0")/statusline.sh" >/dev/null 2>&1 || true
    u=$(jq -r '.seven_day.utilization // empty' "${TMPDIR:-/tmp}/claude-sl/ClaudeCodecredentials.json" 2>/dev/null | cut -d. -f1)
    if [ -n "$u" ] && [ "$u" -ge "$KNOWLEDGE_DIGEST_MAX_7D" ]; then echo "7日の使用率が ${u}% で、上限 ${KNOWLEDGE_DIGEST_MAX_7D}% に達したので止める" >&2; exit 3; fi
  fi
  b=$(basename "$chunk" .txt); a=$(echo "$b" | cut -d- -f2 | sed 's/^0*//'); z=$(echo "$b" | cut -d- -f3 | sed 's/^0*//')
  bytes=$(wc -c < "$chunk" | tr -d ' ')
  if [ "$bytes" -lt "$MIN_CHUNK" ]; then
    awk -F'\t' -v s="$sid" '$1!=s' "$STATE/cursor.tsv" > "$STATE/cursor.tmp"
    printf '%s\t%s\n' "$sid" "$z" >> "$STATE/cursor.tmp"; mv "$STATE/cursor.tmp" "$STATE/cursor.tsv"
    echo "$sid L$a-L$z: 小さいので飛ばす（${bytes}B）"
    continue
  fi
  t0=$(date +%s)
  # 子の claude は transcript を残さず、user の hook（experience の queue など）も読まない
  out=$(cd "$K" && EXPERIENCE_DIR= KNOWLEDGE_DIGEST=1 claude -p "${prompt//INDEX_BYTES/$(wc -c < "$K/index.md" | tr -d ' ')}" \
          --model "$MODEL" --no-session-persistence --output-format json \
          --setting-sources project --strict-mcp-config \
          --permission-mode acceptEdits --allowedTools Read Glob Grep Write Edit \
          < "$chunk")
  secs=$(( $(date +%s) - t0 ))
  [ "$(echo "$out" | jq -r '.is_error')" = "false" ] || { echo "$out" >&2; exit 1; }
  changed=$(git -C "$K" status --porcelain | awk '{print $2}' | paste -sd, -)
  for m in $(git -C "$K" status --porcelain | awk '$2 ~ /\.md$/ && $2 != "index.md" {print $2}'); do
    uvx --quiet --with pyyaml python -I -c "import sys,yaml;yaml.safe_load(open(sys.argv[1]).read().split('---')[1])" "$K/$m" 2>/dev/null || echo "警告: $m の frontmatter が YAML として読めない" >&2
  done
  if [ -n "$changed" ]; then
    git -C "$K" add -A
    git -C "$K" commit -q -m "digest: $sid L$a-L$z" -m "$(echo "$out" | jq -r '.result')"
  fi
  printf '%s\t%s\tL%s-L%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M)" "$sid" "$a" "$z" "$bytes" \
    "$(echo "$out" | jq -r '[.usage.input_tokens, .usage.cache_creation_input_tokens, .usage.cache_read_input_tokens]|map(.//0)|add')" \
    "$(echo "$out" | jq -r '.usage.output_tokens // 0')" "$(echo "$out" | jq -r '.total_cost_usd // 0')" "$secs" "${changed:-なし}" >> "$STATE/log.tsv"
  # 区切りごとに位置を進める（途中で落ちても、次はそこから）
  awk -F'\t' -v s="$sid" '$1!=s' "$STATE/cursor.tsv" > "$STATE/cursor.tmp"
  printf '%s\t%s\n' "$sid" "$z" >> "$STATE/cursor.tmp"; mv "$STATE/cursor.tmp" "$STATE/cursor.tsv"
  echo "$sid L$a-L$z: $(echo "$out" | jq -r '.result' | head -5)"
done

# 最後の区切りの後ろの、会話でない行（attachment など）まで処理済みにする
awk -F'\t' -v s="$sid" '$1!=s' "$STATE/cursor.tsv" > "$STATE/cursor.tmp"
printf '%s\t%s\n' "$sid" "$total" >> "$STATE/cursor.tmp"; mv "$STATE/cursor.tmp" "$STATE/cursor.tsv"
