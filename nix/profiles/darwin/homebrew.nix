{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = false;
      cleanup = "zap";
    };

    taps = [
      "solarphlare/airmute"
      "steipete/tap"
      "yosukeiida/pindrop"
    ];

    brews = [
      "brightness"
      "cloudflared"
      {
        name = "colima";
        start_service = true;
        restart_service = "changed";
      }
      "duti"
      "fzf"
      "gh"
      "ghq"
      "lazydocker"
      "lazygit"
      "neovim"
      "poppler"
      "rclone"
      "tmux"
      "tree"
      "zellij"
      "zsh-autosuggestions"
      "zsh-syntax-highlighting"
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
      "discord"
      "docker-desktop"
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
      "notion"
      "notion-calendar"
      "obsidian"
      "onlyoffice"
      {
        name = "yosukeiida/pindrop/pindrop";
      }
      "raycast"
      "shottr"
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
