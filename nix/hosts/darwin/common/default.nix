{
  username ? "user",
  homedir ? "/Users/${username}",
  ...
}:

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
}
