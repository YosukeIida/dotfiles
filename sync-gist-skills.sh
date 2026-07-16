#!/usr/bin/env bash
# k16shikano の gist 由来 skill（cognitive-rhythm-writing / japanese-tech-writing）を
# agents/skills/ に vendor するスクリプト。
#
# なぜ vendor か: この2 skillは cognitive-rhythm-writing が
# `../japanese-tech-writing/SKILL.md` を相対参照する依存関係を持つ。
# Nix (agent-skills-nix 等) で各 skill を個別の derivation として配備すると、
# シンボリックリンクを辿った後の物理的な `..` が正しい兄弟ディレクトリに
# 戻らず相対参照が壊れる（実測で確認済み）。git 管理された実ディレクトリを
# postActivation の _link で1回だけ symlink する方式なら、`..` は正しく
# git checkout 内の兄弟ディレクトリに戻るため問題が起きない。
#
# 更新手順:
#   1. 下記の REV_* を更新したい gist の最新 commit hash に書き換える
#   2. ./sync-gist-skills.sh を実行
#   3. git diff で内容を目視確認（外部コンテンツなので必須）
#   4. commit
#
# 更新確認のみ（変更はしない）:
#   ./sync-gist-skills.sh --check

set -euo pipefail

REV_COGNITIVE_RHYTHM="a3b1e26beced71d582e13314fb6f5b179b023c76"
REV_JAPANESE_TECH_WRITING="209db7d6d19bc4727139844c0e8d786542e9ff68"

GIST_COGNITIVE_RHYTHM="https://gist.github.com/k16shikano/eb2929f13ed19c97188393d297be8432"
GIST_JAPANESE_TECH_WRITING="https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d"

DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agents/skills"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

check_mode=0
if [ "${1:-}" = "--check" ]; then
  check_mode=1
fi

sync_one() {
  local name="$1" url="$2" rev="$3"
  local clone_dir="$WORK/$name"

  git clone -q "$url" "$clone_dir"

  if [ "$check_mode" -eq 1 ]; then
    local head
    head="$(git -C "$clone_dir" rev-parse HEAD)"
    if [ "$head" = "$rev" ]; then
      echo "$name: up to date (pinned $rev)"
    else
      local behind
      behind="$(git -C "$clone_dir" rev-list --count "$rev..$head" 2>/dev/null || echo "?")"
      echo "$name: $behind new commit(s) since pinned $rev (HEAD=$head)"
    fi
    return
  fi

  git -C "$clone_dir" checkout -q "$rev"
  rm -rf "$DEST/$name"
  mkdir -p "$DEST/$name"
  cp "$clone_dir/SKILL.md" "$DEST/$name/SKILL.md"
  echo "synced $name @ $rev -> $DEST/$name/SKILL.md"
}

sync_one "cognitive-rhythm-writing" "$GIST_COGNITIVE_RHYTHM" "$REV_COGNITIVE_RHYTHM"
sync_one "japanese-tech-writing" "$GIST_JAPANESE_TECH_WRITING" "$REV_JAPANESE_TECH_WRITING"
