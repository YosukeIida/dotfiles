{
  username ? "user",
  homedir ? "/Users/${username}",
  darwinPublicConfigDir ? "/Users/${username}/workspace/github.com/YosukeIida/dotfiles",
  ...
}:
{ pkgs, ... }:

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

  users.users.${username}.home = homedir;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit darwinPublicConfigDir; };
    users.${username} = import ../../../home/default.nix;
  };

  launchd.user.agents."homebrew.mxcl.colima" = {
    serviceConfig = {
      EnvironmentVariables = {
        PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      KeepAlive = { SuccessfulExit = true; };
      LimitLoadToSessionType = [ "Aqua" "Background" "LoginWindow" "StandardIO" "System" ];
      ProgramArguments = [ "${pkgs.colima}/bin/colima" "start" "-f" ];
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

    # home.file (home-manager) に移行済みの symlink を事前に削除
    # （既存 symlink が残っていると home-manager の linkGeneration が失敗するため）
    for f in \
      "$home/.gitconfig" \
      "$home/.config/git/ignore" \
      "$home/.config/ghostty/config" \
      "$home/.config/direnv/direnvrc" \
      "$home/.config/tmux/tmux.conf" \
      "$home/.config/nvim/init.lua" \
      "$home/.hammerspoon/init.lua" \
      "$home/.hammerspoon/window_manager.lua" \
      "$home/.hammerspoon/layouts" \
      "$home/.config/zed/settings.json" \
      "$home/.config/zed/keymap.json" \
      "$home/.config/cmux/settings.json" \
      "$home/.config/gh/config.yml" \
      "$home/.config/karabiner/karabiner.json" \
      "$home/.config/karabiner/assets/complex_modifications/dodo.json" \
      "$home/.zshenv" \
      "$home/.zshrc"; do
      [ -L "$f" ] && rm "$f"
    done

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

    # codex（初回のみコピー。[projects.*] 等の自動追記を上書きしない）
    if [ ! -e "$home/.codex/config.toml" ]; then
      mkdir -p "$home/.codex"
      cp "$pub/codex/config.toml" "$home/.codex/config.toml"
    fi
  '';
}
