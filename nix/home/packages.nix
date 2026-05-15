{ pkgs, ... }:

{
  home.packages = with pkgs; [
    cloudflared
    duti
    fzf
    gh
    ghq
    lazydocker
    lazygit
    neovim
    poppler
    rclone
    tmux
    tree
    zsh-autosuggestions
    zsh-syntax-highlighting
  ];
}
