# ~/.config/shell/common.sh — zsh（zshrc）と bash（bashrc）の両方が読む関数・alias。
# 両方のシェルで動く構文だけで書く（zsh の path 配列・修飾子は使わない）。

# =====================================================================
# ==== omp（oh my pi）のアカウント切り替え =============================
# =====================================================================
# omp は --profile / OMP_PROFILE で auth・セッション・設定・キャッシュを丸ごと
# 分離する（codex に profile の概念が無く cx が CODEX_HOME を差し替えているのとは
# 違い、omp 側の標準機能）。プロファイルの実体は ~/.omp/profiles/<name>/。
#
#   personal = ChatGPT Plus / labteam = Team プラン（同一メールだが別枠）
#
# 既定を export しておけば、どの端末で起動する omp もこれを継承する。
# 一時的に切り替えたいときだけ omp-personal / omp-labteam を使う。
#
# 注意: 同一プロファイルに両方ログインすると omp はセッションごとに round-robin で
# 振り分ける（`omp token openai-codex --list` の --account 参照）。分けたいなら
# プロファイルを必ず分けること。
export OMP_PROFILE=personal
alias omp-personal='OMP_PROFILE=personal omp'
alias omp-labteam='OMP_PROFILE=labteam omp'
# Anthropic の API キー（Claude Code の api モードと同じ anthropic.env）で Opus を使う
alias omp-api='ANTHROPIC_API_KEY="$(sh ~/.claude/get_key.sh)" omp --model anthropic/claude-opus-5-5'
omp-help() {
  cat <<EOF
omp            既定の profile（OMP_PROFILE=${OMP_PROFILE:-未設定}）で起動
omp-personal   personal の profile で起動
omp-labteam    labteam の profile で起動
omp-api        Anthropic の API キー（~/.claude/anthropic.env）で Opus 5.5 を起動
               別のモデル: omp-api --model anthropic/claude-haiku-5-5
1 回だけ応答させる: 上のどれかに -p "<質問>" を足す
EOF
}

# =====================================================================
# ==== クリップボード整形 ==============================================
# =====================================================================
# Claude Code のターミナル出力をコピーした際に行頭2スペースを除去する
alias cleanspace='pbpaste | sed -E "s/^ {1,2}//" | pbcopy && pbpaste'
alias cs='cleanspace'

# =====================================================================
# ==== Zed Dev (RaTeX unofficial) 起動 =================================
# =====================================================================
#   zedd .        カレントディレクトリを Zed Dev で開く
# --user-data-dir で通常の Zed とデータ（DB/拡張/セッション）を分離する。
# config はその data dir 配下を読むが、files.nix が dotfiles/zed/ の実体へ
# symlink しているため設定・keymap・tasks は通常の Zed と共有される。
# 同梱の cli バイナリを使う（1.10 以降は dev ビルドにも同梱される）。
# open -b（Apple イベント）経路だと cli_default_open_behavior が参照されず、
# 既存 window の multi-workspace サイドバーに追加されてしまうため cli 経由が必須。
zedd() {
  "/Applications/Zed Dev RaTeX(unofficial).app/Contents/MacOS/cli" \
    --user-data-dir "$HOME/Library/Application Support/ZedDevRaTeX" "$@"
}

# =====================================================================
# ==== cctag spoke 起動 ================================================
# =====================================================================
# tmllab Slack workspace 用の CCTAG_ENV_FILE を自動指定して起動する。
# 複数 workspace を使うようになったら workspace ごとに同様の関数を増やす。
cctag-spoke() {
  CCTAG_ENV_FILE="$HOME/.config/cctag/slack_tmllab_workspace.env" command cctag-spoke "$@"
}

# nutmeg Slack workspace 用（自前 Hub: cctag-hub.iodine2.net）。
cctag-spoke-nutmeg() {
  CCTAG_ENV_FILE="$HOME/.config/cctag/slack_nutmeg_workspace.env" command cctag-spoke "$@"
}

# kyosukeegg Slack workspace 用（Hub: cctag-hub-kyosukeegg.iodine2.net）。
cctag-spoke-kyosukeegg() {
  CCTAG_ENV_FILE="$HOME/.config/cctag/slack_kyosukeegg_workspace.env" command cctag-spoke "$@"
}

# =====================================================================
# ==== sleepctl: 蓋閉じ耐性の切り替え ===================================
# =====================================================================
# 蓋を閉じても処理を継続する状態 (pmset -a disablesleep) を切り替える。
# on/off のパスワードレス実行は nix/hosts/darwin/yosuke/macbook-air.nix の
# security.sudo.extraConfig にある sudoers NOPASSWD ルール前提。
# sudoers 側と引数を完全一致させること（-a disablesleep 1 / -a disablesleep 0）。
# 蓋閉じ時の画面消灯は launchd agent com.yosuke.sleepctl-watcher が別途行う。
function sleepctl() {
  case "$1" in
    on)
      sudo /usr/bin/pmset -a disablesleep 1 && echo "sleepctl: on (蓋を閉じても処理を継続)"
      ;;
    off)
      sudo /usr/bin/pmset -a disablesleep 0 && echo "sleepctl: off (通常のスリープ動作)"
      ;;
    status)
      if [[ "$(pmset -g | awk '$1 == "SleepDisabled" { print $2 }')" == "1" ]]; then
        echo "on"
      else
        echo "off"
      fi
      ;;
    *)
      echo "usage: sleepctl {on|off|status}" >&2
      return 1
      ;;
  esac
}
