{
  username,
  homedir,
  ...
}:

{
  home.username = username;
  home.homeDirectory = homedir;
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
