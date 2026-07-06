# cx — Codex CLI/App アカウント切り替え
#
# ターミナルは常に明示的なアカウント home を使う想定（デフォルト export は
# このプラグインではなく利用者の zshenv/zshrc 側で行う — README 参照）。
# CODEX_HOME 未設定のプロセス（Dock から起動した Codex App・launchd 等）は
# ~/.codex を見るため、そちらは cx app で切り替える。
#
# cx                 → 現在状態表示（shell / App / 起動中デーモン）
# cx <name>          → このターミナルの CODEX_HOME を切替（他ターミナルに影響しない）
# cx app <name>      → Codex App 用（~/.codex/auth.json symlink）を切替
cx() {
  local sub="${1:-}"
  case "$sub" in
    "")
      cx_status
      ;;
    app)
      local name="${2:-}"
      [[ -n "$name" ]] || { echo "usage: cx app <name>" >&2; return 1; }
      local dir="${AGSW_CODEX_HOME_PREFIX:-$HOME/.codex-}$name"
      if [[ ! -d "$dir" ]]; then
        echo "Error: $dir not found. Run: $_AGSW_DIR/bin/setup-codex-account $name" >&2
        return 1
      fi
      local app_auth="${AGSW_CODEX_APP_AUTH:-$HOME/.codex/auth.json}"
      # 実ファイル（非symlink）を ln -sf で潰すとログイン中の認証情報を破壊するため拒否
      if [[ -e "$app_auth" && ! -L "$app_auth" ]]; then
        echo "Error: $app_auth is a real file, not a symlink. Overwriting it would destroy" >&2
        echo "the logged-in credentials. Run first: $_AGSW_DIR/bin/setup-codex-account migrate <name>" >&2
        return 1
      fi
      ln -sf "$dir/auth.json" "$app_auth"
      echo "(Codex App は再起動後に反映。確実に切り替えるなら: pkill -f 'codex app-server')"
      cx_status
      ;;
    *)
      local dir="${AGSW_CODEX_HOME_PREFIX:-$HOME/.codex-}$sub"
      if [[ ! -d "$dir" ]]; then
        echo "Error: $dir not found. Run: $_AGSW_DIR/bin/setup-codex-account $sub" >&2
        return 1
      fi
      export CODEX_HOME="$dir"
      cx_status
      ;;
  esac
}

cx_status() {
  local shell_home="${CODEX_HOME:-$HOME/.codex}"
  local app_auth="${AGSW_CODEX_APP_AUTH:-$HOME/.codex/auth.json}"
  local app_target
  app_target="$(readlink "$app_auth" 2>/dev/null || echo "(not a symlink)")"

  echo "shell CODEX_HOME : $shell_home"
  echo "app auth.json -> : $app_target"

  # app-server デーモンは起動時の CODEX_HOME の auth をキャッシュし、TUI が
  # CODEX_HOME をまたいで Remote 接続することがある（/statusのRemote行で確認可）。
  # 現在の shell と実体 auth が異なるデーモンがいたら警告する。
  # ps の環境変数表示は macOS (BSD ps) 前提のため、他OSではスキップする。
  [[ "$OSTYPE" == darwin* ]] || return 0

  local shell_auth_path="$shell_home/auth.json"
  local shell_auth="${shell_auth_path:A}"
  local pid line dhome daemon_auth_path daemon_auth mismatch=""
  for pid in $(pgrep -f 'codex app-server' 2>/dev/null); do
    line="$(ps eww -p "$pid" -o command= 2>/dev/null | tr ' ' '\n' | grep '^CODEX_HOME=' | head -1)"
    dhome="${line#CODEX_HOME=}"
    [[ -n "$dhome" ]] || dhome="$HOME/.codex"
    daemon_auth_path="$dhome/auth.json"
    daemon_auth="${daemon_auth_path:A}"
    echo "daemon PID $pid  : CODEX_HOME=$dhome"
    [[ "$daemon_auth" != "$shell_auth" ]] && mismatch=1
  done
  if [[ -n "$mismatch" ]]; then
    echo "warning: 現在のshellと異なるアカウントのapp-serverデーモンが起動中。TUIがそちらにRemote接続すると別アカウントで動くことがある。確実に切り替えるには: pkill -f 'codex app-server'"
  fi
}
