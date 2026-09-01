# Yosukes-Mac-Studio 固有設定（研究室に据え置く常設機）。
#
# 持ち歩かない前提なので、Air とは逆に「常に起きていて、いつでも入れる」方向に倒す。
# 蓋がないため sleepctl 一式（macbook-air.nix）は入れない。
#
# ここに無いもの / 意図的に入れていないもの:
# - FileVault: nix からは強制できない。agenix の復号鍵 ~/.ssh/id_ed25519 は mode 600 の
#   平文で、at-rest 保護は FileVault 依存（yosuke/secrets.nix 冒頭を参照）。研究室は
#   他人が物理アクセスしうるので、初回セットアップ時に手動で有効化を確認すること。
# - リモートログイン(SSH): 必要になってから足す。開けっ放しにはしない。
#
# HF_HOME（HuggingFace のモデルキャッシュ）を外付けへ移すなら、この機の設定として
# `home-manager.users.yosuke.home.sessionVariables.HF_HOME = "...";` を素の値で書く。
# 既定は yosuke/common.nix が mkDefault で与えているので、そのまま上書きされる。
{ ... }:

let
  username = "yosuke";
  homedir = "/Users/${username}";
in

{
  # omlx（jundot/omlx）は formula の upgrade/ビルドが重く、持ち歩く Air には不要なため
  # Studio 専用インストールにする（profiles/darwin/homebrew.nix は両機共通の一覧）。
  homebrew.extraConfig = ''
    tap "jundot/omlx", "https://github.com/jundot/omlx", trusted: true
  '';
  homebrew.brews = [ "jundot/omlx/omlx" ];

  # 常設機なので寝かせない。ディスプレイだけは離席時に消す。
  power = {
    sleep = {
      computer = "never";
      display = 15;
      harddisk = "never";
    };
    # 研究室は停電・ブレーカー落ちがありうる。復電したら自動で戻す。
    restartAfterPowerFailure = true;
  };

  # 共用スペースに置くので、離席時のロックは Air より短くする。
  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 60;
  };

  # Air から `herdr --remote ${username}@<この機の tailnet アドレス>` で attach するための
  # sshd。アドレスは `tailscale ip -4` で引く（この repo には書かない）。
  # 常設機なのでこちらだけがサーバーになる（Air 側では開けない）。
  #
  # nix-darwin の services.openssh は activation で launchctl enable +
  # launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist を行うので、
  # darwin-switch だけでリモートログインが有効になる（モジュール側が
  # `systemsetup -setremotelogin` を避けているのは Full Disk Access を要求するため）。
  #
  # tailnet 限定にするのに ListenAddress は使えない。ssh.plist は Sockets
  # （SockServiceName = ssh）による launchd socket activation で bind は launchd が
  # 所有し、sshd_config の ListenAddress は無視される。代わりに Match Address で
  # tailnet 以外からの接続を全部落とす。共用スペースの機なので、少なくとも
  # 研究室 LAN や外からは触らせない。
  #
  # 公開鍵は Air から ssh-copy-id で登録済み（2026-08-21）。パスワード認証は閉じる。
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no

      Match Address *,!100.64.0.0/10
        DenyUsers *
    '';
  };

  # Orca の runtime を launchd が所有する。GUI（Orca.app）は「別のクライアント」ではなく、
  # この同じプロセスがウィンドウを開いたものになる。単一インスタンスロックが GUI 起動を
  # 既存プロセスへの second-instance イベントとして配送し、
  # shouldActivateDesktopForSecondInstance → desktopActivationGate →
  # focusExistingMainWindow(openWindow) がウィンドウを開く経路（app.asar の main を読んで
  # 確認、`open -a Orca` しても pid が変わらないことを実測）。つまりウィンドウを閉じても
  # runtime は生き続ける。
  #
  # 以前は `--serve --serve-pairing-address <tailnet-ip>` で headless runtime server として
  # 起動していたが、2点の理由でやめて素のデスクトップアプリ起動に変えた
  # （2026-09-01、実機確認済み）:
  #
  # 1. Orca 公式ドキュメント（https://www.onorca.dev/docs/remote-servers）は
  #    `--serve` を「headless Linux server / VM 向け」と位置づけており、Mac のような
  #    常設デスクトップ機には「デスクトップアプリを起動したままにして
  #    Settings → Remote Orca Servers → Advertise this app as a server で
  #    access link を発行する」方式を推奨している。
  # 2. 実測で `--serve` 経路は Tailscale 到達性のある LAN/tailnet 内でしかペアリング
  #    できず、公式の relay server 経由の接続（スマホがモバイル回線のみでもバック
  #    グラウンド通知が届く）が機能しなかった。素のデスクトップアプリ経由の
  #    access link ならこの relay 経由の接続も機能することを確認した。
  #
  # なお `orca serve`（公式 CLI）を使わず Electron を直接叩いているのは、
  # Orca 1.4.192 の macOS で `orca serve` が起動時に必ず落ちるバグの回避のため
  # （CLI が packaged app に ORCA_SERVE_UPDATE_HANDOFF_PATH を常に渡し、
  # setAppEnvironment() より前に getCanonicalUserDataPath() が走って
  # "AppEnvironment not initialized" で落ちる）。素のデスクトップアプリ起動には
  # このバグ自体が関係ない（`orca serve` を経由しないため）が、Electron 直叩きの
  # ままにして起動経路を単純に保っている。upstream が直ったら `open -a Orca` や
  # `orca open` に切り替えてもよい。
  #
  # 初回セットアップ: darwin-switch 後、Studio の画面で Orca を開き、
  # Settings → Remote Orca Servers → Share this host → Advertise this app as a
  # server → Connection address に Tailscale アドレスを選んで Generate Access Link。
  # この access link は Orca 側のミュータブルな状態（orca-data.json）に保存されるので
  # nix には焼き込めない。Air・スマホからはこの link で pair する。
  #
  # 注意（herdr の kickstart と同じ性質）: このウィンドウで Cmd+Q すると runtime ごと
  # 落ちるので、管理下の terminal / agent が全部死ぬ。KeepAlive で新しい runtime が
  # 起動し直すだけで、走っていた agent セッションは戻らない（pairing 状態は
  # orca-data.json に永続化されているので再ペアリングは不要）。閉じたいだけなら
  # ウィンドウを閉じる（赤ボタン）。
  #
  # 注意（導入順）: 素の Orca.app が既に起動していると単一インスタンスロックを先に
  # 取られ、launchd 側が exit 1 で落ちて KeepAlive のリトライループになる。
  # darwin-switch の前に Orca.app を終了しておくこと。
  launchd.user.agents.orcaApp = {
    serviceConfig = {
      Label = "com.yosuke.orca-app";
      ProgramArguments = [ "/Applications/Orca.app/Contents/MacOS/Orca" ];
      RunAtLoad = true;
      KeepAlive = true;
      # 以前の `orca serve` 相当の起動が cwd を app root に固定していたのに倣う
      # （Electron のリソース解決が process.cwd() を見る経路があるため）。
      WorkingDirectory = "/Applications/Orca.app/Contents/Resources/app.asar.unpacked";
      EnvironmentVariables = {
        # herdr と同じ理由。launchd agent は login shell を経ないので hm-session-vars が
        # 届かず、LANG が無いと Orca 配下で spawn した経路の日本語が MacRoman 化する。
        LANG = "en_US.UTF-8";
        # 同じく herdr と同じ理由。Orca は agent（claude / codex）と git を自分で spawn
        # するので、launchd の最小 PATH のままだと nix 側の git や node を見失う。
        PATH = "${homedir}/.local/share/agent-switch/shims:${homedir}/.nix-profile/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      StandardOutPath = "${homedir}/Library/Logs/orca-app.log";
      StandardErrorPath = "${homedir}/Library/Logs/orca-app.log";
    };
  };
}
