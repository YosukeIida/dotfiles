#!/usr/bin/env bash
# setup-claude-account と setup-codex-account が共有する安全ロジック。
#
# 両スクリプトが独立実装していた「未管理dirの取り込みガード」「symlink衝突検査」
# 「マーカー付与」は、認証方式（Keychain vs ファイル）と無関係な同一の安全不変条件
# であり、過去のデータ破壊事故（実ファイルをsymlinkで潰す・迷子リンク化）への
# 防壁を別々に保守するリスクの方が大きい（2026-08-04 codex-pr-review 指摘で共有化）。
#
# このファイルは `source` される前提（実行可能ファイルではない）。呼び出し側が
# 既に `set -euo pipefail` 済みであることを前提とする。

AGSW_MARKER=".agsw-profile"

# agsw_require_claimable <dir> <name> <claim> <hint-command-prefix>
#   <dir> が「マーカー無し・空でない」既存ディレクトリなら、<claim> が 1 でない限り
#   案内を出して exit 1 する。無関係な別アプリのデータを誤って取り込む事故
#   （実例: ~/.claude-science は Claude Science アプリのデータ）を防ぐガード。
#   <hint-command-prefix> には呼び出し元スクリプトと name まで（例: "$0 $NAME"）を渡す。
agsw_require_claimable() {
  local dir="$1" name="$2" claim="$3" hint="$4"

  [[ -d "$dir" ]] || return 0
  [[ -f "$dir/$AGSW_MARKER" ]] && return 0
  [[ -n "$(ls -A "$dir" 2>/dev/null)" ]] || return 0

  if [[ "$claim" != 1 ]]; then
    {
      echo "Error: $dir は既に存在し、agent-switch の管理下ではありません（$AGSW_MARKER が無い）。"
      echo "  中身:"
      # set -e + pipefail 下で head が先に終了すると ls が SIGPIPE で死に、
      # 案内の残りが出ないまま exit 141 になるため、パイプライン全体を保護する。
      { ls -A "$dir" 2>/dev/null | head -8 | sed 's/^/    /'; } || true
      [[ "$(ls -A "$dir" 2>/dev/null | wc -l)" -gt 8 ]] && echo "    ..."
      echo "  別アプリのデータディレクトリでないことを確認してください。"
      echo "  agent-switch のプロファイルとして取り込むなら:"
      echo "    $hint --claim"
    } >&2
    exit 1
  fi
  echo "[--claim] 既存ディレクトリを agent-switch のプロファイルとして取り込みます"
}

# agsw_check_link_conflicts <dir> <item>...
#   共有 symlink を張る先（<dir>/<item>）に実ファイル・実ディレクトリがあれば、
#   全項目をまとめて検査したうえで案内を出して exit 1 する（1項目見つかった時点で
#   即終了すると、他の衝突が案内から漏れるため全件集めてから報告する）。
#
#   呼び出し側は「実際にリンクする item」だけを渡すこと。リンク元の存在判定は
#   ここでは行わない（以前は <src>:<item> 形式で受けて内部判定していたが、
#   (a) ASSETS_DIR 等のパスに ':' を含むと壊れる (b) 呼び出し側の実リンク処理と
#   判定条件が食い違う可能性がある、という2つの問題があった。Claude の
#   ASSET_LINKS/Codex の LINKED_ITEMS は `-e` のみ、Claude の SHARED_FROM_BASE は
#   `-e || -L` と、リンク元の存在条件が呼び出し側ごとに異なるため、判定は
#   呼び出し側が自分のリンク処理と同じ条件でフィルタしてから item 名だけを渡す
#   設計にした。2026-08-04 codex-pr-review 指摘で修正）。
#   同じ <item> が複数回渡されても案内には1回だけ出す（例: CLAUDE.md が
#   assets 由来と共有base由来の両方にあるケース）。
#
#   ln -sfn は実ファイルを問答無用で置き換え、実ディレクトリの中に迷子リンクを
#   作って半壊させるため（2026-07-28 実測）、実際に変更を始める前に必ず呼ぶこと。
agsw_check_link_conflicts() {
  local dir="$1"; shift
  local conflicts="" item dst

  [[ -d "$dir" ]] || return 0

  for item in "$@"; do
    dst="$dir/$item"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
      case " $conflicts " in *" $item "*) ;; *) conflicts="$conflicts $item" ;; esac
    fi
  done

  [[ -n "$conflicts" ]] || return 0

  {
    echo "Error: $dir に共有 symlink と衝突する実体があります:$conflicts"
    echo "  symlink に張り替えると元の内容が失われます（ディレクトリの場合は中に迷子の"
    echo "  リンクができて半壊します）。何も変更していません。"
    echo "  内容が不要／退避済みなら、次のように退けてから再実行してください:"
    for item in $conflicts; do
      echo "    mv \"$dir/$item\" \"$dir/$item.bak\""
    done
  } >&2
  exit 1
}

# agsw_mark_profile <dir>
#   プロファイル・マーカーを置く。正規化（symlink張り）が完了してから呼ぶこと
#   （先に呼ぶと、途中で失敗した半端な dir が「管理下」と誤認される）。
agsw_mark_profile() {
  touch "$1/$AGSW_MARKER"
}
