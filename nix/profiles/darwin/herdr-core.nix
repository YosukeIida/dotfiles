# herdr-core を常駐させる機体（Yosuke の各 Mac と秘書の VM）で共通の launchd の定義。
# 導入・更新のスクリプトは dotfiles-private の macos-fda/herdr-core-sync にあるので、
# privateDir はその clone を指す。example 構成は dotfiles-private を持たないので import しない。
{
  username,
  homedir,
  privateDir,
}:

let
  path = "${homedir}/.local/share/agent-switch/shims:${homedir}/.local/bin:${homedir}/.nix-profile/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
in
{
  # herdr-core（実ファイルは ~/.local/share/herdr-core/Cellar、自己署名でフルディスクアクセスを
  # 付ける）の導入と更新。Herdr app の自動更新（`hc update`）に任せないのは、ad-hoc の版が
  # 付与したパスで保護されたファイルに触れると、TCC が付与ごと無効にするため（2026-11-02 に
  # 実測）。パスに /Cellar/ を含めて core に `hc update` を断らせ、公式の版を署名してから置く。
  # ~/.local/bin を見張るのは、Herdr app の install.sh が symlink を実ファイルで置き換えたとき
  # 張り直すため。証明書が無い機体では、GUI の端末で一度 `herdr-core-sync --grant` を
  # 実行するまで失敗し続ける。
  launchd.user.agents.herdrCoreSync = {
    serviceConfig = {
      Label = "com.yosuke.herdr-core-sync";
      ProgramArguments = [
        "${privateDir}/macos-fda/herdr-core-sync"
      ];
      WatchPaths = [
        "${homedir}/.local/bin"
      ];
      StartInterval = 3600;
      RunAtLoad = true;
      ThrottleInterval = 30;
      EnvironmentVariables = {
        # 起動し直した core はこの環境を引き継ぐので、serve と同じものを渡す。
        LANG = "en_US.UTF-8";
        PATH = path;
      };
      StandardOutPath = "${homedir}/Library/Logs/herdr-core-sync.log";
      StandardErrorPath = "${homedir}/Library/Logs/herdr-core-sync.log";
    };
  };

  # herdr-core のサーバを Aqua のセッションで起こす。Herdr app（別の機体からの SSH も）は
  # 動いているサーバにつなぐだけになる。SSH の connect にサーバを起こさせると、TCC が
  # サーバの中の agent のアクセスを sshd に帰属させ、herdr-core に付けたフルディスク
  # アクセスが効かない（2026-10-31 に実測）。core は更新のたびに自分で起動し直し、元の
  # プロセスは 0 で終わるので、KeepAlive は異常終了のときだけにする（true だと、既に
  # 動いているサーバを見て 0 で終わる起動を繰り返す）。起動し直しても端末は残る。
  launchd.user.agents.herdrCore = {
    serviceConfig = {
      Label = "com.yosuke.herdr-core";
      ProgramArguments = [
        "${homedir}/.local/share/herdr-core/Cellar/herdr-core"
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive = {
        SuccessfulExit = false;
      };
      EnvironmentVariables = {
        # launchd は login shell を経ないので、LANG と PATH を orcaApp と同じ理由で渡す。
        LANG = "en_US.UTF-8";
        PATH = path;
      };
      StandardOutPath = "${homedir}/Library/Logs/herdr-core.log";
      StandardErrorPath = "${homedir}/Library/Logs/herdr-core.log";
    };
  };
}
