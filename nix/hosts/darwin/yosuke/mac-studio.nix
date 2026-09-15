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

  # herdr server を Aqua セッション限定で常駐させる。**この機だけ**が server を持つ
  # （2026-09-16 に yosuke/common.nix から移設）。Air でも上げると workspace / pane id が
  # 機ごとに別空間になり、intent-cli の topology がどちらの pane を指すのか決まらなくなる。
  # Air からは上の sshd 経由で `herdr --remote yosuke@mac-studio` で attach する。
  #
  # `brew services start herdr` は使わない。brew services は sudo 経由・SSH 経由
  # （HOMEBREW_SSH_TTY かつ /dev/console 非所有）・uid≠euid のいずれかを踏むと
  # gui/$UID ではなく user/$UID = Background セッションへ bootstrap する
  # （Homebrew/Library/Homebrew/services/system.rb の domain_target）。そして
  # /opt/homebrew/opt/herdr/homebrew.mxcl.herdr.plist は LimitLoadToSessionType に
  # Aqua だけでなく Background も並べているため、その user/ domain へのロードが
  # 実際に成功してしまう。Background セッションで起動した herdr server 配下の pane では
  # DNS 解決と keychain アクセスが壊れる（`launchctl managername` が Background を返す状態）。
  #
  # nix-darwin の launchd.user.agents は LimitLoadToSessionType を出力しないので既定の
  # Aqua のみでロードされ（既存 agent が gui/501 にのみ存在し user/501 には無いことを実測）、
  # この経路が構造的に塞がる。バイナリは brew 管理（homebrew.nix の brews に "herdr"）
  # なのでパスを直に指す。
  #
  # PATH を明示するのは、launchd 起動では最小 PATH になり server 自身が呼ぶ nix 側の
  # git（/etc/profiles/per-user/... にあり /usr/bin/git とは別物）を見失うため。
  # 先頭の agent-switch/shims は、herdr が自プロセスの env のまま claude/codex を直接
  # spawn する経路（login shell を経由しない）のために必要（nix/home/files.nix の shims
  # 導入の経緯。かつて hook が `node: command not found` で落ちた）。pane 内で login shell
  # を経る場合の PATH は zshenv/zprofile が再構築するのでここには依存しない。
  #
  # 注意: この agent を再起動すると稼働中の pane が全部落ちる
  # （`launchctl kickstart -k gui/$UID/com.yosuke.herdr`）。実行前に必ず確認すること。
  launchd.user.agents.herdr = {
    serviceConfig = {
      Label = "com.yosuke.herdr";
      ProgramArguments = [
        "/opt/homebrew/bin/herdr"
        "server"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables = {
        # LANG が無いと herdr が spawn する経路のクリップボード書き込みが MacRoman
        # 扱いになり、日本語のコピーが化ける（nix/home/packages.nix の LANG 参照）。
        # launchd agent は login shell を経ないので hm-session-vars では届かない。
        LANG = "en_US.UTF-8";
        PATH = "${homedir}/.local/share/agent-switch/shims:${homedir}/.nix-profile/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      StandardOutPath = "${homedir}/Library/Logs/herdr.log";
      StandardErrorPath = "${homedir}/Library/Logs/herdr.log";
    };
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
  # 落ちるので、管理下の terminal / agent が全部死ぬ。しかも KeepAlive を
  # SuccessfulExit = false にしてあるため、Cmd+Q（正常終了）からは復活しない
  # ── 意図した終了として尊重する。閉じたいだけならウィンドウを閉じる（赤ボタン）。
  # 常駐に戻すときは `launchctl kickstart gui/$UID/com.yosuke.orca-app`
  # （pairing 状態は orca-data.json に永続化されているので再ペアリングは不要）。
  #
  # 注意（導入順）: 素の Orca.app が既に起動していると単一インスタンスロックを先に
  # 取られ、launchd 側の Orca は「既存ウィンドウを前面に出して自分は exit 0 で抜ける」
  # という second-instance の作法で終了する。darwin-switch の前に Orca.app を
  # 終了しておくこと。
  launchd.user.agents.orcaApp = {
    serviceConfig = {
      Label = "com.yosuke.orca-app";
      ProgramArguments = [ "/Applications/Orca.app/Contents/MacOS/Orca" ];
      RunAtLoad = true;
      # exit 0 は再起動対象から外し、クラッシュ（exit != 0）だけを復帰させる。
      # KeepAlive = true だと上の single-instance 退出（exit 0）まで再起動してしまい、
      # 「前面化 → exit 0 → 再起動」が数秒周期で回るループになった
      # （2026-09-01 に Studio で発生、runs=56 / ログは ~/Library/Logs/orca-app.log）。
      KeepAlive = { SuccessfulExit = false; };
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
