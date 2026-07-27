# cx — Codex CLI/App アカウント切り替え
#
# ターミナルは常に明示的なアカウント home を使う想定（デフォルト export は
# このプラグインではなく利用者の zshenv/zshrc 側で行う — README 参照）。
# CODEX_HOME 未設定のプロセス（Dock から起動した Codex App・launchd 等）は
# ~/.codex を見るため、そちらは cx app で切り替える。
#
# cx                 → 現在状態表示（shell / App / 起動中デーモン）
# cx list            → プロファイル一覧（* が現在の CODEX_HOME）
# cx <name>          → このターミナルの CODEX_HOME を切替（他ターミナルに影響しない）
# cx app <name>      → Codex App 用（~/.codex/auth.json symlink）を切替
cx() {
  local sub="${1:-}"
  case "$sub" in
    "")
      cx_status
      ;;
    list)
      cx_list
      ;;
    app)
      local name="${2:-}"
      [[ -n "$name" ]] || { echo "usage: cx app <name>" >&2; return 1; }
      local dir="${AGSW_CODEX_HOME_PREFIX:-$HOME/.codex-}$name"
      _agsw_require_profile "$dir" "$_AGSW_DIR/bin/setup-codex-account $name" || return 1
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
      _agsw_require_profile "$dir" "$_AGSW_DIR/bin/setup-codex-account $sub" || return 1
      export CODEX_HOME="$dir"
      cx_status
      ;;
  esac
}

# プロファイル一覧。* が現在このシェルで有効な CODEX_HOME、@ が Codex App 側。
# Claude と違い Codex は「デフォルト = env var 未設定」という特別扱いを持たず、
# 全アカウントが dir を実体に持つので、列挙はマーカー由来のものだけで足りる。
cx_list() {
  local prefix="${AGSW_CODEX_HOME_PREFIX:-$HOME/.codex-}"
  local app_auth="${AGSW_CODEX_APP_AUTH:-$HOME/.codex/auth.json}"
  local current="${CODEX_HOME:-}"
  local app_target name dir mark

  app_target="$(readlink "$app_auth" 2>/dev/null || echo "")"

  # CODEX_HOME 未設定のシェルは共有の ~/.codex を直接使う。Claude と違い Codex には
  # 「デフォルトアカウント」の概念が無いため、この状態はどのプロファイル行にも一致せず
  # `*` がどこにも付かない。codex() の login ガードが危険と見なす状態でもあるので、
  # 行として明示する。
  if [[ -z "${CODEX_HOME:-}" ]]; then
    echo "*  (CODEX_HOME 未設定 — 共有の ~/.codex を直接使用。cx <name> で選択してください)"
  fi

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    dir="$prefix$name"
    mark=""
    [[ "$current" == "$dir" ]] && mark="*"
    [[ "$app_target" == "$dir/auth.json" ]] && mark="$mark@"
    printf '%-2s %s\n' "$mark" "$name"
  done < <(_agsw_list_profiles "$prefix")

  echo ""
  echo "  * = このシェルの CODEX_HOME / @ = Codex App が読む auth.json"
}

cx_status() {
  local shell_home="${CODEX_HOME:-$HOME/.codex}"
  local app_auth="${AGSW_CODEX_APP_AUTH:-$HOME/.codex/auth.json}"
  local app_target
  app_target="$(readlink "$app_auth" 2>/dev/null || echo "(not a symlink)")"

  # account_id を出して「shell と App が同じアカウントか」をディレクトリ名の記憶に
  # 頼らず確認できるようにする。アカウントが3つ以上あると名前だけでは追えない。
  # 取れないのは未ログイン / API-key 認証（tokens が null）/ python3 不在のとき。
  local shell_id="" app_id=""
  if [[ -x "$_AGSW_DIR/bin/agsw-codex-account-id" ]]; then
    shell_id="$("$_AGSW_DIR/bin/agsw-codex-account-id" "$shell_home/auth.json" 2>/dev/null)" || shell_id=""
    app_id="$("$_AGSW_DIR/bin/agsw-codex-account-id" "$app_auth" 2>/dev/null)" || app_id=""
  fi

  echo "shell CODEX_HOME : $shell_home"
  echo "shell account_id : ${shell_id:-(不明)}"
  echo "app auth.json -> : $app_target"
  echo "app account_id   : ${app_id:-(不明)}"

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

  # App 用 auth.json の3状態（正常symlink / 実ファイル(事故) / 不在・リンク切れ）を検査し、
  # 既知アカウントへの実ファイル化は自動修復する（codex-auth-doctor 参照）。
  # 直接 `codex login`（CODEX_HOME 未指定）が symlink を上書きした事故（2026-07-11 発生）の復旧を担う。
  [[ -x "$_AGSW_DIR/bin/codex-auth-doctor" ]] && "$_AGSW_DIR/bin/codex-auth-doctor" --fix

  # プロファイル間の symlink 漏れ検出＆自動修復（新しい Codex が追加したトップレベル項目の共有漏れ）
  [[ -x "$_AGSW_DIR/bin/check-codex-drift" ]] && "$_AGSW_DIR/bin/check-codex-drift" --fix
}

# codex() ラッパー: CODEX_HOME 未指定のまま `codex login`/`codex logout` を実行すると、
# 共有 symlink（~/.codex/auth.json）が実ファイルで上書きされ、別アカウントの認証を破壊する
# （2026-07-11 に実際に発生）。書き込み先が共有 symlink になるときだけ警告し確認を挟む。
# `cx <name>` で CODEX_HOME を明示アカウントへ向けてから login するのが正しい手順。
# AGSW_ALLOW_RAW_LOGIN=1 でこのガードを完全にバイパスできる。
codex() {
  if [[ "${AGSW_ALLOW_RAW_LOGIN:-}" != "1" ]]; then
    local arg has_login=0 has_logout=0 has_status=0 has_mcp=0
    for arg in "$@"; do
      case "$arg" in
        login)  has_login=1 ;;
        logout) has_logout=1 ;;
        status) has_status=1 ;;
        mcp)    has_mcp=1 ;;
      esac
    done

    # `codex login status` は認証を書き換えない（トークン表示のみ）ため除外する。
    # `codex mcp login/logout <server>` は MCP サーバの OAuth（Keychain /
    # .credentials.json）の操作で auth.json には触れないため対象外。
    local risky=0
    [[ "$has_login" == 1 && "$has_status" != 1 ]] && risky=1
    [[ "$has_logout" == 1 ]] && risky=1
    [[ "$has_mcp" == 1 ]] && risky=0

    if [[ "$risky" == 1 ]]; then
      # 書き込み先が共有 ~/.codex（App と共有する symlink）になるときだけ発動。
      # CODEX_HOME が明示アカウント dir を指していれば実体が分離されているので安全。
      local codex_home="${CODEX_HOME:-$HOME/.codex}"
      if [[ -z "${CODEX_HOME:-}" || "$codex_home" == "$HOME/.codex" ]]; then
        echo "⚠ 警告: CODEX_HOME が未設定/共有の ~/.codex を指しています。" >&2
        echo "  このまま login/logout すると共有 symlink（${AGSW_CODEX_APP_AUTH:-$HOME/.codex/auth.json}）が" >&2
        echo "  実ファイルで上書きされ、別アカウントの認証を破壊する恐れがあります。" >&2
        echo "  正しい手順: 先に 'cx <name>' でアカウントを選んでから login してください。" >&2
        echo "  （このガードを無効化するには AGSW_ALLOW_RAW_LOGIN=1）" >&2
        if [[ -o interactive ]]; then
          if ! read -q "?それでも続行しますか? [y/N] "; then
            echo "" >&2
            echo "中断しました。" >&2
            return 1
          fi
          echo ""
        else
          echo "非インタラクティブシェルのため拒否しました（AGSW_ALLOW_RAW_LOGIN=1 で許可）。" >&2
          return 1
        fi
      fi
    fi
  fi

  # codex プラグイン（sites 等）の MCP サーバ用 node を codex 起動時だけ PATH に注入する。
  # node は devshell のみの方針のため、通常の PATH には置かず nix が
  # ~/.local/share/codex-runtime/bin に配置したものを使う（nix/home/files.nix 参照）。
  local _codex_rt="$HOME/.local/share/codex-runtime/bin"
  if [[ -d "$_codex_rt" ]]; then
    PATH="$_codex_rt:$PATH" command codex "$@"
  else
    command codex "$@"
  fi
}

# シェル起動時チェック（インタラクティブのみ・警告表示のみ・ファイル変更なし）。
# 正常な symlink のときは lstat 1〜2 回で早期に抜け、doctor を起動しない。
# App 用 auth.json が「実ファイル(事故)」または「リンク切れ symlink」のときだけ、
# --fix 無しで doctor を呼んで警告を出す（修復は明示的な cx 実行時のみ）。
if [[ -o interactive ]]; then
  _agsw_app_auth="${AGSW_CODEX_APP_AUTH:-$HOME/.codex/auth.json}"
  if [[ -L "$_agsw_app_auth" ]]; then
    # symlink: リンク切れ（-e で辿れない）のときだけ doctor
    [[ -e "$_agsw_app_auth" ]] || {
      [[ -x "$_AGSW_DIR/bin/codex-auth-doctor" ]] && "$_AGSW_DIR/bin/codex-auth-doctor"
    }
  elif [[ -e "$_agsw_app_auth" ]]; then
    # 実ファイル（事故）→ 警告のみ
    [[ -x "$_AGSW_DIR/bin/codex-auth-doctor" ]] && "$_AGSW_DIR/bin/codex-auth-doctor"
  fi
  unset _agsw_app_auth
fi
