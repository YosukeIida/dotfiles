{ pkgs, ... }:

{
  fonts.packages = with pkgs; [
    (google-fonts.override {
      fonts = [
        "Hind"
        "Noto Sans JP"
        "Lato"
      ];
    })
  ];
}
