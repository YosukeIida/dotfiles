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
      "yosukeiida/nimbus"
      "yosukeiida/pindrop"
      {
        name = "yosukeiida/powerglance";
        clone_target = "/Users/yosuke/workspace/github.com/YosukeIida/homebrew-powerglance";
      }
    ];

    brews = [
      "brightness"
      "ffmpeg"
      "herdr"
      "hermes-agent"
      "jundot/omlx/omlx"
      "rtk"
      "xcodegen"
    ];

    casks = [
      "adobe-acrobat-reader"
      "affinity"
      "airmute"
      "arc"
      "chatgpt"
      "chrome-remote-desktop-host"
      "claude"
      "claude-code@latest"
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
      "yosukeiida/nimbus/nimbus"
      "notion"
      "notion-calendar"
      "obsidian"
      "onlyoffice"
      "orbstack"
      "pindrop"
      "yosukeiida/powerglance/powerglance"
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
    ];
  };
}
