{
  pkgs,
  darwinPublicConfigDir,
  ...
}:

{
  imports = [
    ./packages.nix
    ./files.nix
  ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
