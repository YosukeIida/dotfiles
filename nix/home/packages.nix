{ pkgs, lib, pkgsUnstable, ... }:

let
  # nixpkgs に未収録のため self-contained release binary を fetchurl で取り込む。
  # dotnet SDK は入れず、`dotnet tool install -g` 相当のグローバル状態管理外インストールを避ける。
  # 更新時は https://github.com/J-Tech-Japan/intent-system/releases から
  # version と osx-arm64 tarball の sha256 を手で更新する。
  intent-cli = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "intent-cli";
    version = "0.22.0";
    src = pkgs.fetchurl {
      url = "https://github.com/J-Tech-Japan/intent-system/releases/download/v${version}/intent-cli-${version}-osx-arm64.tar.gz";
      sha256 = "5e1684af3f020ac5c7eb2c845f53bb9e069b6e8198c49507ac8d3fe3cb59ddf0";
    };
    # tarball の中身は単一バイナリ（ディレクトリなし）なので、stdenv の
    # デフォルト unpackPhase の sourceRoot 自動推定（ディレクトリ前提）が失敗する。
    unpackPhase = "tar xzf $src";
    installPhase = ''
      mkdir -p $out/bin
      install -m755 intent-cli $out/bin/intent-cli
    '';
  };

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
    bun
    cloudflared
    duti
    fzf
    gh
    git
    ghq
    intent-cli
    # jq: git clean filter（strip-model）と agent-switch の agsw-codex-identity が使う。
    # macOS 同梱の /usr/bin/jq に依存すると OS バージョンで挙動が変わるので nix で固定する。
    jq
    lazydocker
    lazygit
    neovim
    poppler
    python3Packages.twscrape
    rclone
    rustup
    tmux
    tree
    uv
    zig
    zsh-autosuggestions
    zsh-syntax-highlighting
    figma-console-mcp
    # nixpkgs-25.11-darwin（stable）には未収録（新規パッケージは stable に
    # バックポートされない）ため、nixpkgs-unstable から個別に引く。
    pkgsUnstable.agent-browser
  ];

  home.sessionVariables = {
    AGMSG_NODE = "${pkgs.nodejs_22}/bin/node";
    # gws-multi-account skill（agents/skills/gws-multi-account/、vendor元は
    # indentcorp/gws-multi-account）の PreToolUse hook（hooks/hook.js）と、
    # SKILL.md 内の accounts.json 更新スニペットが使う。AGMSG_NODE と同じ理由
    # （nodeless-policy: 裸の node を PATH に常駐させない）で、nix pin 済みの
    # node をこの専用変数経由でだけ触れるようにしている。
    GWS_MULTI_ACCOUNT_NODE = "${pkgs.nodejs_22}/bin/node";
    # agent-browser は headed（通常ウィンドウ・ハードウェア GPU）で起動する。
    # headless だと swiftshader（CPU での GPU エミュレーション）で描画され、
    # 閉じ忘れた放置ページが数コアを焼き続ける事故が起きた（2026-08-03〜06）。
    AGENT_BROWSER_HEADED = "1";
    # 閉じ忘れ保険: 30分アイドルでデーモンごと Chrome を自動終了する（実測で動作確認済み）。
    AGENT_BROWSER_IDLE_TIMEOUT_MS = "1800000";
    # agmsg の codex shim（~/.agents/bin/codex）に実体を直指しさせ、PATH 走査を止める。
    # 走査させると cmux が panel ごとに $TMPDIR/cmux-cli-shims/<panel-id>/ へ生成する
    # codex shim を「実体」と誤認する。cmux 側の wrapper も逆に agmsg shim を「実体」と
    # 判定するため、両者が互いを exec し合って無限再帰し、codex が起動しなくなる
    # （2026-08-13 に cmux 0.64.22 × agmsg 1.1.6 で実測。herdr では cmux の per-panel
    # shim が無いので発生しない）。本質は agmsg の resolve_real_codex が他社製 wrapper を
    # 除外できていない点で、upstream 修正が入ればこの pin は不要になる。
    AGMSG_REAL_CODEX = "/opt/homebrew/bin/codex";
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
