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
      tap "jundot/omlx", "https://github.com/jundot/omlx", trusted: true
      tap "solarphlare/airmute", trusted: true
      tap "steipete/tap", trusted: true
      tap "yosukeiida/casks-personal", trusted: true
    '';

    brews = [
      # homebrew-core 版は node 依存（scripts/cli.cjs の薄い dispatcher のためだけ）。
      # yosukeiida/casks-personal 版は upstream が npm optionalDependency で配布している
      # プリコンパイル済みネイティブバイナリ（darwin-arm64）を直接installし、node依存ゼロ。
      "yosukeiida/casks-personal/backlog-md"
      "bat"
      "brightness"
      "ffmpeg"
      "git-delta"
      "glow"
      "herdr"
      "hermes-agent"
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
      "google-chrome@canary"
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
      "paseo"
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
      # args = { no_quarantine = true; } は指定できない: Homebrew 6 で --no-quarantine は
      # CLI フラグとしては廃止されており（HOMEBREW_CASK_OPTS 経由のみ）、brew bundle は
      # それをフラグに変換して渡すため install が失敗する。加えて brew bundle は
      # upgrade 経路では args を渡さない（bundle/cask.rb:75-76）。対処は cask 側で行う。
      "yosukeiida/casks-personal/zed-dev-ratex"
    ];
  };
}
