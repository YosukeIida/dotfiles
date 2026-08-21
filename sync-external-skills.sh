#!/usr/bin/env bash
# 外部の公開ソース由来 skill を agents/skills/ に vendor するスクリプト。
# gist だけでなく通常の GitHub repo 由来も扱うため sync-external-skills.sh という
# 名前にしている（旧名 sync-gist-skills.sh。2026-08 に repo 由来の比重が増えたため改名）。
#
# 扱う2系統:
#   1. gist 由来（cognitive-rhythm-writing / japanese-tech-writing）
#      → clone して SKILL.md をコピーする。REV_* で pin。
#   2. repo 内の SKILL.md 由来（herdr, browser-harness, writing-quotation,
#      grilling, domain-modeling, grill-with-docs, gws-multi-account）
#      → gh api で1ファイルだけ取得し、ローカルのパッチと vendor-* metadata を注入する。
#        gh skill install は使えない: 発見に `<name>/SKILL.md` のディレクトリ構造を要求し、
#        リポジトリ直下の裸の SKILL.md を認識しない（`gh skill preview` が
#        "no standard skills found" を返す。2026-07 実測）。
#        writing-quotation（mathbullet/skills）は marketplace 構造の repo だが、
#        `/plugin install` は使わない（~/.claude の mutable state に入り、
#        nix/dotfiles の宣言的管理から外れるため。判断は dotfiles/CLAUDE.md 参照）。
#        domain-modeling は SKILL.md から ADR-FORMAT.md / CONTEXT-FORMAT.md を相対参照
#        するため、この2ファイルも extra_files で同じ rev から一緒に vendor する。
#        gws-multi-account（indentcorp/gws-multi-account）も同じ理由:
#        本体は Bun/npm でビルドする Claude Code plugin（PreToolUse hook が
#        `node hooks/hook.js` を実行）だが、`/plugin install` は上記と同じ理由に加えて
#        node をグローバル PATH に常駐させる必要が生じ nodeless-policy と衝突するため
#        使わない。hook.js は依存を全部バンドルした単一ファイルなので、skill 本体
#        （SKILL.md + references/auth-login.md）と一緒に hooks/hook.js だけを
#        extra_files で vendor し、PreToolUse からは GWS_MULTI_ACCOUNT_NODE
#        （nix pin 済み node、nix/home/packages.nix）経由で実行する。
#        extra_files はディレクトリ構造を持つため（references/・hooks/）、
#        従来の「basename だけコピー」ではなく `repo相対パス:vendor先相対パス`
#        の形式でも指定できるよう sync_repo_file を拡張してある。
#
# なぜ vendor か: cognitive-rhythm-writing が
# `../japanese-tech-writing/SKILL.md` を相対参照する依存関係を持つ。
# Nix (agent-skills-nix 等) で各 skill を個別の derivation として配備すると、
# シンボリックリンクを辿った後の物理的な `..` が正しい兄弟ディレクトリに
# 戻らず相対参照が壊れる（実測で確認済み）。git 管理された実ディレクトリを
# postActivation の _link で1回だけ symlink する方式なら、`..` は正しく
# git checkout 内の兄弟ディレクトリに戻るため問題が起きない。
#
# 更新手順:
#   1. 下記の REV_* を更新したい gist/commit の最新 hash に書き換える
#   2. ./sync-external-skills.sh を実行
#   3. git diff で内容を目視確認（外部コンテンツなので必須）
#   4. commit
#
# 更新確認のみ（変更はしない）:
#   ./sync-external-skills.sh --check

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
# 2026-08 に upstream が SKILL.md を repo 直下から skills/herdr/SKILL.md へ移動
# （gh skill install が要求する <name>/SKILL.md 構造に合わせた再編、と見られる）。
HERDR_PATH="skills/herdr/SKILL.md"
HERDR_REV="9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c"

# writing-quotation: 引用ブロックの書式規約（Bash等のツール呼び出しを一切含まない
# 純粋な書式ガイドなので allowed-tools は付けない）。
WRITING_QUOTATION_REPO="mathbullet/skills"
WRITING_QUOTATION_PATH="plugins/writing-quotation/skills/writing-quotation/SKILL.md"
WRITING_QUOTATION_REV="c1814f2850c2e18624a15206bc8b18b24cf3d3e8"

# browser-use は 2026-07 に browser-harness（コマンド名も変更、AXツリー優先の
# 新設計）へ実質移行した。browser-use/browser-use 本体には SKILL.md が無いため
# （404 実測）、こちらだけを vendor する。
BROWSER_HARNESS_REPO="browser-use/browser-harness"
BROWSER_HARNESS_PATH="SKILL.md"
BROWSER_HARNESS_REV="2c3a69ad09fd7b6f369f32d3eb5c5ad44d7832ed"

# grill-me系（mattpocock/skills）。3 skill は依存関係がある:
#   grill-with-docs → /grilling + /domain-modeling に一行委譲
# 各 REV は該当 SKILL.md を最後に変更した commit（HEAD ではない。理由は上の HERDR と同じ）。

# grilling: interview の共通原始単位。upstream に disable-model-invocation は無く、
# 単体でも自動発動する。パッチ不要。
GRILLING_REPO="mattpocock/skills"
GRILLING_PATH="skills/productivity/grilling/SKILL.md"
GRILLING_REV="85f83d3fde1d3a90d5c9a657f6998c79a6c37308"

# domain-modeling: CONTEXT.md / ADR の執筆規律。SKILL.md 本文が同ディレクトリの
# ADR-FORMAT.md / CONTEXT-FORMAT.md を相対参照するため、この2ファイルも一緒に vendor
# しないと壊れる（agents/openai.yaml は別インターフェース向けの metadata なので不要）。
DOMAIN_MODELING_REPO="mattpocock/skills"
DOMAIN_MODELING_PATH="skills/engineering/domain-modeling/SKILL.md"
DOMAIN_MODELING_EXTRA="skills/engineering/domain-modeling/ADR-FORMAT.md skills/engineering/domain-modeling/CONTEXT-FORMAT.md"
DOMAIN_MODELING_REV="321658273cb1d20b76026717d027d505790106d4"

# grill-with-docs: 上記2つへの一行委譲オーケストレータ。upstream の
# `disable-model-invocation: true` を strip_pattern で落とし、herdr と同様に
# 自作 skill 全体の方針（disable-model-invocation を使わず自動発動を保つ）に揃える。
GRILL_WITH_DOCS_REPO="mattpocock/skills"
GRILL_WITH_DOCS_PATH="skills/engineering/grill-with-docs/SKILL.md"
GRILL_WITH_DOCS_REV="447ca70872026d5b79d6073a546dac082117fed7"

# gws-multi-account: `gws`（Google Workspace CLI）のマルチアカウント運用規約。
# SKILL.md が references/auth-login.md を相対参照し、PreToolUse hook 本体は
# hooks/hook.js（依存バンドル済みの単一ファイル）。3ファイルとも同じ rev で揃える
# 必要があるため、その時点の repo HEAD で pin する（3ファイルそれぞれの
# 「最後にそのファイルを触ったcommit」は互いに異なる別々の値だが、HEAD の
# 時点でどれも取り込み済みなので内容としては最新）。
# 注意: agent-skills-outdated の scan_vendor_pins は「pin が各パスの最新
# 変更commitを祖先として含むか」を compare API で判定する（単純な文字列一致
# ではない）。これは1つの pin で複数ファイルを束ねる vendor（このskillのように
# 各ファイルの最終変更commitがpinと一致しない）に対応するため。
# hooks/hook.js・references/auth-login.md だけが更新されて SKILL.md に触れられない
# ケースも、vendor-extra-paths metadata（sync_repo_file が extra_files から自動生成）
# 経由で同じ scan_vendor_pins が検知する（nix/hosts/darwin/yosuke/common.nix）。
GWS_MULTI_ACCOUNT_REPO="indentcorp/gws-multi-account"
GWS_MULTI_ACCOUNT_PATH="skills/gws-multi-account/SKILL.md"
GWS_MULTI_ACCOUNT_EXTRA="skills/gws-multi-account/references/auth-login.md:references/auth-login.md hooks/hook.js:hooks/hook.js"
GWS_MULTI_ACCOUNT_REV="e73dcbb12e581c51a259e0d5bf827b684faf997a"

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
# $5 = allowed-tools の値。省略・空文字なら付けない（Bash等のツール呼び出しを
# 持たない純粋な書式・文章規約 skill 向け）。$6 = description の上書き行
# （frontmatter の `description: ...` 1行そのもの）。省略時は description を上書きしない。
# $7 = 削除したい行の正規表現パターン（grep -E -v にそのまま渡す）。upstream の
# disable-model-invocation: true のような、自動発動を妨げるフラグを落とすときに使う。
# $8 = SKILL.md 以外に一緒に vendor したい追加ファイルの repo 相対パス（空白区切り、
# 複数可）。SKILL.md から相対参照される補助ファイル（*-FORMAT.md 等）を持つ skill 用。
# 各エントリは `repo相対パス` か `repo相対パス:vendor先相対パス`（コロン区切り）。
# コロン省略時は vendor 先は basename 直下（従来通り、ADR-FORMAT.md 等サブディレクトリを
# 持たない skill 向け）。コロンありは vendor 先にサブディレクトリを再現する
# （gws-multi-account の references/・hooks/ のように、skill 内の相対参照や
# hook 内に埋め込まれたパス文字列がそのまま通るようにするため）。
sync_repo_file() {
  local name="$1" repo="$2" path="$3" rev="$4" allowed_tools="${5:-}" desc_override="${6:-}" \
    strip_pattern="${7:-}" extra_files="${8:-}"
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
  if [ -n "$allowed_tools" ] && ! grep -q '^allowed-tools:' "$raw"; then
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

  # --- ローカルパッチ3: 指定パターンに一致する行を削除 -----------------------
  # 例: grill-with-docs の `disable-model-invocation: true` を落として、
  # 自作 skill 全体の方針（自動発動を維持する）に揃える。
  if [ -n "$strip_pattern" ]; then
    grep -v -E "$strip_pattern" "$raw" >"$raw.patched" && mv "$raw.patched" "$raw"
  fi

  # extra_files の src 部分（repo相対パス）だけを空白区切りで集める。
  # vendor-extra-paths metadata に使う（agent-skills-outdated が SKILL.md 以外の
  # vendor 済みファイルの更新も検知できるようにするため）。
  local extra_srcs="" f_probe
  for f_probe in $extra_files; do
    case "$f_probe" in
      *:*) extra_srcs="$extra_srcs ${f_probe%%:*}" ;;
      *) extra_srcs="$extra_srcs $f_probe" ;;
    esac
  done
  extra_srcs="${extra_srcs# }"

  # --- vendor-* metadata を注入（agent-skills-outdated が読む） --------------
  # github-* にしないのは、gh skill がリポジトリルートの tree を見て
  # upstream の全 commit を「更新あり」と誤検知するのを避けるため。
  # vendor-extra-paths は extra_files の src を同じ vendor-commit 基準で
  # 追加チェックできるようにするための拡張（scan_vendor_pins 側で読む）。
  awk -v repo="$repo" -v path="$path" -v rev="$rev" -v extra="$extra_srcs" '
    NR == 1 && $0 == "---" { print; infm = 1; next }
    infm && $0 == "---" {
      print "metadata:"
      print "    vendor-repo: " repo
      print "    vendor-path: " path
      print "    vendor-commit: " rev
      if (extra != "") print "    vendor-extra-paths: " extra
      print
      infm = 0
      next
    }
    { print }
  ' "$raw" >"$raw.patched" && mv "$raw.patched" "$raw"

  # extra_files: SKILL.md が相対参照する補助ファイルを同じ rev から取得しておく。
  # `src:dest` 形式ならサブディレクトリ構造を vendor 先に再現し、`src` 単独なら
  # 従来通り basename 直下に置く。
  local -a extra_dests=()
  local f src dest_rel safe_name
  for f in $extra_files; do
    case "$f" in
      *:*)
        src="${f%%:*}"
        dest_rel="${f#*:}"
        ;;
      *)
        src="$f"
        dest_rel="$(basename "$f")"
        ;;
    esac
    # $WORK 側の一時保存先はパスのまま使うとサブディレクトリ衝突するため、
    # / を _ に潰した安全な一時ファイル名にする。
    safe_name="$(printf '%s' "$dest_rel" | tr '/' '_')"
    gh api "repos/$repo/contents/$src?ref=$rev" \
      -H "Accept: application/vnd.github.raw" >"$WORK/$name-$safe_name"
    extra_dests+=("$dest_rel")
  done

  # 変数が空でも rm -rf / にならないよう :? で防御する
  rm -rf "${DEST:?}/${name:?}"
  mkdir -p "$DEST/$name"
  cp "$raw" "$dest"
  for dest_rel in "${extra_dests[@]+"${extra_dests[@]}"}"; do
    safe_name="$(printf '%s' "$dest_rel" | tr '/' '_')"
    mkdir -p "$DEST/$name/$(dirname "$dest_rel")"
    cp "$WORK/$name-$safe_name" "$DEST/$name/$dest_rel"
  done
  echo "synced $name @ $rev -> $dest"
}

sync_one "cognitive-rhythm-writing" "$GIST_COGNITIVE_RHYTHM" "$REV_COGNITIVE_RHYTHM"
sync_one "japanese-tech-writing" "$GIST_JAPANESE_TECH_WRITING" "$REV_JAPANESE_TECH_WRITING"
sync_repo_file "herdr" "$HERDR_REPO" "$HERDR_PATH" "$HERDR_REV" \
  "Bash(herdr:*), Bash(python3:*)" \
  'description: "Control herdr from inside it. Manage workspaces and tabs, split panes, spawn agents, read output, and wait for state changes — all via CLI commands that talk to the running herdr instance over a local unix socket. Use when running inside herdr (HERDR_ENV=1)."'
sync_repo_file "browser-harness" "$BROWSER_HARNESS_REPO" "$BROWSER_HARNESS_PATH" "$BROWSER_HARNESS_REV" \
  "Bash(browser-harness:*)"
sync_repo_file "writing-quotation" "$WRITING_QUOTATION_REPO" "$WRITING_QUOTATION_PATH" "$WRITING_QUOTATION_REV"
sync_repo_file "grilling" "$GRILLING_REPO" "$GRILLING_PATH" "$GRILLING_REV"
sync_repo_file "domain-modeling" "$DOMAIN_MODELING_REPO" "$DOMAIN_MODELING_PATH" "$DOMAIN_MODELING_REV" \
  "" "" "" "$DOMAIN_MODELING_EXTRA"
sync_repo_file "grill-with-docs" "$GRILL_WITH_DOCS_REPO" "$GRILL_WITH_DOCS_PATH" "$GRILL_WITH_DOCS_REV" \
  "" "" '^disable-model-invocation:'
sync_repo_file "gws-multi-account" "$GWS_MULTI_ACCOUNT_REPO" "$GWS_MULTI_ACCOUNT_PATH" "$GWS_MULTI_ACCOUNT_REV" \
  "" "" "" "$GWS_MULTI_ACCOUNT_EXTRA"

# ローカルパッチ: upstream の SKILL.md は accounts.json のマージに裸の `node -e` を
# 使い、「Claude Code や opencode を動かすマシンには必ず node がある」という前提で
# 書かれている。この環境には nodeless-policy により裸の node が PATH に無いため、
# nix pin 済みの node を指す $GWS_MULTI_ACCOUNT_NODE（nix/home/packages.nix）
# 経由に差し替える。sync_repo_file の汎用パッチ機構（frontmatter 差し替え前提）では
# 表現しづらい複数行置換なので、専用関数として最後に適用する。
# 対象は bash/zsh の行継続（`\` の直後）に続く `node -e "` の2箇所のみ
# （PowerShell 例のブロックは `$env:` 変数参照の作法が異なるため触らない）。
patch_gws_multi_account_node_path() {
  local f="$DEST/gws-multi-account/SKILL.md"
  [ -f "$f" ] || return 0
  perl -0777 -pi -e '
    s/\\\n(\s*)node -e "/\\\n$1"\$GWS_MULTI_ACCOUNT_NODE" -e "/g;
    s/Use Node for cross-platform JSON merging — no `jq` dependency\. Node is guaranteed present on any machine running Claude Code or opencode\./Use "\$GWS_MULTI_ACCOUNT_NODE" (a nix-pinned Node.js binary) for cross-platform JSON merging — no `jq` dependency. There is no bare `node` on PATH in this environment by design; see the dotfiles nodeless policy./g;
  ' "$f"
}
if [ "$check_mode" -eq 0 ]; then
  patch_gws_multi_account_node_path
fi
