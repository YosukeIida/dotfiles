{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = false;
      cleanup = "zap";
      # cleanup は --force なしだと削除対象がある限り exit 1 になるだけで実際には削除しない
      # （Homebrew Bundle の既知の制限）ため、--force を明示して宣言的クリーンアップを機能させる。
      # ~/.homebrew/trust.json を symlink ではなく copy 管理にしている（nix/home/files.nix の
      # homebrewTrustJson activation）のは、--force 実行時に Homebrew 自身がこのファイルへ
      # 書き込みを試み、symlink 先が nix store（root/nixbld 所有）だと拒否されるため。
      extraFlags = [ "--force" ];
    };

    taps = [
      {
        name = "jundot/omlx";
        clone_target = "https://github.com/jundot/omlx";
      }
      "solarphlare/airmute"
      "steipete/tap"
      "yosukeiida/casks-personal"
    ];

    brews = [
      "brightness"
      "ffmpeg"
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
      "codex-app"
      "codexbar"
      "discord"
      "figma@beta"
      "fujitsu-scansnap-home"
      "ghostty@tip"
      "google-chrome@canary"
      "google-drive"
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
      "yosukeiida/casks-personal/zed-dev-ratex"
    ];
  };
}
