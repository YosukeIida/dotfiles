# cc — Claude Code アカウント・モード切り替え
#
# Claude Code の認証トークンは macOS Keychain に CLAUDE_CONFIG_DIR ごとの
# エントリで保存される（実測: 認証の無い dir では "Not logged in" になる）。
# よってシェルの CLAUDE_CONFIG_DIR 切替 = 本物の認証分離。
# 一方 Codex と違いトークンはファイルではないため、symlink 差替による
# App/VS Code 拡張の切替（cx app 相当）は実装できない。App/拡張は常に
# デフォルト（CLAUDE_CONFIG_DIR 未設定 = ~/.claude + ~/.claude.json）の
# アカウントで動く。
#
# cc                     → 現在状態表示
# cc <name>              → アカウント切替（このシェルのみ）
#                          デフォルトアカウント名（AGSW_CLAUDE_DEFAULT_NAME、
#                          既定 labteam）は unset CLAUDE_CONFIG_DIR に相当し、
#                          App/拡張と同じ認証を使う
# cc sub / cc api        → 現在のアカウントのモード切替
# cc <name> sub|api      → アカウント + モード同時切替
cc() {
  local default_name="${AGSW_CLAUDE_DEFAULT_NAME:-labteam}"
  local arg account="" mode=""

  if [[ $# -eq 0 ]]; then
    cc_status; return 0
  fi

  for arg in "$@"; do
    case "$arg" in
      api|sub|subscription) mode="$arg" ;;
      1)
        echo "note: 番号制は廃止されました。'cc $default_name' を使ってください（今回はそのまま実行します）" >&2
        account="$default_name" ;;
      2)
        echo "note: 番号制は廃止されました。'cc personal' を使ってください（今回はそのまま実行します）" >&2
        account="personal" ;;
      *)
        account="$arg" ;;
    esac
  done

  # アカウント切り替え
  if [[ -n "$account" ]]; then
    if [[ "$account" == "$default_name" ]]; then
      # デフォルトアカウント = CLAUDE_CONFIG_DIR 未設定（App/拡張と同じ認証）。
      # export CLAUDE_CONFIG_DIR=~/.claude にすると Keychain エントリが
      # デフォルトと別になってしまうため、必ず unset にする。
      unset CLAUDE_CONFIG_DIR
    else
      local dir="${AGSW_CLAUDE_HOME_PREFIX:-$HOME/.claude-}$account"
      if [[ ! -d "$dir" ]]; then
        echo "Error: $dir not found. Run: $_AGSW_DIR/bin/setup-claude-account $account" >&2
        return 1
      fi
      export CLAUDE_CONFIG_DIR="$dir"
    fi
  fi

  # モード切り替え（ln -sf でシンボリックリンクのまま切り替え）
  # - api: settings.api.json（live + api-mode-overlay.json からの生成物）に差し替え
  # - sub: live の settings.json（settings.api.json の実体と同じディレクトリ）に戻す。
  #   サブスク専用ファイルは持たない（live そのものがサブスク設定）。
  if [[ -n "$mode" ]]; then
    local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
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
    name="${config_dir##*[-/]}"
    json="$config_dir/.claude.json"
  fi

  local mode="subscription"
  local resolved
  resolved=$(readlink "$config_dir/settings.json" 2>/dev/null || echo "")
  [[ "$resolved" == *settings.api.json ]] && mode="api"

  local email="(not logged in)" display_name="" org_name=""
  if [[ -f "$json" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      IFS=$'\t' read -r email display_name org_name <<< "$(python3 - "$json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    oa = d.get("oauthAccount") or {}
    print(oa.get("emailAddress","(unknown)"), oa.get("displayName",""), oa.get("organizationName",""), sep="\t")
except Exception:
    print("(parse error)", "", "", sep="\t")
PY
)"
    else
      email="(python3 not found — email/org display skipped)"
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
claude() {
  local _rt_bin="$HOME/.local/share/claude-runtime/bin"
  local _rt_fallback="$HOME/.local/share/claude-runtime/fallback"
  local _path="$PATH"
  [[ -d "$_rt_bin" ]] && _path="$_rt_bin:$_path"
  [[ -d "$_rt_fallback" ]] && _path="$_rt_fallback:$_path"
  PATH="$_path" command claude "$@"
}
