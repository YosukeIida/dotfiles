# Yosuke の各 Mac（Mac Studio・MacBook Air）に入れる Homebrew の一覧。
# 全構成に入る最小の一覧は profiles/darwin/homebrew.nix、機種固有は mac-studio.nix / macbook-air.nix。
{
  imports = [ ../../../profiles/darwin/office.nix ];

  homebrew.extraConfig = ''
    tap "can1357/tap", trusted: true
    tap "mantrakp04/tap", trusted: true
    tap "solarphlare/tap", trusted: true
    tap "stablyai/orca", trusted: true
    tap "steipete/tap", trusted: true
    tap "xoshbin/asyar", trusted: true
    tap "yetanotherbrowser/tap", trusted: true
  '';

  homebrew.brews = [
    # homebrew-core 版は node 依存（scripts/cli.cjs の薄い dispatcher のためだけ）。
    # yosukeiida/casks-personal 版は upstream が npm optionalDependency で配布している
    # プリコンパイル済みネイティブバイナリ（darwin-arm64）を直接installし、node依存ゼロ。
    "yosukeiida/casks-personal/backlog-md"
    # RaTeX の ratex-svg（TeX の数式を SVG に）。Herdr app の activity の Markdown の数式に使う。
    # nixpkgs にも homebrew-core にも無く、公式のビルド済みの CLI を置く自前の formula で入れる。
    "yosukeiida/casks-personal/ratex"
    "brightness"
    # omp（oh my pi）。formula は release の単体バイナリを置くだけで depends_on ゼロ
    # （node/bun 非依存）。nixpkgs には無く、derivation を書いても formula と同内容に
    # なるうえ version/sha256 の手動追随が増えるため homebrew 側で管理する。
    "can1357/tap/omp"
    # hermes-agent は brew ではなく nix flake input（upstream 自身の uv2nix
    # packaging）から home.packages 経由で導入する（nix/home/packages.nix の
    # hermesAgentPkgs.full）。brew formula は node を depends_on して
    # /opt/homebrew/bin にリンクしてしまう（nodeless 方針違反）ため使わない。
    "mas"
    "opencode"
    "xcodegen"
  ];

  # Mac App Store アプリ（mas 経由）。Bitwarden は agenix バックアップ鍵の回収に必要なため
  # flake から再現する（App Store へのサインインのみ手動。README 参照）。
  homebrew.masApps = {
    Bitwarden = 1352778147;
  };

  homebrew.casks = [
    "adobe-acrobat-reader"
    "affinity"
    # tap 修飾必須、かつ **solarphlare/tap** を使うこと（solarphlare/airmute ではない）。
    # solarphlare/homebrew-airmute は GitHub 上で homebrew-tap にリネームされており、
    # 参照すると Homebrew が「Redirected tap solarphlare/airmute to tap solarphlare/tap」
    # と言ってリダイレクト先も tap するため、両方が存在して裸の "airmute" が
    # 「exists in multiple taps」で bundle 全体を止める。trusted: の宣言も
    # リダイレクト後の名前と一致せず「Untrusted tap」になる（2026-08-20 に遭遇）。
    "solarphlare/tap/airmute"
    "arc"
    "mantrakp04/tap/ardia"
    "xoshbin/asyar/asyar"
    "chatgpt"
    "chrome-remote-desktop-host"
    "claude"
    "yosukeiida/casks-personal/claude-science"
    "cloudflare-warp@beta"
    "yosukeiida/casks-personal/cra"
    "discord"
    "figma@beta"
    "ghostty@tip"
    "hammerspoon"
    # Herdr app。公式の配布は releases.herdr.dev の install.sh だけで、nixpkgs にも
    # homebrew にも無いため、同じ manifest を指す自前 cask を使う。herdr-core は brew では
    # 入れない（brew の管理下だと core が自己更新を断り、フルディスクアクセスを保つ署名も
    # できない）。導入と更新は profiles/darwin/herdr-core.nix の herdrCoreSync が受け持つ。
    # nix にしないのは、app が自分の bundle を置き換えて更新するため（store は書き込めない）。
    "yosukeiida/casks-personal/herdr-app"
    "karabiner-elements"
    "lens"
    "libreoffice"
    "nani"
    "yosukeiida/casks-personal/nimbus"
    "notion"
    "notion-calendar"
    "obs"
    "obsidian"
    "onlyoffice"
    "orbstack"
    # Orca（並列エージェントを worktree ごとに走らせる ADE）。upstream 公式 tap の cask でのみ配布されており
    # homebrew-core にも nixpkgs にも無いため tap 修飾で入れる。
    "stablyai/orca/orca"
    "yosukeiida/casks-personal/pindrop"
    "yosukeiida/casks-personal/powerglance"
    "raycast"
    "scansnap-home"
    "shottr"
    "skim"
    "slack"
    "stats"
    "tailscale-app"
    "thebrowsercompany-dia"
    "visual-studio-code"
    "wezterm@nightly"
    # yab（ブラウザ）は配布元の証明書のエラーで秘書の VM の brew bundle を止めたので、VM には入れない。
    "yetanotherbrowser/tap/yab"
    "zed"
    # 個人 fork の自前ビルドなので ad-hoc 署名（TeamIdentifier なし、spctl は rejected）で、
    # quarantine 属性が付くと Gatekeeper に起動を止められる。ただしここで
    # args = { no_quarantine = true; } は指定できない: Homebrew 6 には install 時に
    # quarantine を無効化する手段がそもそも存在しない。--no-quarantine は CLI フラグとして
    # 廃止されたうえ、HOMEBREW_CASK_OPTS 経由でも効かない（判定関数
    # EnvConfig.cask_opts_quarantine? は env_config.rb:983 に定義が残るだけで呼び出し元ゼロ。
    # cmd/install.rb:372,420 は Cask::Installer に quarantine: を渡さないため、
    # installer.rb:42 の既定値 true が常に使われる）。加えて brew bundle は args を
    # そのまま "--#{key}" に変換して渡すため（bundle/cask.rb:78-88）install 自体が失敗し、
    # upgrade 経路では args を渡さない（同 76）。対処は cask 側の postflight で
    # xattr -dr する（検証: Homebrew 6.0.12）。
    "yosukeiida/casks-personal/zed-dev-ratex"
  ];
}
