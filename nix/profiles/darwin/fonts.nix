{ pkgs, lib, ... }:

let
  # Datatype: テキストをインラインチャートに変換する OpenType 可変フォント
  # {b:30,70,50} → bar chart  {l:10,40,25} → sparkline  {p:75} → pie chart
  # https://github.com/franktisellano/datatype
  datatypeFont = pkgs.stdenvNoCC.mkDerivation {
    pname = "datatype";
    version = "1.2.2";
    src = pkgs.fetchFromGitHub {
      owner = "franktisellano";
      repo = "datatype";
      rev = "v1.2.2";
      # 正しいハッシュ取得方法（初回 darwin-switch 時にエラーで表示される）:
      #   nix-prefetch-github franktisellano datatype --rev v1.2.2
      hash = "sha256-ny48VQ7etHSna4mMWEJDyztlbuI6Stuld1J6cPIeQ0c=";
    };
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm644 'fonts/variable/Datatype[wdth,wght].ttf' \
        "$out/share/fonts/truetype/Datatype[wdth,wght].ttf"
      runHook postInstall
    '';
    meta = {
      description = "Variable font that turns text into inline charts";
      homepage = "https://github.com/franktisellano/datatype";
      license = lib.licenses.ofl;
    };
  };
in
{
  fonts.packages = with pkgs; [
    datatypeFont
    (google-fonts.override {
      fonts = [
        "Hind"
        "Noto Sans JP"
        "Lato"
      ];
    })
  ];
}
