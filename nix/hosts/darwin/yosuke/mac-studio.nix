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
{ ... }:

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

  # Air から `herdr --remote yosuke@100.64.0.12` で attach するための sshd。
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
}
