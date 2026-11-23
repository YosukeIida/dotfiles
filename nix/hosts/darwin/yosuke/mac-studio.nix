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
  homebrew.brews = [
    # Apple Container 本体（CLI + XPC バックエンド）。Orchard（cask）はこの GUI フロント
    # エンドで、本体がないと "XPC connection error" になる。常駐サービス化はせず、
    # 使うときに `container system start` を手動実行する運用。
    "container"
  ];
  homebrew.casks = [
    # OpenClaw 秘書を閉じ込める macOS VM の土台（dotfiles-private の
    # docs/2026-10-02_secretary-agent-base-selection.md）。公式 tap（trycua/lume）は
    # 0.1.13 で止まっており、install スクリプトは自動更新と daemon の LaunchAgent まで
    # 入れるため、公証済みの app だけを置く自前 cask を使う。formula にしないのは、
    # Homebrew の再署名で com.apple.vm.networking の署名が崩れないようにするため。
    # テレメトリは home.sessionVariables の LUME_TELEMETRY_ENABLED で止める。
    "yosukeiida/casks-personal/lume"
    "orchard"
    # ローカルの LLM は Studio では omlx に一本化する（LM Studio は Air だけ）。持ち歩く Air には入れない。
    # 公式 tap（jundot/omlx）の formula は upgrade のたびにソースからビルドし、rust と python@3.11 を
    # 入れるので、公証済みの DMG のアプリを置く自前 cask を使う。更新は brew upgrade で行い、
    # アプリ内の自動更新は下の home.activation で止める。
    "yosukeiida/casks-personal/omlx"
  ];

  # Xcode は Swift のビルド（ararat など）に要る。宣言に無い App Store アプリは
  # cleanup = "zap" が uninstall しようとする（2026-10-31 に sudo の失敗で止まって残った）。
  homebrew.masApps.Xcode = 497799835;

  # HuggingFace のキャッシュ（モデル・データセット）を外付け SSD（PRO-G40, 4TB）に置く。
  # 既定は yosuke/common.nix の mkDefault（~/.cache/huggingface）で、ここで素の値で上書きする。
  # ディスク未接続時はこのパスが存在せず、ロードもダウンロードも失敗する。
  home-manager.users.${username} =
    { lib, ... }:
    {
      home.sessionVariables.HF_HOME = "/Volumes/PRO-G40/huggingface";

      # omlx のアプリが置く CLI（omlx start/stop/status）。アプリは初回起動時に .zshrc へ PATH を
      # 書くかを尋ねるが、.zshrc は nix が持つので断り、ここで足す。
      home.sessionPath = [ "$HOME/.omlx/bin" ];

      # omlx のアプリ内の自動更新は、24 時間ごとに確認のダイアログを出してクリックを待つ。
      # 更新は cask の brew upgrade に任せるので、確認そのものを切る（autoCheck だけを書き換え、他の値は残す）。
      home.activation.omlxNoSelfUpdate = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        prefs="$HOME/Library/Application Support/oMLX/update-prefs.json"
        mkdir -p "$(dirname "$prefs")"
        [ -s "$prefs" ] || echo '{}' > "$prefs"
        ${pkgs.jq}/bin/jq '.autoCheck = false' "$prefs" > "$prefs.tmp" && mv "$prefs.tmp" "$prefs"
      '';
    };

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

  # omlx のアプリをログイン時に裏で起動する。サーバはアプリの子で、~/.omlx/settings.json の
  # server.auto_start_on_launch（既定で true）によりアプリの起動と同時に立ち上がる。サーバが落ちたら
  # アプリが起動し直す。KeepAlive は付けない（omlx stop や Quit で意図して止めたものを起こし直さないため）。
  launchd.user.agents.omlx = {
    serviceConfig = {
      Label = "com.yosuke.omlx";
      ProgramArguments = [
        "/usr/bin/open"
        "-g"
        "-a"
        "oMLX"
      ];
      RunAtLoad = true;
    };
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
}
