# cc — Claude Code アカウント・モード切り替え
#
# Claude Code の認証トークンは macOS Keychain に CLAUDE_CONFIG_DIR ごとの
# エントリで保存される（実測: 認証の無い dir では "Not logged in" になる）。
# よってシェルの CLAUDE_CONFIG_DIR 切替 = 本物の認証分離。
# 一方 Codex と違いトークンはファイルではないため、symlink 差替による
# App/VS Code 拡張の切替（cx app 相当）は同じ方法では作れない。現状 App/拡張は
# 常にデフォルト（CLAUDE_CONFIG_DIR 未設定 = ~/.claude + ~/.claude.json）の
# アカウントで動く。Keychain エントリの move による cc app の実現可否は検証中
# （README.md「cc app の検証」参照）。
#
# cc                     → 現在状態表示
# cc list                → プロファイル一覧（* が現在のアカウント）
# cc <name>              → アカウント切替（このシェルのみ）
#                          デフォルトアカウント名（AGSW_CLAUDE_DEFAULT_NAME、
#                          既定 labteam）は unset CLAUDE_CONFIG_DIR に相当し、
#                          App/拡張と同じ認証を使う
# cc sub / cc api        → 現在のアカウントのモード切替
# cc <name> sub|api      → アカウント + モード同時切替
#
# 引数は cx と同じ「1語目がサブコマンド」の位置固定で解釈する。以前は全引数を
# 走査するフラグ集合モデルだったため語順が無関係になり（cc api personal が
# cc personal api と同義）、その緩さが `cc app personal` を黙って
# `cc personal` として通す原因になった（2026-07-28）。
# アカウント（personal / labteam …）はサブスクの軸、api / sub はモードの軸で、
# API キーは1つしかないためモードはアカウントの次元ではない。
# したがって `cc api <name>` のような組み合わせは受け付けない。
cc() {
  local default_name="${AGSW_CLAUDE_DEFAULT_NAME:-labteam}"
  local account="" mode=""

  # 引数なしと「空文字を渡された」を区別する。${1:-} で一緒にすると
  # `cc "" personal` が状態表示になり personal が黙って捨てられる（2026-07-28 実測）。
  if (( $# == 0 )); then
    cc_status; return 0
  fi
  _agsw_reject_empty_args "cc [<name>] [api|sub] / cc list" "$@" || return 1

  case "$1" in
    list)
      (( $# == 1 )) || { echo "usage: cc list" >&2; return 1; }
      cc_list; return $?
      ;;
    app)
      # cx app に相当する機能は未実装。黙って `cc <name>` として動作すると
      # 「App も切り替わった」と誤解させる（2026-07-28 に実際に発生）。
      echo "Error: cc app は未実装です（cx app に相当する機能はありません）。" >&2
      echo "  Claude の認証は CLAUDE_CONFIG_DIR のパスハッシュで引く Keychain エントリで、" >&2
      echo "  Codex の auth.json のように symlink を差し替えられないためです。" >&2
      echo "  Desktop App / VS Code 拡張は常に非ハッシュの 'Claude Code-credentials'" >&2
      echo "  （= CLAUDE_CONFIG_DIR 未設定のアカウント）を読みます。" >&2
      echo "  実現方針と検証状況: $_AGSW_DIR/README.md の「cc app の検証」" >&2
      return 1
      ;;
    api|sub|subscription)
      # モードのみ切替（現在のアカウントに適用する）
      if (( $# != 1 )); then
        echo "Error: 'cc $1' はモード切替のみです。アカウントも変えるなら順序を逆にしてください:" >&2
        echo "    cc <name> $1" >&2
        return 1
      fi
      mode="$1"
      ;;
    *)
      account="$1"
      case "${2:-}" in
        "") ;;
        api|sub|subscription) mode="$2" ;;
        *)
          echo "Error: 2番目の引数はモード（api / sub）のみです: '$2'" >&2
          echo "  使い方: cc [<name>] [api|sub] / cc list" >&2
          return 1 ;;
      esac
      if (( $# > 2 )); then
        echo "Error: 引数が多すぎます。usage: cc [<name>] [api|sub]" >&2
        return 1
      fi
      ;;
  esac

  # アカウント切り替え
  if [[ -n "$account" ]]; then
    if [[ "$account" == "$default_name" ]]; then
      # デフォルトアカウント = CLAUDE_CONFIG_DIR 未設定（App/拡張と同じ認証）。
      # export CLAUDE_CONFIG_DIR=~/.claude にすると Keychain エントリが
      # デフォルトと別になってしまうため、必ず unset にする。
      unset CLAUDE_CONFIG_DIR
    else
      local dir="${AGSW_CLAUDE_HOME_PREFIX:-$HOME/.claude-}$account"
      _agsw_require_profile "$dir" "$_AGSW_DIR/bin/setup-claude-account $account" || return 1
      export CLAUDE_CONFIG_DIR="$dir"
    fi
  fi

  # モード切り替え（ln -sf でシンボリックリンクのまま切り替え）
  # - api: settings.api.json（live + api-mode-overlay.json からの生成物）に差し替え
  # - sub: live の settings.json（settings.api.json の実体と同じディレクトリ）に戻す。
  #   サブスク専用ファイルは持たない（live そのものがサブスク設定）。
  if [[ -n "$mode" ]]; then
    local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

    # モード切替は settings.json を書き換えるので、マーカー検査を通す。
    # cc <name> 経由なら上で検査済みだが、`cc api` 単体は外部から export された
    # CLAUDE_CONFIG_DIR にそのまま作用するため、ここを塞がないと未管理ディレクトリの
    # settings.json を symlink で置換できてしまう（2026-07-28 実測）。
    # 未設定（= デフォルトの ~/.claude）はマーカーを持たないので免除する。
    if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
      _agsw_require_profile "$config_dir" \
        "$_AGSW_DIR/bin/setup-claude-account ${config_dir##*/}" || return 1
    fi

    local dst="$config_dir/settings.json"
    local src
    case "$mode" in
      api) src="$config_dir/settings.api.json" ;;
      sub|subscription)
        local api_real
        api_real="$(readlink -f "$config_dir/settings.api.json" 2>/dev/null || true)"
        if [[ -z "$api_real" || "${api_real%/*}/settings.json" == "$dst" ]]; then
          echo "Error: live settings の場所を解決できません（$config_dir/settings.api.json を確認。darwin-switch で再生成できます）" >&2
          return 1
        fi
        src="${api_real%/*}/settings.json"
        ;;
    esac
    if [[ ! -e "$src" ]]; then
      echo "Error: missing $src" >&2
      return 1
    fi
    ln -sf "$src" "$dst"
  fi

  cc_status
}

# プロファイル一覧。* が現在このシェルで有効なアカウント。
# デフォルトアカウントは dir を持たない（CLAUDE_CONFIG_DIR 未設定に相当）ので、
# マーカー由来の列挙とは別に必ず先頭へ出す。
cc_list() {
  local default_name="${AGSW_CLAUDE_DEFAULT_NAME:-labteam}"
  local prefix="${AGSW_CLAUDE_HOME_PREFIX:-$HOME/.claude-}"
  local current name mark

  if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
    current="$default_name"
  else
    # 列挙側（agsw-list-profiles）は prefix をちょうど剥がすので、同じ規則で導出する。
    # `##*[-/]` だと「最後の - まで」を剥がすため、ハイフンを含む名前（lab-team → team）や
    # 末尾スラッシュ付きのパスで一覧のどの行とも一致しなくなる。
    current="${${CLAUDE_CONFIG_DIR%/}#$prefix}"
  fi

  mark=" "; [[ "$current" == "$default_name" ]] && mark="*"
  echo "$mark $default_name  (default — CLAUDE_CONFIG_DIR 未設定。App/拡張と同じ認証)"

  while IFS= read -r name; do
    [[ -n "$name" && "$name" != "$default_name" ]] || continue
    mark=" "; [[ "$current" == "$name" ]] && mark="*"
    echo "$mark $name"
  done < <(_agsw_list_profiles "$prefix")
}

cc_status() {
  local default_name="${AGSW_CLAUDE_DEFAULT_NAME:-labteam}"
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local name json

  if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
    name="$default_name (default)"
    # CLAUDE_CONFIG_DIR 未設定時の identity ファイルはホーム直下の ~/.claude.json
    # （~/.claude/.claude.json は旧位置で更新されない — mtime実測で確認済み）
    json="$HOME/.claude.json"
  else
    # cc_list と同じ規則で導出する（`##*[-/]` はハイフンを含む名前で誤る）
    name="${${config_dir%/}#${AGSW_CLAUDE_HOME_PREFIX:-$HOME/.claude-}}"
    json="$config_dir/.claude.json"
  fi

  local mode="subscription"
  local resolved
  resolved=$(readlink "$config_dir/settings.json" 2>/dev/null || echo "")
  [[ "$resolved" == *settings.api.json ]] && mode="api"

  local email="(not logged in)" display_name="" org_name=""
  if [[ -f "$json" ]]; then
    local identity_line
    if [[ -x "$_AGSW_DIR/bin/agsw-claude-identity" ]]; then
      if identity_line="$("$_AGSW_DIR/bin/agsw-claude-identity" "$json" 2>/dev/null)"; then
        IFS=$'\t' read -r email display_name org_name <<< "$identity_line"
      else
        # jq 不在 or JSON パース失敗を区別する（「未ログイン」と決めつけない）
        if ! command -v jq >/dev/null 2>&1; then
          email="(identity 不明 — jq が無いため判定できません)"
        else
          email="(identity 不明 — .claude.json の解析に失敗しました)"
        fi
      fi
    else
      email="(identity ヘルパが見つかりません)"
    fi
  fi

  echo "account : $name  ($config_dir)"
  echo "mode    : $mode"
  echo "email   : $email${display_name:+  ($display_name)}"
  echo "org     : ${org_name:-(unknown)}"
}

# claude() ラッパー: codex() と同じ設計。Claude Code 起動時だけ、
# プラグインhook用のnode と、pythonのsystem-python誤用ガードをPATHに注入する。
# 両方ともPATH先頭に追加する（/usr/binより必ず先に見つかる）。pythonガード自身が
# IN_NIX_SHELL の有無・pyproject.toml/uv.lock の有無を見て、devShellの本物のpythonに
# 委譲するか、uv run pythonに委譲するか、拒否するかを判定する
# （PATH位置だけでは devShell > guard > /usr/bin という優先順位を表現できないため）。
#
# あわせて claude-memory の registrar を起動前に走らせる。auto memory の行き先
# （autoMemoryDirectory）は **セッション開始時に読まれる** ため、SessionStart hook
# では間に合わない — hook が設定を書いても、そのセッションは旧位置に書いてしまい、
# 使い捨ての worktree では二度と回収できない。実装は private overlay にあり、
# 無いマシンでは単に skip する。
#
# 不変条件: registrar が何をしようと claude の起動は妨げない。失敗したときだけ
# CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 を付けて、旧位置に書かれるのを防ぐ。
claude() {
  local _rt_bin="$HOME/.local/share/claude-runtime/bin"
  local _rt_fallback="$HOME/.local/share/claude-runtime/fallback"
  local _path="$PATH"
  [[ -d "$_rt_bin" ]] && _path="$_rt_bin:$_path"
  [[ -d "$_rt_fallback" ]] && _path="$_rt_fallback:$_path"

  # registrar は **deadline 付きで**走らせる。非0 で失敗するだけなら fail-open できるが、
  # git rev-parse やファイルシステムが hang すると claude に到達しなくなり、
  # decision-003 の最重要不変条件（registrar は claude の起動を妨げない）が破れる。
  # timeout(1) は macOS に無いので、watchdog を背後に置いて wait する。
  local _cm="${CLAUDE_MEMORY_HOME:-$HOME/workspace/github.com/YosukeIida/dotfiles-private}/claude-memory.sh"
  local _cm_ok=1 _cm_pid
  if [[ -x "$_cm" ]]; then
    "$_cm" register "$PWD" >/dev/null 2>&1 &
    _cm_pid=$!
    { sleep "${CLAUDE_MEMORY_REGISTER_TIMEOUT:-5}"; kill -KILL "$_cm_pid" 2>/dev/null } &!
    wait "$_cm_pid" 2>/dev/null || _cm_ok=0
  fi

  if (( ! _cm_ok )); then
    PATH="$_path" CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 command claude "$@"
    return
  fi
  PATH="$_path" command claude "$@"
}
