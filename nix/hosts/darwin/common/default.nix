{
  username ? "user",
  homedir ? "/Users/${username}",
  darwinPublicConfigDir ? "/Users/${username}/workspace/github.com/YosukeIida/dotfiles",
  ...
}:

{
  imports = [
    (import ../../../profiles/darwin/macos-defaults.nix {
      inherit username homedir;
    })
    ../../../profiles/darwin/fonts.nix
    ../../../profiles/darwin/homebrew.nix
  ];

  system = {
    stateVersion = 6;
    primaryUser = username;
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-darwin";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  launchd.user.agents."homebrew.mxcl.colima" = {
    serviceConfig = {
      EnvironmentVariables = {
        PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      KeepAlive = { SuccessfulExit = true; };
      LimitLoadToSessionType = [ "Aqua" "Background" "LoginWindow" "StandardIO" "System" ];
      ProgramArguments = [ "/opt/homebrew/opt/colima/bin/colima" "start" "-f" ];
      RunAtLoad = true;
      StandardErrorPath = "/opt/homebrew/var/log/colima.log";
      StandardOutPath = "/opt/homebrew/var/log/colima.log";
      WorkingDirectory = homedir;
    };
  };

  system.activationScripts.postActivation.text = ''
    # omlx が依存する python@3.11 の versioned symlink を PATH に露出させない
    su - ${username} -c "/opt/homebrew/bin/brew unlink python@3.11 2>/dev/null || true"

    pub="${darwinPublicConfigDir}"
    home="${homedir}"

    _link() {
      local src="$1" dst="$2"
      mkdir -p "$(dirname "$dst")"
      if [ -L "$dst" ]; then
        rm "$dst"
      elif [ -e "$dst" ]; then
        mv "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
      fi
      ln -sf "$src" "$dst"
    }

    # Claude Code
    if [ -f "$home/.claude/settings.json" ] && [ ! -L "$home/.claude/settings.json" ]; then
      cp "$home/.claude/settings.json" "$pub/claude/settings.json"
    fi
    _link "$pub/claude/settings.json"              "$home/.claude/settings.json"
    _link "$pub/claude/settings.api.json"          "$home/.claude/settings.api.json"
    _link "$pub/claude/settings.subscription.json" "$home/.claude/settings.subscription.json"
    _link "$pub/claude/settings.subscription.json" "$home/.claude-2/settings.subscription.json"
    _link "$pub/claude/get_key.sh"                 "$home/.claude/get_key.sh"
    _link "$pub/claude/statusline.sh"              "$home/.claude/statusline.sh"
    _link "$pub/agents/AGENTS.md"                  "$home/.claude/CLAUDE.md"
    _link "$pub/agents/AGENTS.md"                  "$home/.codex/AGENTS.md"

    # Claude Code プラグインを自動インストール（ユーザー権限で実行）
    su - ${username} -c "bash $pub/claude/install-plugins.sh" || true

    # public skills を ~/.claude/skills/ に展開
    # ~/.claude/skills が symlink なら実ディレクトリに移行
    if [ -L "$home/.claude/skills" ]; then
      rm "$home/.claude/skills"
    fi
    mkdir -p "$home/.claude/skills"
    for d in "$pub/agents/skills"/*/; do
      [ -d "$d" ] || continue
      _link "$d" "$home/.claude/skills/$(basename "$d")"
    done

    # git
    _link "$pub/git/gitconfig" "$home/.gitconfig"
    _link "$pub/git/ignore"    "$home/.config/git/ignore"

    # ghostty
    _link "$pub/ghostty/config" "$home/.config/ghostty/config"

    # direnv
    _link "$pub/direnv/direnvrc" "$home/.config/direnv/direnvrc"

    # tmux
    _link "$pub/tmux/tmux.conf" "$home/.config/tmux/tmux.conf"

    # nvim
    _link "$pub/nvim/init.lua" "$home/.config/nvim/init.lua"

    # hammerspoon
    _link "$pub/hammerspoon/init.lua"           "$home/.hammerspoon/init.lua"
    _link "$pub/hammerspoon/window_manager.lua" "$home/.hammerspoon/window_manager.lua"
    _link "$pub/hammerspoon/layouts"            "$home/.hammerspoon/layouts"

    # zed
    _link "$pub/zed/settings.json" "$home/.config/zed/settings.json"
    _link "$pub/zed/keymap.json"   "$home/.config/zed/keymap.json"

    # cmux
    _link "$pub/cmux/settings.json" "$home/.config/cmux/settings.json"

    # gh
    _link "$pub/gh/config.yml" "$home/.config/gh/config.yml"

    # karabiner
    _link "$pub/karabiner/karabiner.json"                         "$home/.config/karabiner/karabiner.json"
    _link "$pub/karabiner/assets/complex_modifications/dodo.json" "$home/.config/karabiner/assets/complex_modifications/dodo.json"

    # zsh
    _link "$pub/zsh/zshenv" "$home/.zshenv"
    _link "$pub/zsh/zshrc"  "$home/.zshrc"

    # codex（初回のみコピー。[projects.*] 等の自動追記を上書きしない）
    if [ ! -e "$home/.codex/config.toml" ]; then
      mkdir -p "$home/.codex"
      cp "$pub/codex/config.toml" "$home/.codex/config.toml"
    fi
  '';
}
