{ pkgs, ... }:

{
  imports = [ ./packages.nix ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
