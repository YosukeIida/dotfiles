# 全構成（fork の土台の example・秘書の VM・Yosuke の各 Mac）に入る最小の一覧。
# 個人の Mac だけで使うものは nix/hosts/darwin/yosuke/homebrew.nix、Office は office.nix、
# 秘書の VM だけで使うものは secretary.nix に置く。
{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = false;
      cleanup = "zap";
      # cleanup は --force なしだと削除対象がある限り exit 1 になるだけで実際には削除しない
      # （Homebrew Bundle の既知の制限）ため、--force を明示して宣言的クリーンアップを機能させる。
      extraFlags = [ "--force" ];
    };

    # tap trust: Homebrew（2026-07 の更新以降）は非公式 tap の formula/cask 読み込みに
    # `brew trust` による信頼を既定で要求し、`brew bundle --cleanup --force` は
    # ~/.homebrew/trust.json を「Brewfile 内の trusted: 宣言」で毎回**完全置換**する
    # （bundle/subcommand/cleanup.rb の Trust.replace!）。手動 `brew trust` や外部からの
    # trust.json 配置は switch のたびに消されるため、Brewfile 行での宣言が唯一持続する方法。
    #
    # nix-darwin の tapOptions は trusted: 未対応（name/clone_target/force_auto_update のみ）で、
    # tap 行の brewfileLine は readOnly のため上書きもできない。そのため taps ではなく
    # extraConfig（Brewfile 末尾にそのまま追記される）で tap を宣言する。bundle は tap 依存を
    # 名前で解決する（installer.rb の tap_dependencies）ため、Brewfile 内での行順は問題ない。
    # nix-darwin が trusted オプションに対応したら taps に戻すこと。
    # 各層の extraConfig は連結される（types.lines）ので、tap はそれを使う cask と同じ層に置く。
    # steipete/tap は codexbar（作者の tap）の入手元。一度その tap から入れた機械では、宣言から外すと
    # brew cleanup が未信頼の tap の cask を読めずに失敗し、untap もできない（2026-11-06 に秘書の VM で遭遇）。
    extraConfig = ''
      tap "yosukeiida/casks-personal", trusted: true
      tap "steipete/tap", trusted: true
    '';

    brews = [
      "bat"
      "ffmpeg"
      "git-delta"
      "glow"
      # Google Workspace CLI（gws）。Drive/Sheets/Gmail を1つの CLI で扱う。
      # 認証情報の置き場は GOOGLE_WORKSPACE_CLI_CONFIG_DIR で上書きできるため、
      # バイナリはグローバルで1つ、アカウントは ~/.config/gws/<email>/ に分離する
      # 運用にしている（gws-multi-account skill、agents/skills/gws-multi-account/）。
      # 2026-08 以前は repo ごとに .envrc で既定アカウントを固定する方式だったが、
      # direnv の export は Claude Code の Bash ツールには自動で乗らない（実測済み）
      # ため廃止し、エージェントは常に skill 経由で明示的に CONFIG_DIR を指定する
      # 運用に一本化した。skill 側の PreToolUse hook が CONFIG_DIR 未指定の
      # 裸の `gws` 呼び出しを弾く。
      "googleworkspace-cli"
      "hunk"
      "rtk"
    ];

    casks = [
      # 公式 cask は quarantine 付きのまま置くので、更新後の初回起動で Gatekeeper の
      # ダイアログが出て止まる。preflight で quarantine を外す以外は公式と同じ cask
      # を使う（詳細は casks-personal の Casks/claude-code@latest.rb）。
      "yosukeiida/casks-personal/claude-code@latest"
      # 公式 cask は更新時に quarantine 付きの bin/codex で補完を生成するため、
      # Gatekeeper のダイアログで brew upgrade が止まる。preflight で quarantine を
      # 外す以外は公式と同じ cask を使う（詳細は casks-personal の Casks/codex.rb）。
      "yosukeiida/casks-personal/codex"
      # 秘書の VM では、OpenClaw 同梱の skill model-usage が CodexBar の記録から利用量を集計する。
      "codexbar"
      "google-chrome"
    ];
  };
}
