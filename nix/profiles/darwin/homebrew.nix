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
    extraConfig = ''
      tap "can1357/tap", trusted: true
      tap "jundot/omlx", "https://github.com/jundot/omlx", trusted: true
      tap "solarphlare/airmute", trusted: true
      tap "steipete/tap", trusted: true
      tap "xoshbin/asyar", trusted: true
      tap "yosukeiida/casks-personal", trusted: true
    '';

    brews = [
      # homebrew-core 版は node 依存（scripts/cli.cjs の薄い dispatcher のためだけ）。
      # yosukeiida/casks-personal 版は upstream が npm optionalDependency で配布している
      # プリコンパイル済みネイティブバイナリ（darwin-arm64）を直接installし、node依存ゼロ。
      "yosukeiida/casks-personal/backlog-md"
      "bat"
      "brightness"
      # omp（oh my pi）。formula は release の単体バイナリを置くだけで depends_on ゼロ
      # （node/bun 非依存）。nixpkgs には無く、derivation を書いても formula と同内容に
      # なるうえ version/sha256 の手動追随が増えるため homebrew 側で管理する。
      "can1357/tap/omp"
      # Apple Container 本体（CLI + XPC バックエンド）。Orchard（cask）はこの GUI フロント
      # エンドで、本体がないと "XPC connection error" になる。常駐サービス化はせず、
      # 使うときに `container system start` を手動実行する運用。
      "container"
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
      "herdr"
      # hermes-agent は brew ではなく nix flake input（upstream 自身の uv2nix
      # packaging）から home.packages 経由で導入する（nix/home/packages.nix の
      # hermesAgentPkgs.full）。brew formula は node を depends_on して
      # /opt/homebrew/bin にリンクしてしまう（nodeless 方針違反）ため使わない。
      "hunk"
      "jundot/omlx/omlx"
      "mas"
      "rtk"
      "xcodegen"
    ];

    # Mac App Store アプリ（mas 経由）。Bitwarden は agenix バックアップ鍵の回収に必要なため
    # flake から再現する（App Store へのサインインのみ手動。README 参照）。
    masApps = {
      Bitwarden = 1352778147;
    };

    casks = [
      "adobe-acrobat-reader"
      "affinity"
      "airmute"
      "arc"
      "xoshbin/asyar/asyar"
      "chatgpt"
      "chrome-remote-desktop-host"
      "claude"
      "claude-code@latest"
      "yosukeiida/casks-personal/claude-science"
      "cloudflare-warp@beta"
      "cmux"
      "codex"
      "codexbar"
      "discord"
      "figma@beta"
      "fujitsu-scansnap-home"
      "ghostty@tip"
      "google-chrome"
      "hammerspoon"
      "karabiner-elements"
      "lens"
      "libreoffice"
      "lm-studio"
      "microsoft-auto-update"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-teams"
      "microsoft-word"
      "nani"
      "yosukeiida/casks-personal/nimbus"
      "notion"
      "notion-calendar"
      "obsidian"
      "onlyoffice"
      "orbstack"
      "orchard"
      "yosukeiida/casks-personal/pindrop"
      "yosukeiida/casks-personal/powerglance"
      "raycast"
      "shottr"
      "skim"
      "slack"
      "stats"
      "tailscale-app"
      "thebrowsercompany-dia"
      "visual-studio-code"
      "wezterm@nightly"
      "zed"
      # 個人 fork の自前ビルドなので ad-hoc 署名（TeamIdentifier なし、spctl は rejected）で、
      # quarantine 属性が付くと Gatekeeper に起動を止められる。ただしここで
      # args = { no_quarantine = true; } は指定できない: Homebrew 6 には install 時に
      # quarantine を無効化する手段がそもそも存在しない。--no-quarantine は CLI フラグとして
      # 廃止されたうえ、HOMEBREW_CASK_OPTS 経由でも効かない（判定関数
      # EnvConfig.cask_opts_quarantine? は env_config.rb:983 に定義が残るだけで呼び出し元ゼロ。
      # cmd/install.rb:372,420 は Cask::Installer に quarantine: を渡さないため、
      # installer.rb:42 の既定値 true が常に使われる）。加えて brew bundle は args を
      # そのまま "--#{key}" に変換して渡すため（bundle/cask.rb:78-88）install 自体が失敗し、
      # upgrade 経路では args を渡さない（同 76）。対処は cask 側の postflight で
      # xattr -dr する（検証: Homebrew 6.0.12）。
      "yosukeiida/casks-personal/zed-dev-ratex"
    ];
  };
}
