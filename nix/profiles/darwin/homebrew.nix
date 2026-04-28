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
      "duti"
      "fzf"
      "gh"
      "ghq"
      "git-filter-repo"
      "lazygit"
      "neovim"
      "poppler"
      "rclone"
      "tmux"
      "tree"
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
      "wezterm"
      "zed"
    ];
  };
}
