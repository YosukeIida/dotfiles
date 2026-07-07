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

  # Zed のビルド済み依存を取得する cachix バイナリキャッシュ。
  # zed リポジトリ同梱 flake の nixConfig と同じ値をグローバルに信頼させ、
  # `nix develop` 時の承認プロンプトを不要にする。
  nix.settings.extra-substituters = [
    "https://zed.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
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
    # settings.json は「実ファイルなら dotfiles に取り込んで symlink 化」を初回だけ行う。
    # 既に symlink なら張り替えない: cc api が settings.api.json へ差し替えた
    # モード選択を darwin-switch が巻き戻さないようにするため。
    if [ -f "$home/.claude/settings.json" ] && [ ! -L "$home/.claude/settings.json" ]; then
      cp "$home/.claude/settings.json" "$pub/claude/settings.json"
    fi
    if [ ! -L "$home/.claude/settings.json" ]; then
      _link "$pub/claude/settings.json"            "$home/.claude/settings.json"
    fi
    # settings.api.json は生成物（live settings.json + api-mode-overlay.json）。
    # 編集は api-mode-overlay.json 側へ。サブスクは live をそのまま使う（複製しない）。
    su - ${username} -c "bash $pub/claude/gen-api-settings.sh" || true

    # settings.json / settings.api.json の "model" キーは /model コマンドで頻繁に
    # ローカル書き換えされるため、git の管理対象から外す（clean filter で常に除去）。
    # .gitattributes で filter=strip-model が指定されているファイルにのみ効く。
    su - ${username} -c "cd $pub && git config filter.strip-model.clean '/usr/bin/python3 \"\$(git rev-parse --show-toplevel)/claude/git-filters/strip-model-clean.py\"' && git config filter.strip-model.smudge cat" || true
    _link "$pub/claude/settings.api.json"          "$home/.claude/settings.api.json"
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

    # subagents を ~/.claude/agents/ に展開
    mkdir -p "$home/.claude/agents"
    for f in "$pub/agents/subagents"/*.md; do
      [ -f "$f" ] || continue
      _link "$f" "$home/.claude/agents/$(basename "$f")"
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
