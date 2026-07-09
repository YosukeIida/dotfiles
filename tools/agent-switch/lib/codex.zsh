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

  # 自分の CODEX_HOME 用 managed daemon が動いていれば情報表示のみ行う。
  # 他ツール・他プロジェクトが起動した無関係な codex app-server プロセス
  # （$CODEX_HOME ごとに control socket が分離されているため接続対象にならない）
  # を pgrep で拾って警告していたのは誤検知だったため削除済み（2026-07-09）。
  local pid_file="$shell_home/app-server-daemon/app-server.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(<"$pid_file")"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && echo "managed daemon   : PID $pid (this CODEX_HOME)"
  fi

  # プロファイル間の symlink 漏れ検出＆自動修復（新しい Codex が追加したトップレベル項目の共有漏れ）
  [[ -x "$_AGSW_DIR/bin/check-codex-drift" ]] && "$_AGSW_DIR/bin/check-codex-drift" --fix
}
