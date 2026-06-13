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
    python3Packages.twscrape
    rclone
    tmux
    tree
    zsh-autosuggestions
    zsh-syntax-highlighting
  ];
}
