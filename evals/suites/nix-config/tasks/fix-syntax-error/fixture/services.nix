{
  services = {
    yabai = {
      enable = true
      extraConfig = "yabai -m config layout bsp";
    };
    skhd = {
      enable = true;
      keybindings = [
        "alt - return : open -a Ghostty"
        "alt - b : open -a 'Google Chrome'"
      ];
    };
    sketchybar.enable = false;
  };
}
