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
    ".config/zsh/plugins/agent-switch".source = lnk "tools/agent-switch";
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
    ".hammerspoon/usb_keyboard_profile.lua".source = lnk "hammerspoon/usb_keyboard_profile.lua";
    ".hammerspoon/layouts".source = lnk "hammerspoon/layouts";
    ".config/zed/settings.json".source = lnk "zed/settings.json";
    ".config/zed/keymap.json".source = lnk "zed/keymap.json";
    ".config/zed/tasks.json".source = lnk "zed/tasks.json";
    ".config/cmux/settings.json".source = lnk "cmux/settings.json";
    ".docker/daemon.json".source = lnk "docker/daemon.json";
    ".config/gh/config.yml".source = lnk "gh/config.yml";
    ".zshenv".source = lnk "zsh/zshenv";
    ".zshrc".source = lnk "zsh/zshrc";
    ".homebrew/trust.json".text = builtins.toJSON {
      trustedtaps = [
        "https://github.com/jundot/omlx"
        "solarphlare/airmute"
        "steipete/tap"
        "yosukeiida/nimbus"
        "yosukeiida/pindrop"
      ];
    };
  };
}
