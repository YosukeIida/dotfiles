{
  username ? "user",
  homedir ? "/Users/${username}",
  darwinPublicConfigDir ? "/Users/${username}/workspace/github.com/YosukeIida/dotfiles",
  pkgsUnstable,
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
    extraSpecialArgs = { inherit darwinPublicConfigDir pkgsUnstable; };
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

    # clean filter は python を使わない。python ガード
    # （tools/agent-switch/runtime-guards/python-guard.sh）が Claude Code セッション中の
    # PATH に入ると、フィルタが絶対パスで /usr/bin/python3 を呼んでいても撃ち落とされる
    # （macOS の python3 は PATH を再解決するスタブのため。2026-07-28 実測）。
    # フィルタが失敗すると「除去すべきキーがそのままコミットされる」か「git add が
    # 中断する」のどちらかになり、この仕組みの目的が崩れる。
    # インタプリタは nix store のパスを直指定する（PATH に依存しない・generation ごとに固定）。

    # settings.json / settings.api.json の "model" キーは /model コマンドで頻繁に
    # ローカル書き換えされるため、git の管理対象から外す（clean filter で常に除去）。
    # .gitattributes で filter=strip-model が指定されているファイルにのみ効く。
    su - ${username} -c "cd $pub && git config filter.strip-model.clean '${pkgs.jq}/bin/jq --indent 2 -f \"\$(git rev-parse --show-toplevel)/claude/git-filters/strip-model-clean.jq\"' && git config filter.strip-model.smudge cat" || true

    # karabiner.json の "selected" プロファイルは GUI 切替で頻繁に書き換わるため、
    # git の管理対象から外す（clean filter で常に "Default profile" に固定）。
    # .gitattributes で filter=strip-selected が指定されているファイルにのみ効く。
    # jq ではなく awk なのは、karabiner.json の独自コンパクト整形を再シリアライズで
    # 壊さないため（実測 783行 → 1161行）。詳細はスクリプト内のコメント参照。
    su - ${username} -c "cd $pub && git config filter.strip-selected.clean '${pkgs.gawk}/bin/awk -f \"\$(git rev-parse --show-toplevel)/karabiner/git-filters/strip-selected-clean.awk\"' && git config filter.strip-selected.smudge cat" || true
    _link "$pub/claude/settings.api.json"          "$home/.claude/settings.api.json"
    _link "$pub/claude/get_key.sh"                 "$home/.claude/get_key.sh"
    _link "$pub/claude/statusline.sh"              "$home/.claude/statusline.sh"
    _link "$pub/claude/subagent-statusline.sh"     "$home/.claude/subagent-statusline.sh"
    _link "$pub/agents/AGENTS.md"                  "$home/.claude/CLAUDE.md"
    _link "$pub/agents/AGENTS.md"                  "$home/.codex/AGENTS.md"

    # public skills を ~/.claude/skills/ に展開
    # ~/.claude/skills が symlink なら実ディレクトリに移行
    if [ -L "$home/.claude/skills" ]; then
      rm "$home/.claude/skills"
    fi
    mkdir -p "$home/.claude/skills"
    # postActivation は root で走るため mkdir がディレクトリを root 所有にしてしまう。
    # home-manager の linkGeneration はユーザー権限で同じディレクトリに書くので、
    # 所有者をユーザーに戻さないと activation が Permission denied で失敗する。
    chown ${username}:staff "$home/.claude/skills"
    for d in "$pub/agents/skills"/*/; do
      [ -d "$d" ] || continue
      _link "$d" "$home/.claude/skills/$(basename "$d")"
    done

    # agent-browser CLI に同梱の公式 skill。git vendor ではなく nix store から直接
    # symlink する — nixpkgs-unstable の pin 更新だけで CLI と skill が同時にバージョンアップする。
    _link "${pkgsUnstable.agent-browser}/skills/agent-browser" "$home/.claude/skills/agent-browser"

    # public skills を ~/.codex/skills/ にも展開
    mkdir -p "$home/.codex/skills"
    chown ${username}:staff "$home/.codex/skills"
    for d in "$pub/agents/skills"/*/; do
      [ -d "$d" ] || continue
      _link "$d" "$home/.codex/skills/$(basename "$d")"
    done
    _link "${pkgsUnstable.agent-browser}/skills/agent-browser" "$home/.codex/skills/agent-browser"

    # skill を削除・移動したあとに残るリンク切れ symlink を掃除する。
    # 有効な symlink・実ディレクトリ（home-manager 管理の per-file link 等）には触れない。
    for skdir in "$home/.claude/skills" "$home/.codex/skills"; do
      [ -d "$skdir" ] || continue
      for l in "$skdir"/*; do
        if [ -L "$l" ] && [ ! -e "$l" ]; then
          rm "$l"
        fi
      done
    done

    # subagents を ~/.claude/agents/ に展開
    mkdir -p "$home/.claude/agents"
    for f in "$pub/agents/subagents"/*.md; do
      [ -f "$f" ] || continue
      _link "$f" "$home/.claude/agents/$(basename "$f")"
    done

    # subagent を削除・リネームしたあとに残るリンク切れ symlink を掃除する。
    # 有効な symlink には触れない（skills の掃除ループと同じ安全条件）。
    for l in "$home/.claude/agents"/*; do
      if [ -L "$l" ] && [ ! -e "$l" ]; then
        rm "$l"
      fi
    done

    # Codex の安定設定（/etc/codex/config.toml）は approval_policy=never・
    # sandbox_mode=danger-full-access という個人の合意前提の危険設定を含むため、
    # common（example にも波及）ではなく host 固有（yosuke-macbook-air.nix）で配備する。

    # Claude Code プラグインを自動インストール（ユーザー権限で実行）
    su - ${username} -c "bash $pub/claude/install-plugins.sh" || true

    # Codex プラグインを希望リストから冪等にインストール
    su - ${username} -c "bash $pub/codex/install-plugins.sh" || true

    # 外部由来 skill（gist・GitHub repo 等）の更新有無を通知のみ表示する（brew outdated 相当）。
    # 内容は一切書き換えない（読み取り専用）。ネットワーク不通でも switch を失敗させない。
    if [ -x "$pub/sync-external-skills.sh" ]; then
      su - ${username} -c "bash $pub/sync-external-skills.sh --check" || true
    fi

    # Asyar（2026-07-30 Raycastから移行）。設定・portals は tauri-plugin-store の
    # JSON（拡張子は .dat だが中身はプレーンJSON）で
    # ~/Library/Application Support/org.asyar.app/ 配下に保存される
    # （clipboard/snippets/shortcuts/エイリアス等は asyar_data.db という別の
    # SQLiteで、こちらはクリップボード履歴等の個人データを含むため対象外）。
    # Claude Code の settings.json と同じ「実ファイルが既にあれば初回だけ dotfiles に
    # 取り込んで symlink 化」パターン。オンボーディング未完了（ファイル未生成）の間は
    # 何もしない — root 権限の postActivation が先にディレクトリを作ってしまうと
    # ユーザー権限で動く Asyar 本体が同ディレクトリに書き込めなくなるため。
    _asyar_sync_store() {
      local name="$1"
      local live="$home/Library/Application Support/org.asyar.app/$name"
      if [ -f "$live" ] && [ ! -L "$live" ]; then
        mkdir -p "$pub/asyar"
        chown ${username}:staff "$pub/asyar"
        cp "$live" "$pub/asyar/$name"
        chown ${username}:staff "$pub/asyar/$name"
      fi
      if [ -f "$pub/asyar/$name" ] && [ ! -L "$live" ]; then
        _link "$pub/asyar/$name" "$live"
        chown -h ${username}:staff "$live"
      fi
    }
    _asyar_sync_store "settings.dat"
    _asyar_sync_store "portals.dat"
  '';
}
