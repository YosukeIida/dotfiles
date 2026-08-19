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
}
