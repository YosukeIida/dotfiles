#!/usr/bin/env bash
# 外部の公開ソース由来 skill を agents/skills/ に vendor するスクリプト。
#
# 扱う2系統:
#   1. gist 由来（cognitive-rhythm-writing / japanese-tech-writing）
#      → clone して SKILL.md をコピーする。REV_* で pin。
#   2. repo 直下の SKILL.md 由来（herdr, browser-harness）
#      → gh api で1ファイルだけ取得し、ローカルのパッチと vendor-* metadata を注入する。
#        gh skill install は使えない: 発見に `<name>/SKILL.md` のディレクトリ構造を要求し、
#        リポジトリ直下の裸の SKILL.md を認識しない（`gh skill preview` が
#        "no standard skills found" を返す。2026-07 実測）。
#
# 名前が gist 限定に見えるがリネームしていないのは、
# nix/hosts/darwin/common/default.nix と CLAUDE.md の両方から参照されているため。
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
REV_JAPANESE_TECH_WRITING="c7189cdc9c2520be50418209834145bdf3a46e97"

GIST_COGNITIVE_RHYTHM="https://gist.github.com/k16shikano/eb2929f13ed19c97188393d297be8432"
GIST_JAPANESE_TECH_WRITING="https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d"

# repo 直下 SKILL.md 由来。SKILL.md を最後に変更した commit で pin する
# （リポジトリの HEAD ではない。活発な repo なので HEAD で pin すると無関係な
# commit で「更新あり」になる）。更新確認は agent-skills-outdated が
# vendor-* metadata を読んで行う。
HERDR_REPO="ogulcancelik/herdr"
HERDR_PATH="SKILL.md"
HERDR_REV="0f161fac287011b3e216383e2b8482f049fd6a7b"

# browser-use は 2026-07 に browser-harness（コマンド名も変更、AXツリー優先の
# 新設計）へ実質移行した。browser-use/browser-use 本体には SKILL.md が無いため
# （404 実測）、こちらだけを vendor する。
BROWSER_HARNESS_REPO="browser-use/browser-harness"
BROWSER_HARNESS_PATH="SKILL.md"
BROWSER_HARNESS_REV="4000dd16919360ea60c3329403061b15bb730b25"

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
  # 変数が空でも rm -rf / にならないよう :? で防御する
  rm -rf "${DEST:?}/${name:?}"
  mkdir -p "$DEST/$name"
  cp "$clone_dir/SKILL.md" "$DEST/$name/SKILL.md"
  echo "synced $name @ $rev -> $DEST/$name/SKILL.md"
}

# repo 直下の1ファイルを vendor する。gist と違い、ローカルで意図的に持つ差分
# （allowed-tools と、必要な skill だけ description）をここでパッチとして再適用し、
# 更新検知用の vendor-* metadata を注入する。手で編集しないこと（次回 sync で上書きされる）。
# $5 = allowed-tools の値。$6 = description の上書き行（frontmatter の
# `description: ...` 1行そのもの）。省略時は description を上書きしない。
sync_repo_file() {
  local name="$1" repo="$2" path="$3" rev="$4" allowed_tools="$5" desc_override="${6:-}"
  local dest="$DEST/$name/SKILL.md"

  if [ "$check_mode" -eq 1 ]; then
    # 更新確認は agent-skills-outdated が vendor-* を読んで行うのでそちらに委ねる。
    # ここで二重にAPIを叩かない。
    echo "$name: pinned $rev (更新確認は agent-skills-outdated が行う)"
    return
  fi

  local raw="$WORK/$name.md"
  gh api "repos/$repo/contents/$path?ref=$rev" \
    -H "Accept: application/vnd.github.raw" >"$raw"

  # --- ローカルパッチ1: allowed-tools を足す（upstream には無い） -------------
  # 権限プロンプトを最小限にするため。frontmatter の閉じ `---` の直前に挿入する。
  if ! grep -q '^allowed-tools:' "$raw"; then
    awk -v tools="$allowed_tools" '
      NR == 1 && $0 == "---" { print; infm = 1; next }
      infm && $0 == "---" {
        print "allowed-tools: " tools
        print
        infm = 0
        next
      }
      { print }
    ' "$raw" >"$raw.patched" && mv "$raw.patched" "$raw"
  fi

  # --- ローカルパッチ2: description を差し戻す（指定した skill のみ） ---------
  # herdr は upstream が 2026-07 に「Herdr を明示的に言及したときのみ使う」方向へ
  # 絞ったが、ここでは herdr 内にいれば自動発動する挙動を維持する（自作 skill
  # 全体の方針。disable-model-invocation を使わず発動を保つ、という判断に揃える）。
  if [ -n "$desc_override" ]; then
    if ! grep -q '^description: ' "$raw"; then
      echo "sync: $name の frontmatter に description 行が見つからない（upstream の形式が変わった？）" >&2
      exit 1
    fi
    awk -v repl="$desc_override" '
      !done_desc && /^description: / { print repl; done_desc = 1; next }
      { print }
    ' "$raw" >"$raw.patched" && mv "$raw.patched" "$raw"
  fi

  # --- vendor-* metadata を注入（agent-skills-outdated が読む） --------------
  # github-* にしないのは、gh skill がリポジトリルートの tree を見て
  # upstream の全 commit を「更新あり」と誤検知するのを避けるため。
  awk -v repo="$repo" -v path="$path" -v rev="$rev" '
    NR == 1 && $0 == "---" { print; infm = 1; next }
    infm && $0 == "---" {
      print "metadata:"
      print "    vendor-repo: " repo
      print "    vendor-path: " path
      print "    vendor-commit: " rev
      print
      infm = 0
      next
    }
    { print }
  ' "$raw" >"$raw.patched" && mv "$raw.patched" "$raw"

  # 変数が空でも rm -rf / にならないよう :? で防御する
  rm -rf "${DEST:?}/${name:?}"
  mkdir -p "$DEST/$name"
  cp "$raw" "$dest"
  echo "synced $name @ $rev -> $dest"
}

sync_one "cognitive-rhythm-writing" "$GIST_COGNITIVE_RHYTHM" "$REV_COGNITIVE_RHYTHM"
sync_one "japanese-tech-writing" "$GIST_JAPANESE_TECH_WRITING" "$REV_JAPANESE_TECH_WRITING"
sync_repo_file "herdr" "$HERDR_REPO" "$HERDR_PATH" "$HERDR_REV" \
  "Bash(herdr:*), Bash(python3:*)" \
  'description: "Control herdr from inside it. Manage workspaces and tabs, split panes, spawn agents, read output, and wait for state changes — all via CLI commands that talk to the running herdr instance over a local unix socket. Use when running inside herdr (HERDR_ENV=1)."'
sync_repo_file "browser-harness" "$BROWSER_HARNESS_REPO" "$BROWSER_HARNESS_PATH" "$BROWSER_HARNESS_REV" \
  "Bash(browser-harness:*)"
