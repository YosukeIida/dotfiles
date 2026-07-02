# cc — Claude Code アカウント・モード切り替え
#
# cc                   → 現在状態表示
# cc sub               → subscription モードに切り替え
# cc api               → API モードに切り替え
# cc sub 1 / cc sub 2  → アカウント N + subscription
# cc api 1 / cc api 2  → アカウント N + API
# cc 1 / cc 2          → 後方互換（subscription 固定）
cc() {
  local arg1="${1:-}" arg2="${2:-}"
  local account="" mode=""

  if [[ -z "$arg1" ]]; then
    _cc_status; return 0
  fi

  for arg in "$arg1" "$arg2"; do
    [[ -z "$arg" ]] && continue
    case "$arg" in
      api|sub|subscription) mode="$arg" ;;
      [1-9]*)               account="$arg" ;;
      *)
        echo "usage: cc [sub|api] [N]" >&2
        return 1 ;;
    esac
  done

  # 後方互換: cc N のみ → subscription を自動設定
  if [[ -n "$account" && -z "$mode" ]]; then
    mode="sub"
  fi

  # アカウント切り替え
  if [[ -n "$account" ]]; then
    if [[ "$account" == "1" ]]; then
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
  if [[ -n "$mode" ]]; then
    local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local dst="$config_dir/settings.json"
    local src
    case "$mode" in
      api)              src="$config_dir/settings.api.json" ;;
      sub|subscription) src="$config_dir/settings.subscription.json" ;;
    esac
    if [[ ! -e "$src" ]]; then
      echo "Error: missing $src" >&2
      return 1
    fi
    ln -sf "$src" "$dst"
  fi

  _cc_status
}

_cc_status() {
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local num="1"
  [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && num="${CLAUDE_CONFIG_DIR##*-}"

  local mode="subscription"
  local resolved
  resolved=$(readlink "$config_dir/settings.json" 2>/dev/null || echo "")
  [[ "$resolved" == *settings.api.json ]] && mode="api"

  local email="(not logged in)" display_name="" org_name=""
  local json="$config_dir/.claude.json"
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

  echo "account : $num  ($config_dir)"
  echo "mode    : $mode"
  echo "email   : $email${display_name:+  ($display_name)}"
  echo "org     : ${org_name:-(unknown)}"
}
