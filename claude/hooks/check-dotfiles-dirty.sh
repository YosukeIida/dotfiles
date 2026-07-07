#!/usr/bin/env bash
# Stop hook: dotfiles の未コミット変更を検知してリマインドする。
# ~/.claude/settings.json 等は dotfiles への symlink のため、/plugin や /model の
# 操作で live 側だけが書き換わる。「変更後は必ず commit」原則の再発防止用。
# ブロックはしない（systemMessage を表示するだけで exit 0）。
#
# claude/settings.json・settings.api.json の "model" は /model のたびに書き換わる。
# git の clean filter（.gitattributes の filter=strip-model）は commit 内容から
# model を除外するが、`git status` の dirty 判定は clean filter を通さない生バイト
# 比較なので、model だけ変えても modified 扱いのまま残る（`git add` するまで消えない）。
# ここで index に触れず（`git add` は「判定」ではなく実際の staging 操作のため、
# permissions/hooks/enabledPlugins 等の本物の変更を意図せず stage してしまう）
# HEAD と worktree の内容を model 抜き・キー順無視で比較し、実質差分の有無だけを見る。
# Claude Code 自身が /model や /plugin のたびにキー順を変えて書き込むため、キー順は
# 無視しないと model 以外の理由で誤警告が出る。

DOTFILES="$HOME/workspace/github.com/YosukeIida/dotfiles"
MODEL_FILES=(claude/settings.json claude/settings.api.json)

normalize_json() {
  python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
data.pop("model", None)
print(json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2))
' 2>/dev/null
}

has_real_diff() {
  local f="$1"
  local head_norm worktree_norm
  head_norm=$(git -C "$DOTFILES" show "HEAD:$f" 2>/dev/null | normalize_json)
  worktree_norm=$(normalize_json < "$DOTFILES/$f" 2>/dev/null)
  [ "$head_norm" != "$worktree_norm" ]
}

exclude_pathspecs=()
for f in "${MODEL_FILES[@]}"; do
  exclude_pathspecs+=(":(exclude)$f")
done

dirty_files=$(git -C "$DOTFILES" status --porcelain -- . "${exclude_pathspecs[@]}" 2>/dev/null)

for f in "${MODEL_FILES[@]}"; do
  if git -C "$DOTFILES" status --porcelain -- "$f" 2>/dev/null | grep -q . && has_real_diff "$f"; then
    dirty_files="$dirty_files
 M $f"
  fi
done

dirty_files=$(printf '%s\n' "$dirty_files" | grep -v '^\s*$')
dirty_count=$(printf '%s\n' "$dirty_files" | grep -c .)

if [ "${dirty_count:-0}" -gt 0 ]; then
  files=$(printf '%s\n' "$dirty_files" | head -3 | awk '{print $2}' | tr '\n' ' ')
  printf '{"systemMessage": "⚠ dotfiles に未コミット変更が %s 件あります（%s…）。symlink 管理のため commit を忘れずに。"}\n' \
    "$dirty_count" "$files"
fi

exit 0
