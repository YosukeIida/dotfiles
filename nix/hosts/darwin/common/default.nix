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
    backupFileExtension = "bak";
  };

  system.activationScripts.postActivation.text = ''
    # python の versioned symlink を PATH に露出させない
    su - ${username} -c "/opt/homebrew/bin/brew unlink python@3.11 python@3.14 2>/dev/null || true"

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

    # public skills を ~/.codex/skills/ にも展開
    mkdir -p "$home/.codex/skills"
    for d in "$pub/agents/skills"/*/; do
      [ -d "$d" ] || continue
      _link "$d" "$home/.codex/skills/$(basename "$d")"
    done

    # Codex の安定設定は system layer で管理する。
    # ~/.codex/config.toml は projects/trust/UI 等のローカル状態として Codex に所有させる。
    _link "$pub/codex/config.toml" "/etc/codex/config.toml"

    # 旧 activation が ~/.codex/config.toml にコピーした安定設定を除去する。
    # user layer は system layer より優先されるため、残すと新しい system 設定が無視される。
    su - ${username} -c "bash $pub/codex/migrate-user-config.sh" || true

    # Claude Code プラグインを自動インストール（ユーザー権限で実行）
    su - ${username} -c "bash $pub/claude/install-plugins.sh" || true

    # Codex プラグインを希望リストから冪等にインストール
    su - ${username} -c "bash $pub/codex/install-plugins.sh" || true
  '';
}
