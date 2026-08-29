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
{ pkgs, ... }:

let
  username = "yosuke";
  homedir = "/Users/${username}";

  # Orca の runtime server を、この機の tailnet アドレスを広告しながら起動する。
  #
  # --serve-pairing-address は「相手に伝える住所」を決めるだけで bind 先は変えない
  # （bind は 0.0.0.0:6768 固定で、Orca 側に選択肢が無い）。省略すると Orca は
  # advertisedEndpoint を 127.0.0.1 に決め打ちする（app.asar の
  # resolveAdvertisedPairingEndpoint に自動検出は無い）ため、Air で開いた瞬間に
  # Air 自身を指す使えないリンクになる。だから住所は必ず渡す必要がある。
  #
  # その住所を nix に焼き込まず実行時に引くのは、tailnet アドレスがこの repo の事実では
  # なく Tailscale が持つ状態だから。公開 repo に自分の tailnet アドレスを残さない意味も
  # ある（CGNAT 空間なので到達はできないが、書かずに済むなら書かない）。
  #
  # tailscale を素の `tailscale` ではなく .app 内の実体で呼ぶのは、下の PATH に
  # /usr/local/bin を入れていないため（herdr と揃えた PATH）。そこにあるのは
  #     #!/bin/sh
  #     /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
  # という2行のラッパでしかなく、経由しても得るものが無い。vpn-coexistence-apply
  # （common.nix）が .app 内を直に指しているのと同じ判断。
  #
  # tailscaled が未起動なら住所は取れない。ここで 127.0.0.1 等にフォールバックすると
  # 「繋がらない pairing リンク」を静かに配ることになるので、正直に落ちて KeepAlive の
  # 再試行に任せる（launchd は既定で 10 秒間隔に絞る）。
  orcaServe = pkgs.writeShellScriptBin "orca-serve" ''
    set -euo pipefail

    tailscale_bin="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    orca_bin="/Applications/Orca.app/Contents/MacOS/Orca"

    if [ ! -x "$orca_bin" ]; then
      echo "orca-serve: $orca_bin が無い（cask 未導入か更新中）" >&2
      exit 1
    fi

    if [ ! -x "$tailscale_bin" ]; then
      echo "orca-serve: $tailscale_bin が無い（Tailscale.app 未導入）" >&2
      exit 1
    fi

    address=$("$tailscale_bin" ip -4 2>/dev/null | head -n 1 || true)
    if [ -z "$address" ]; then
      echo "orca-serve: tailnet アドレスを取得できない（tailscaled 起動待ち）。再試行する" >&2
      exit 1
    fi

    echo "orca-serve: advertising $address"
    exec "$orca_bin" --serve --serve-pairing-address "$address"
  '';
in

{
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
  # serve 側への second-instance イベントとして配送し、shouldActivateDesktopForSecondInstance
  # → desktopActivationGate → focusExistingMainWindow(openWindow) がウィンドウを開く経路
  # （app.asar の main を読んで確認、`open -a Orca` しても pid が変わらないことを実測）。
  # つまりウィンドウを閉じても runtime は生き続け、Air からは pairing で入れる。
  #
  # なぜ `orca serve`（公式 CLI）ではなく Electron を直接叩くのか、理由は2つ:
  #
  # 1. Orca 1.4.192 の macOS では `orca serve` が起動時に必ず落ちる。CLI が packaged app
  #    に対して ORCA_SERVE_UPDATE_HANDOFF_PATH を常に渡すため、app 側の
  #    getConfiguredHandoffPath() が early return せず getCanonicalUserDataPath() に進むが、
  #    この呼び出しはモジュールのトップレベル（installServeSupervisorDisconnectQuit）に
  #    あって setAppEnvironment() より前に走る:
  #      Error: AppEnvironment not initialized — call setAppEnvironment() during startup
  #
  # 2. そもそもその supervisor は「CLI の親プロセスが runtime を所有する」ための仕組みで、
  #    親が disconnect したら app.quit() する。launchd に所有させたい本構成では逆に邪魔。
  #    Orca 自体は homebrew cask 管理なので、アプリ内自動更新の引き継ぎも不要。
  #
  # upstream が 1 を直したら ProgramArguments を `orca serve` に戻してよい。
  #
  # 注意（herdr の kickstart と同じ性質）: このウィンドウで Cmd+Q すると runtime ごと
  # 落ちるので、管理下の terminal / agent が全部死ぬ。KeepAlive で新しい runtime が
  # 起動し直すだけで、状態は戻らない。閉じたいだけならウィンドウを閉じる（赤ボタン）。
  #
  # 注意（導入順）: 素の Orca.app が起動していると単一インスタンスロックを先に取られ、
  # serve 側が exit 3 で落ちて KeepAlive のリトライループになる。darwin-switch の前に
  # Orca.app を終了しておくこと。
  launchd.user.agents.orcaServe = {
    serviceConfig = {
      Label = "com.yosuke.orca-serve";
      # 実際の起動は上の orca-serve が行う（tailnet アドレスを実行時に引くため）。
      ProgramArguments = [ "${orcaServe}/bin/orca-serve" ];
      RunAtLoad = true;
      KeepAlive = true;
      # CLI の serveOrcaApp が cwd を app root に固定しているのに倣う（Electron の
      # リソース解決が process.cwd() を見る経路があるため）。
      WorkingDirectory = "/Applications/Orca.app/Contents/Resources/app.asar.unpacked";
      EnvironmentVariables = {
        # herdr と同じ理由。launchd agent は login shell を経ないので hm-session-vars が
        # 届かず、LANG が無いと serve 配下で spawn した経路の日本語が MacRoman 化する。
        LANG = "en_US.UTF-8";
        # 同じく herdr と同じ理由。serve は agent（claude / codex）と git を自分で spawn
        # するので、launchd の最小 PATH のままだと nix 側の git や node を見失う。
        PATH = "${homedir}/.local/share/agent-switch/shims:${homedir}/.nix-profile/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      # pairing URL はここにしか出ない（Air を繋ぐときはこのログから拾う）。
      # デバイストークンを含むので、共有するときは中身に注意すること。
      StandardOutPath = "${homedir}/Library/Logs/orca-serve.log";
      StandardErrorPath = "${homedir}/Library/Logs/orca-serve.log";
    };
  };
}
