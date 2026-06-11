{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = false;
      cleanup = "none"; # Homebrew 5.x で --cleanup に --force が必要になったため無効化
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
    ];

    brews = [
      "brightness"
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
      "ghostty"
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
