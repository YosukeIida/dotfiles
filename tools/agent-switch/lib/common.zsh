# agent-switch 共通ヘルパ（claude.zsh / codex.zsh より先に source される）

# プロファイル・マーカー。agent-switch が作成した dir にのみ置かれる。
#
# prefix 方式（~/.claude-<name> / ~/.codex-<name>）は agent-switch と無関係な既存
# ディレクトリに偶然合致しうる（実例: 別ツールの ~/.claude-science）。dir の存在だけで
# 判定すると、そこへ CLAUDE_CONFIG_DIR / CODEX_HOME を向けて他ツールのデータを
# 汚染する。マーカーの有無で「agent-switch が管理している dir か」を明示的に区別する。
#
# 列挙側は bin/agsw-list-profiles が同じ規則を実装している。
# マーカー名を変更する場合は両方を直すこと。
typeset -g _AGSW_MARKER=".agsw-profile"

# _agsw_require_profile <dir> <setup-command-hint>
#   <dir> が agent-switch のプロファイルなら 0。そうでなければ理由を stderr に出して 1。
_agsw_require_profile() {
  local dir="$1" hint="$2"

  if [[ ! -d "$dir" ]]; then
    echo "Error: $dir not found. Run: $hint" >&2
    return 1
  fi

  if [[ ! -f "$dir/$_AGSW_MARKER" ]]; then
    echo "Error: $dir は agent-switch のプロファイルではありません（$_AGSW_MARKER が無い）。" >&2
    echo "  prefix（~/.claude- / ~/.codex-）は無関係な別アプリのデータにも偶然合致します。" >&2
    echo "  実例: ~/.claude-science は Claude Science アプリのデータディレクトリ。" >&2
    echo "  まず中身を確認してください。agent-switch のプロファイルだと確認できた場合のみ:" >&2
    echo "    $hint --claim" >&2
    return 1
  fi

  return 0
}

# _agsw_list_profiles <prefix>
#   マーカー付きプロファイル名を1行1件で出力する。ヘルパ不在なら無出力・0。
_agsw_list_profiles() {
  [[ -x "$_AGSW_DIR/bin/agsw-list-profiles" ]] || return 0
  "$_AGSW_DIR/bin/agsw-list-profiles" "$1"
}
