# CodexBar（メニューバーの Claude/Codex 使用量モニタ）の宣言的設定。
#
# 認証情報（token・アカウントラベル）は一切対象にしない。管理するのは
# 「アプリの見た目・挙動の好み」と「有効化するプロバイダ」の2種類だけ。
#
# - 表示系の設定（usage bar の見た目・menu bar の表示モード等）は
#   ~/.codexbar/config.json ではなく macOS defaults（NSUserDefaults,
#   ドメイン com.steipete.codexbar）に保存されている。nix-darwin の
#   CustomUserPreferences で宣言する（既存値をそのまま固定。2026-09-07 実測）。
# - ~/.codexbar/config.json は認証（tokenAccounts）・接続方式（source /
#   cookieSource）・設定が同居する単一ファイルで、アプリが随時全体を
#   書き戻す。symlink はしない。claude/codex 2エントリの `enabled` だけを
#   jq で部分パッチする：
#     - source / cookieSource は対象外（Settings UI で Web cookie /
#       OAuth API / CLI のどれを使うか試行錯誤中のため、switch のたびに
#       巻き戻したくない）
#     - tokenAccounts（token・"TMLlab"/"personal" 等のラベル）は対象外
#       （シークレットなので dotfiles に一切載せない）
#     - 他の約60件の無効プロバイダ行、および将来 CodexBar が追加する
#       新規プロバイダ行には一切触れない（配列全体は書き換えない）
{ pkgs, ... }:

let
  username = "yosuke";
  homedir = "/Users/${username}";
in
{
  system.defaults.CustomUserPreferences."com.steipete.codexbar" = {
    usageBarsShowUsed = true;
    launchAtLogin = true;
    menuBarDisplayMode = "percent";
    costSummaryDisplayStyle = "both";
    claudeModelScopedWeeklyUsageVisible = true;
    historicalTrackingEnabled = true;
    showOptionalCreditsAndExtraUsage = true;
    refreshFrequency = "fifteenMinutes";
  };

  system.activationScripts.postActivation.text = ''
    # ~/.codexbar/config.json: claude/codex の enabled だけ宣言値に揃える。
    # 未インストール・未起動でファイルが無ければ何もせずスキップする。
    _cbcfg="${homedir}/.codexbar/config.json"
    if [ -f "$_cbcfg" ]; then
      # 差分があるときだけ書く（アプリ起動中の無駄な書き戻しを避ける）。
      # jq が失敗（不正 JSON・providers 欠落等）したら空文字になり
      # "differs" にならないので fail-soft。
      if [ "$(su - ${username} -c "${pkgs.jq}/bin/jq -r 'if ([.providers[] | select(.id == \"claude\" or .id == \"codex\") | .enabled] | any(. != true)) then \"differs\" else \"same\" end' '$_cbcfg'" 2>/dev/null)" = "differs" ]; then
        # inode とパーミッションを保つため mv ではなく cat で上書きする。
        if su - ${username} -c "${pkgs.jq}/bin/jq '.providers |= map(if (.id == \"claude\" or .id == \"codex\") then (.enabled = true) else . end)' '$_cbcfg' > '$_cbcfg.new' && cat '$_cbcfg.new' > '$_cbcfg' && rm -f '$_cbcfg.new'"; then
          echo "codexbar: ~/.codexbar/config.json の claude/codex enabled を dotfiles の宣言値に更新した"
        else
          echo >&2 "warning: ~/.codexbar/config.json の更新に失敗した（内容は変更されていない）"
        fi
      fi
    fi
  '';
}
