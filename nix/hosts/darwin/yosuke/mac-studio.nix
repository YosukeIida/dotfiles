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
{ pkgs, ... }:

let
  username = "yosuke";
  homedir = "/Users/${username}";

  # tailnet のアドレスは repo に書かず、起動のたびに引く。ログイン直後でまだ無ければ失敗し、launchd が入り直させる。
  # 研究室の tailnet には他人の端末もいるので、iPhone のアドレス（agenix の secretary-phone-ip）以外は受けた直後に切る。
  secretaryGatewayTailnetTunnel = pkgs.writeShellScriptBin "secretary-gateway-tailnet-tunnel" ''
    ip="$(/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4 2>/dev/null | /usr/bin/head -n1)"
    [ -n "$ip" ] || { echo "tailnet のアドレスがまだ無い" >&2; exit 1; }
    phone="$(tr -d '[:space:]' < "${homedir}/.config/vpn/secretary-phone-ip")"
    [ -n "$phone" ] || { echo "iPhone のアドレスが無い（agenix の secretary-phone-ip）" >&2; exit 1; }
    exec ${pkgs.socat}/bin/socat \
      "TCP-LISTEN:18789,bind=$ip,fork,reuseaddr,range=$phone/32" \
      TCP:127.0.0.1:18789
  '';
in

{
  # omlx（jundot/omlx）は formula の upgrade/ビルドが重く、持ち歩く Air には不要なため
  # Studio 専用インストールにする（profiles/darwin/homebrew.nix は両機共通の一覧）。
  homebrew.extraConfig = ''
    tap "jundot/omlx", "https://github.com/jundot/omlx", trusted: true
  '';
  homebrew.brews = [ "jundot/omlx/omlx" ];

  # HuggingFace のキャッシュ（モデル・データセット）を外付け SSD（PRO-G40, 4TB）に置く。
  # 既定は yosuke/common.nix の mkDefault（~/.cache/huggingface）で、ここで素の値で上書きする。
  # ディスク未接続時はこのパスが存在せず、ロードもダウンロードも失敗する。
  home-manager.users.${username}.home.sessionVariables.HF_HOME = "/Volumes/PRO-G40/huggingface";

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

  # Air から SSH で入るための sshd（Herdr app の Machines もこれで Studio につなぐ）。
  # アドレスは `tailscale ip -4` で引く（この repo には書かない）。
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

  # OpenClaw 秘書を閉じ込めた Lume の macOS VM（darwinConfigurations.secretary を適用したもの。
  # 設計は dotfiles-private の docs/2026-10-02_secretary-agent-base-selection.md）を常駐させる。
  # `lume run` は --detach を付けなければ VM が動いている間フォアグラウンドに留まり、VM が止まると
  # 終了するので、KeepAlive で止まったら起動し直す。画面は VNC（画面共有）で見る。ネイティブの画面
  # （`lume attach`）を付けたあとに VM が止まることが2回あった（2026-10-02、原因は未確定）。
  # 意図して止めるときは `launchctl bootout gui/$UID/com.yosuke.secretary-vm`（`lume stop` だけだと
  # KeepAlive がすぐ起動し直す）。
  # 経験知（dotfiles-private/experience）と knowledge を読み取り専用で共有し、秘書の記憶の検索に載せる
  # （VM 内では /Volumes/My Shared Files/ の下に見える。秘書側の設定は dotfiles-private の secretary/）。
  launchd.user.agents.secretaryVm = {
    serviceConfig = {
      Label = "com.yosuke.secretary-vm";
      ProgramArguments = [
        "/opt/homebrew/bin/lume"
        "run"
        "secretary"
        "--no-display"
        "--shared-dir"
        "${homedir}/workspace/github.com/YosukeIida/dotfiles-private/experience:ro"
        "--shared-dir"
        "${homedir}/workspace/github.com/YosukeIida/knowledge:ro"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables.LUME_TELEMETRY_ENABLED = "false";
      StandardOutPath = "${homedir}/Library/Logs/secretary-vm.log";
      StandardErrorPath = "${homedir}/Library/Logs/secretary-vm.log";
    };
  };

  # 秘書の OpenClaw のダッシュボード（VM の中の 127.0.0.1:18789 でだけ待ち受ける）を、Mac Studio の
  # http://127.0.0.1:18789 で開けるように SSH のトンネルを常駐させる。外には開かない（両端とも loopback）。
  # 18790 は、ダッシュボードの HTML の部品を読み込む sandbox の口（Control UI が部品の iframe をここから開く）。
  # MacBook Air（macbook-air.nix）は、この Mac Studio 側の 18789・18790 へ SSH でさらにつなぐ。
  # 鍵で入る（~/.ssh/id_ed25519.pub を VM の ~/.ssh/authorized_keys に登録しておく）。VM の IP は Lume の NAT の
  # 既定（lume ls の 192.168.64.2）。VM が止まっている間は接続に失敗して、ThrottleInterval ごとに入り直す。
  # 16768 は VM の Orca の実行環境（6768）への転送。Mac Studio の Orca に environment「secretary-vm」として
  # ws://127.0.0.1:16768 で登録してある（Orca.app は VM の IP に直接つながらなかったので loopback を通す）。
  launchd.user.agents.secretaryDashboardTunnel = {
    serviceConfig = {
      Label = "com.yosuke.secretary-dashboard-tunnel";
      ProgramArguments = [
        "/usr/bin/ssh"
        "-N"
        "-o"
        "BatchMode=yes"
        "-o"
        "StrictHostKeyChecking=accept-new"
        "-o"
        "ExitOnForwardFailure=yes"
        "-o"
        "ServerAliveInterval=30"
        "-o"
        "ServerAliveCountMax=3"
        "-L"
        "127.0.0.1:18789:127.0.0.1:18789"
        "-L"
        "127.0.0.1:18790:127.0.0.1:18790"
        "-L"
        "127.0.0.1:16768:127.0.0.1:6768"
        "lume@192.168.64.2"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "${homedir}/Library/Logs/secretary-dashboard-tunnel.log";
      StandardErrorPath = "${homedir}/Library/Logs/secretary-dashboard-tunnel.log";
    };
  };

  # 秘書の Gateway を、この機の tailnet のアドレスの 18789 で iPhone の OpenClaw アプリに出す（wss。TLS は Gateway が終端する）。
  # 上のダッシュボードのトンネル（127.0.0.1:18789）へ socat で渡す。ssh -L を tailnet のアドレスで待ち受けないのは、
  # 接続元で絞れず、研究室の誰の接続も Gateway には 127.0.0.1 に見えるため。Caddy で X-Forwarded-For を渡す形
  # （docs/2026-10-05_secretary-dashboard-remote-access.md）を採らないのは、iPhone 1 台なら接続元の絞り込みで足りるため。
  # Tailscale Serve を使わないのは、研究室の headscale が端末の証明書を出さないため（docs/2026-10-27_openclaw-ios-pairing.md）。
  # 2 つの docs は dotfiles-private にある。
  launchd.user.agents.secretaryGatewayTailnetTunnel = {
    serviceConfig = {
      Label = "com.yosuke.secretary-gateway-tailnet-tunnel";
      ProgramArguments = [ "${secretaryGatewayTailnetTunnel}/bin/secretary-gateway-tailnet-tunnel" ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "${homedir}/Library/Logs/secretary-gateway-tailnet-tunnel.log";
      StandardErrorPath = "${homedir}/Library/Logs/secretary-gateway-tailnet-tunnel.log";
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
  # 注意: このウィンドウで Cmd+Q すると runtime ごと
  # 落ちるので、管理下の terminal / agent が全部死ぬ。しかも KeepAlive を
  # Crashed = true にしてあるため、Cmd+Q（正常終了）からは復活しない
  # ── 意図した終了として尊重する。閉じたいだけならウィンドウを閉じる（赤ボタン）。
  # 常駐に戻すときは `launchctl kickstart gui/$UID/com.yosuke.orca-app`
  # （pairing 状態は orca-data.json に永続化されているので再ペアリングは不要）。
  #
  # 注意（導入順）: 素の Orca.app が既に起動していると単一インスタンスロックを先に
  # 取られ、launchd 側の Orca は「既存ウィンドウを前面に出して自分は exit 3 で抜ける」
  # という second-instance の作法で終了する。darwin-switch の前に Orca.app を
  # 終了しておくこと。
  launchd.user.agents.orcaApp = {
    serviceConfig = {
      Label = "com.yosuke.orca-app";
      ProgramArguments = [ "/Applications/Orca.app/Contents/MacOS/Orca" ];
      RunAtLoad = true;
      # シグナルで落ちたクラッシュだけを復帰させ、終了コードでは判定しない。
      # single-instance 退出は「既存ウィンドウを前面化して exit」なので、これを再起動すると
      # 「前面化 → exit → 再起動」が ThrottleInterval（10 秒）周期で回るループになる。
      # KeepAlive = true では exit 0 で（2026-09-01、runs=56）、SuccessfulExit = false では
      # Orca がこの退出を exit 3 に変えた後に（2026-09-30、runs=185）発生した。
      KeepAlive = { Crashed = true; };
      # 以前の `orca serve` 相当の起動が cwd を app root に固定していたのに倣う
      # （Electron のリソース解決が process.cwd() を見る経路があるため）。
      WorkingDirectory = "/Applications/Orca.app/Contents/Resources/app.asar.unpacked";
      EnvironmentVariables = {
        # launchd agent は login shell を経ないので hm-session-vars が届かず、LANG が
        # 無いと Orca 配下で spawn した経路の日本語が MacRoman 化する。
        LANG = "en_US.UTF-8";
        # Orca は agent（claude / codex）と git を自分で spawn するので、launchd の
        # 最小 PATH のままだと nix 側の git や node を見失う。先頭の agent-switch/shims は、
        # login shell を経ずに spawn された claude / codex にも node の PATH を通すため。
        PATH = "${homedir}/.local/share/agent-switch/shims:${homedir}/.nix-profile/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      StandardOutPath = "${homedir}/Library/Logs/orca-app.log";
      StandardErrorPath = "${homedir}/Library/Logs/orca-app.log";
    };
  };

  # darwin-switch のたびに Orca を launchd の管理下に置く。RunAtLoad は plist が
  # 変わって読み直されたときしか走らないので、Cmd+Q 後などジョブが止まったままの状態を
  # ここで kickstart して戻す。Orca が既に動いているときは kickstart しない
  # （second-instance で既存ウィンドウを前面化するだけで管理下には入らない）。
  # 管理外で動いている Orca は、落とすと中の terminal / agent が全部死ぬので
  # 自動では落とさず、手順を表示するだけにする。
  system.activationScripts.postActivation.text = ''
    orca_uid="$(id -u -- ${username})"
    orca_job="gui/$orca_uid/com.yosuke.orca-app"
    orca_job_pid="$(launchctl print "$orca_job" 2>/dev/null | awk '$1 == "pid" { print $3; exit }')"
    if [ -n "$orca_job_pid" ]; then
      :
    elif pgrep -x -u "$orca_uid" Orca >/dev/null; then
      echo "Orca は launchd の管理外で動いています（クラッシュしても自動で起動し直しません）。" >&2
      echo "  管理下に戻すには Orca を Cmd+Q で終了してから: launchctl kickstart $orca_job" >&2
    else
      launchctl kickstart "$orca_job" || true
    fi
  '';
}
