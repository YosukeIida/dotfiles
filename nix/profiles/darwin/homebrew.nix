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
      "yosukeiida/omlx"
      "yosukeiida/pindrop"
    ];

    brews = [
      "brightness"
      "cloudflared"
      "colima"
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
      "omlx"
      "onlyoffice"
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
