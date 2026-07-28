{ pkgs, lib, ... }:

let
  figma-console-mcp = pkgs.buildNpmPackage {
    pname = "figma-console-mcp";
    version = "1.32.0";
    src = pkgs.fetchFromGitHub {
      owner = "southleft";
      repo = "figma-console-mcp";
      rev = "v1.32.0";
      hash = "sha256-+KQOIMELCFFUu/9KaMgMELR9EySfir7dGE15iQ5O5kw=";
    };
    npmDepsHash = "sha256-XWjwh5NPWRhUALMv8heDZ6XjovlCBX9XSC+o2/L9Z2A=";
    # full build includes wrangler (cloudflare) and vite apps; local-only needs only tsc
    buildPhase = "npm run build:local";
  };
in

{
  home.packages = with pkgs; [
    age
    agent-browser
    cloudflared
    duti
    fzf
    gh
    git
    ghq
    # jq: git clean filter（strip-model）と agent-switch の agsw-codex-identity が使う。
    # macOS 同梱の /usr/bin/jq に依存すると OS バージョンで挙動が変わるので nix で固定する。
    jq
    lazydocker
    lazygit
    neovim
    poppler
    python3Packages.twscrape
    rclone
    tmux
    tree
    uv
    zsh-autosuggestions
    zsh-syntax-highlighting
    figma-console-mcp
  ];

  home.sessionVariables = {
    AGMSG_NODE = "${pkgs.nodejs_22}/bin/node";
  };

  home.sessionPath = [ "$HOME/.agents/bin" ];

  # figma-console-mcp の Desktop Bridge プラグインを安定パスへ実体コピーする。
  # Figma はここ（~/.figma-plugins/figma-desktop-bridge/manifest.json）から一度 import すれば、
  # figma-console-mcp が再ビルドされて /nix/store のハッシュが変わっても再 import 不要
  # （中身は darwin-switch のたびにこの activation が更新する）。
  # symlink だと Figma の import ダイアログが実体解決して /nix/store に戻るため、cp で実体コピーする。
  home.activation.figmaConsoleBridge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rm -rf "$HOME/.figma-plugins/figma-desktop-bridge"
    install -d "$HOME/.figma-plugins"
    cp -rL "${figma-console-mcp}/lib/node_modules/figma-console-mcp/figma-desktop-bridge" \
           "$HOME/.figma-plugins/"
    chmod -R u+w "$HOME/.figma-plugins/figma-desktop-bridge"
  '';
}
