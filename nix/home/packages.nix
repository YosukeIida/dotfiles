{ pkgs, ... }:

{
  home.packages = with pkgs; [
    cloudflared
    colima
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
