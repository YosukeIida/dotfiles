{ pkgs, lib, pkgsUnstable, ... }:

let
  # nixpkgs に未収録のため self-contained release binary を fetchurl で取り込む。
  # dotnet SDK は入れず、`dotnet tool install -g` 相当のグローバル状態管理外インストールを避ける。
  # 更新時は https://github.com/J-Tech-Japan/intent-system/releases から
  # version と osx-arm64 tarball の sha256 を手で更新する。
  intent-cli = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "intent-cli";
    version = "0.31.0";
    src = pkgs.fetchurl {
      url = "https://github.com/J-Tech-Japan/intent-system/releases/download/v${version}/intent-cli-${version}-osx-arm64.tar.gz";
      sha256 = "a2384fdcc2f2c8f7b9cc0d6f47b2ecefb49f3bad44cd51c0ebead0d0c7644b36";
    };
    # tarball の中身は単一バイナリ（ディレクトリなし）なので、stdenv の
    # デフォルト unpackPhase の sourceRoot 自動推定（ディレクトリ前提）が失敗する。
    unpackPhase = "tar xzf $src";
    installPhase = ''
      mkdir -p $out/bin
      install -m755 intent-cli $out/bin/intent-cli
    '';
  };

  # 日本語文章の AI 臭（LLM常套句・翻訳調・リズムの均質化）を決定的に検出する linter。
  # nixpkgs に未収録のため intent-cli と同じく release binary を fetchurl で取り込む。
  # style-notes skill（dotfiles-private）と Claude Code の PostToolUse hook
  # （claude/hooks/suiko-lint.sh）が使う。更新時は
  # https://github.com/nwiizo/suiko/releases から version と
  # aarch64-apple-darwin tarball の sha256 を手で更新する。
  suiko = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "suiko";
    version = "0.3.3";
    src = pkgs.fetchurl {
      url = "https://github.com/nwiizo/suiko/releases/download/v${version}/suiko-v${version}-aarch64-apple-darwin.tar.gz";
      sha256 = "8aa913f79b4f812a9c0360f7f0a1a47d4aca80fd403c909df10daddef7f01677";
    };
    # tarball は suiko-v<version>-aarch64-apple-darwin/ ディレクトリ入りなので
    # デフォルトの unpackPhase がそのまま使える（intent-cli とは違う）。
    installPhase = ''
      mkdir -p $out/bin
      install -m755 suiko $out/bin/suiko
    '';
  };

  # nixpkgs に未収録。NUTFes の nutmeg Slack workspace 用 MCP サーバー
  # （user scope で登録し全リポジトリから使えるようにする、bot token 限定運用
  # — invited channels のみ・search.messages 不可）。更新時は
  # https://github.com/korotovsky/slack-mcp-server/releases から
  # version と darwin-arm64 の sha256 を手で更新する。
  slack-mcp-server-nutmeg-bin = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "slack-mcp-server-nutmeg-bin";
    version = "1.3.0";
    src = pkgs.fetchurl {
      url = "https://github.com/korotovsky/slack-mcp-server/releases/download/v${version}/slack-mcp-server-darwin-arm64";
      sha256 = "04jkhmki2fvs8k7810383mqpbysam9idhkbhxlw389985rfalfg8";
    };
    # 単一バイナリの直配布（tarball ではない）ので unpack をスキップする。
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      install -m755 $src $out/bin/slack-mcp-server-nutmeg-bin
    '';
  };

  # token を .mcp.json に直書きしないためのラッパー。agenix 管理の
  # $HOME/.config/slack-mcp/nutmeg-token.env（common.nix の _place で配置）を
  # 起動時に読み込んでから本体を exec する。
  slack-mcp-server-nutmeg = pkgs.writeShellScriptBin "slack-mcp-server-nutmeg" ''
    set -a
    [ -f "$HOME/.config/slack-mcp/nutmeg-token.env" ] && . "$HOME/.config/slack-mcp/nutmeg-token.env"
    set +a
    exec ${slack-mcp-server-nutmeg-bin}/bin/slack-mcp-server-nutmeg-bin "$@"
  '';

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
    suiko
    tmux
    tree
    uv
    zig
    zsh-autosuggestions
    zsh-syntax-highlighting
    figma-console-mcp
    slack-mcp-server-nutmeg
    # nixpkgs-25.11-darwin（stable）には未収録（新規パッケージは stable に
    # バックポートされない）ため、nixpkgs-unstable から個別に引く。
    pkgsUnstable.agent-browser
  ];

  home.sessionVariables = {
    # macOS は LANG 未設定だと「システム標準エンコーディング」を MacRoman と解釈する
    # （CFStringGetSystemEncoding の既定）。この状態で pbcopy 等を経由すると UTF-8 の
    # バイト列が1バイトずつ MacRoman として読み直され、「なのです」→「„Å™„ÅÆ„Åß„Åô」の
    # 形に化ける（2026-08-24 に Mac Studio で再発、iconv -f MACROMAN で再現確認）。
    # ja_JP ではなく en_US にするのは、ツールのメッセージを英語のまま保ち、英語出力を
    # 前提にしたスクリプトを壊さないため（必要なのは文字コードだけ）。
    # これはシェル経路の分。GUI アプリ・launchd 経路は host 層の
    # launchd.user.envVariables と herdr agent の plist で別途設定する。
    LANG = "en_US.UTF-8";
    # gws-multi-account skill（agents/skills/gws-multi-account/、vendor元は
    # indentcorp/gws-multi-account）の PreToolUse hook（hooks/hook.js）と、
    # SKILL.md 内の accounts.json 更新スニペットが使う。nodeless-policy
    # （裸の node を PATH に常駐させない）のため、nix pin 済みの node を
    # この専用変数経由でだけ触れるようにしている。
    GWS_MULTI_ACCOUNT_NODE = "${pkgs.nodejs_22}/bin/node";
    # agent-browser は headed（通常ウィンドウ・ハードウェア GPU）で起動する。
    # headless だと swiftshader（CPU での GPU エミュレーション）で描画され、
    # 閉じ忘れた放置ページが数コアを焼き続ける事故が起きた（2026-08-03〜06）。
    AGENT_BROWSER_HEADED = "1";
    # 閉じ忘れ保険: 30分アイドルでデーモンごと Chrome を自動終了する（実測で動作確認済み）。
    AGENT_BROWSER_IDLE_TIMEOUT_MS = "1800000";
    # HF_HOME は機ごとに置き場所が変わりうるので、ここ（他人も fork して使う共通層）
    # ではなく nix/hosts/darwin/yosuke/common.nix に置いてある。
  };

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
