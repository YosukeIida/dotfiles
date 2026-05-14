{
  config,
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
    ".config/zsh/fzf/key-bindings.zsh".source =
      "${pkgs.fzf}/share/fzf/key-bindings.zsh";
    ".gitconfig".source = lnk "git/gitconfig";
    ".config/git/ignore".source = lnk "git/ignore";
    ".config/ghostty/config".source = lnk "ghostty/config";
    ".config/direnv/direnvrc".source = lnk "direnv/direnvrc";
    ".config/tmux/tmux.conf".source = lnk "tmux/tmux.conf";
    ".config/nvim/init.lua".source = lnk "nvim/init.lua";
    ".hammerspoon/init.lua".source = lnk "hammerspoon/init.lua";
    ".hammerspoon/window_manager.lua".source = lnk "hammerspoon/window_manager.lua";
    ".hammerspoon/layouts".source = lnk "hammerspoon/layouts";
    ".config/zed/settings.json".source = lnk "zed/settings.json";
    ".config/zed/keymap.json".source = lnk "zed/keymap.json";
    ".config/cmux/settings.json".source = lnk "cmux/settings.json";
    ".config/gh/config.yml".source = lnk "gh/config.yml";
    ".config/karabiner/karabiner.json".source = lnk "karabiner/karabiner.json";
    ".config/karabiner/assets/complex_modifications/dodo.json".source =
      lnk "karabiner/assets/complex_modifications/dodo.json";
    ".zshenv".source = lnk "zsh/zshenv";
    ".zshrc".source = lnk "zsh/zshrc";
  };
}
