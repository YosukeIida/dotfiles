{
  config,
  lib,
  pkgs,
  darwinPublicConfigDir,
  ...
}:

let
  lnk = path: config.lib.file.mkOutOfStoreSymlink "${darwinPublicConfigDir}/${path}";
in

{
  home.file = {
    # zsh-syntax-highlighting / fzf は per-user profile に自動統合されないため直接リンク
    ".config/zsh/plugins/zsh-syntax-highlighting".source =
      "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
    ".config/zsh/plugins/agent-switch".source = lnk "tools/agent-switch";
    ".config/zsh/fzf/key-bindings.zsh".source = "${pkgs.fzf}/share/fzf/key-bindings.zsh";
    ".gitconfig".source = lnk "git/gitconfig";
    # Homebrew のユーザー設定。全 brew 呼び出し（手打ち・スクリプト・GUI 起動を問わず）に効く。
    # 中身の説明は homebrew/brew.env のコメント参照。
    ".homebrew/brew.env".source = lnk "homebrew/brew.env";
    ".config/git/ignore".source = lnk "git/ignore";
    ".config/ghostty/config".source = lnk "ghostty/config";
    ".config/direnv/direnvrc".source = lnk "direnv/direnvrc";
    ".config/direnv/direnv.toml".source = lnk "direnv/direnv.toml";
    ".config/tmux/tmux.conf".source = lnk "tmux/tmux.conf";
    ".config/nvim/init.lua".source = lnk "nvim/init.lua";

    # Karabiner-Elements は GUI で設定変更すると karabiner.json を一時ファイル→rename で
    # 保存し直すため、ファイル単体を symlink すると symlink が実ファイルで置換され、
    # darwin-switch のたびに .bak が量産される（過去に 3385ed7 で home.file から外した経緯）。
    # 公式推奨どおり ~/.config/karabiner ディレクトリごと symlink すると、GUI 保存の rename は
    # 実体（repo/karabiner）内で完結し、GUI 編集がそのまま repo に往復する（真の双方向）。
    # 実行時ノイズ（automatic_backups/・*.bak・.DS_Store）は .gitignore で除外。
    ".config/karabiner".source = lnk "karabiner";
    ".hammerspoon/init.lua".source = lnk "hammerspoon/init.lua";
    ".hammerspoon/window_manager.lua".source = lnk "hammerspoon/window_manager.lua";
    ".hammerspoon/usb_keyboard_profile.lua".source = lnk "hammerspoon/usb_keyboard_profile.lua";
    ".hammerspoon/layouts".source = lnk "hammerspoon/layouts";
    ".config/zed/settings.json".source = lnk "zed/settings.json";
    ".config/zed/keymap.json".source = lnk "zed/keymap.json";
    ".config/zed/tasks.json".source = lnk "zed/tasks.json";
    # VSCode の設定は dotfiles を source of truth にする（settings/keybindings のみ）。
    # 拡張機能・UI State 等は VSCode の Settings Sync 側に残す（Sync 設定で「設定」
    # 「キーボードショートカット」カテゴリをオフにして二重書き込みを避ける）。
    "Library/Application Support/Code/User/settings.json".source = lnk "vscode/settings.json";
    "Library/Application Support/Code/User/keybindings.json".source = lnk "vscode/keybindings.json";
    # Zed Dev (RaTeX unofficial) は zedd() が --user-data-dir でデータを分離する。
    # config はその data dir 配下（<data>/config/）を読むため、同じ実体を張って設定だけ共有する。
    "Library/Application Support/ZedDevRaTeX/config/settings.json".source = lnk "zed/settings.json";
    "Library/Application Support/ZedDevRaTeX/config/keymap.json".source = lnk "zed/keymap.json";
    "Library/Application Support/ZedDevRaTeX/config/tasks.json".source = lnk "zed/tasks.json";
    ".config/cmux/settings.json".source = lnk "cmux/settings.json";
    ".docker/daemon.json".source = lnk "docker/daemon.json";
    ".config/gh/config.yml".source = lnk "gh/config.yml";
    ".zshenv".source = lnk "zsh/zshenv";
    ".zshrc".source = lnk "zsh/zshrc";

    # codex プラグイン（sites 等）の MCP サーバが `command: "node"` で起動されるための node。
    # 通常の PATH には載せない（node は devshell のみの方針）。agent-switch の codex()
    # ラッパーが codex 起動時だけこの dir を PATH 先頭に注入する。
    ".local/share/codex-runtime/bin/node".source = "${pkgs.nodejs}/bin/node";

    # Claude Code プラグイン（openai-codex, impeccable）の hook が `command: "node"` で
    # 起動されるための node。通常の PATH には載せない。agent-switch の claude()
    # ラッパーが claude 起動時だけこの dir を PATH 先頭に注入する。
    ".local/share/claude-runtime/bin/node".source = "${pkgs.nodejs}/bin/node";

    # Claude Code が system python（Xcode CLT の /usr/bin/python3）を無自覚に使わないための
    # ガード。claude() ラッパーが node と同様 PATH 先頭に注入する（/usr/bin より必ず先に
    # 見つかる）。優先順位の制御はPATH位置ではなくガードスクリプト自身の判定に任せる
    # （IN_NIX_SHELL なら devShell の本物の python に委譲、無ければ pyproject.toml/uv.lock の
    # 有無で uv run python に委譲するか拒否するかを決める）。
    ".local/share/claude-runtime/fallback/python3".source =
      lnk "tools/agent-switch/runtime-guards/python-guard.sh";
    ".local/share/claude-runtime/fallback/python".source =
      lnk "tools/agent-switch/runtime-guards/python-guard.sh";
  };
}
