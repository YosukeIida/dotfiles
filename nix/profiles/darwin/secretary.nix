# OpenClaw 秘書を閉じ込める Lume の macOS VM だけの層（flake.nix の darwinConfigurations.secretary）。
# 設計は dotfiles-private の docs/2026-11-06_homebrew-layers-and-secretary-apps.md。
{
  username,
  homedir,
  privateDir,
}:
{
  imports = [
    ./office.nix
    # 秘書の作業者を herdr-core の端末で起こし、ホストの Herdr app から見て介入するため。
    (import ./herdr-core.nix { inherit username homedir privateDir; })
  ];

  homebrew.brews = [
    # OpenClaw の GitHub 接続（tools.github）は Gateway の PATH から gh を探す。Gateway の LaunchAgent の
    # PATH は /opt/homebrew/bin までで、nix の gh（/etc/profiles/per-user/lume/bin）は見えないので brew でも入れる。
    "gh"
  ];

  homebrew.casks = [
    # Yosuke が VNC で VM の画面を見るときに使う。OpenClaw 自体は API とブラウザで扱う。
    "discord"
    "slack"
    # OpenClaw 同梱の skill obsidian が公式の CLI で vault を扱う。
    "obsidian"
    # computer use（組み込みの computer ツール）は、macOS では OpenClaw.app が画面の操作を受け持つ
    # （同梱の docs/nodes/computer-use.md）。plugin の cua-computer は Windows と Linux 向けで、macOS では使えない。
    "openclaw"
  ];
}
