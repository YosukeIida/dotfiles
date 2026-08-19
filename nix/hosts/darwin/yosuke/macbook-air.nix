# Yosukes-MacBook-Air 固有設定。
#
# 蓋（clamshell）のある機種だけに意味がある sleepctl 一式をここに隔離する。
# Mac Studio には蓋がなく AppleClamshellState が存在しないため、watcher を入れても
# 発火せずループが常駐するだけになる（mac-studio.nix には入れない）。
{ pkgs, ... }:

let
  username = "yosuke";
  homedir = "/Users/${username}";

  # sleepctl on 中に蓋を閉じたら内蔵ディスプレイだけ即座に消す監視スクリプト。
  # sleepctl on/off 自体 (pmset -a disablesleep) はこのスクリプトの責務ではなく
  # zsh関数 sleepctl / raycast-scripts/sleepctl_{on,off}.sh 側が行う。
  # 状態源は pmset の実状態のみなので、手動 pmset で切り替えても追従する。
  # 元ネタ: skanehira/dotfiles 2a98c294 (nix/modules/darwin/sleepctl.nix)。
  # writeShellScript ではなく writeShellScriptBin を使うのは表示名のため:
  # 「ログイン項目とバックグラウンドで実行可能な項目」は署名のない実行ファイルを
  # ProgramArguments[0] の basename で表示する。writeShellScript だと store パス直下の
  # ファイル (72glf…-sleepctl-watcher) になりハッシュ込みで出るが、writeShellScriptBin は
  # <store>/bin/sleepctl-watcher を作るので basename がそのまま名前になる。
  sleepctlWatcher = pkgs.writeShellScriptBin "sleepctl-watcher" ''
    fired=0
    while :; do
      # SleepDisabled 行は未設定のマシンでは出力されないことがあるため
      # 「行があり値が 1」のときだけ有効と判定する
      if [ "$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2 }')" != "1" ]; then
        fired=0
        /bin/sleep 5
        continue
      fi

      # AppleClamshellCausesSleep という似た名前のキーが同居しているので
      # キー名は引用符込みの完全一致でパースする
      state=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 1 \
        | /usr/bin/awk -F' = ' '$1 ~ /"AppleClamshellState"$/ { print $2 }')

      if [ "$state" = "Yes" ]; then
        # 閉じ遷移につき 1 回だけ発火
        if [ "$fired" = "0" ]; then
          /usr/bin/pmset displaysleepnow
          fired=1
        fi
      else
        fired=0
      fi
      /bin/sleep 0.25
    done
  '';
in

{
  # sleepctl: 蓋を閉じても処理を継続する状態 (pmset -a disablesleep) を
  # zsh関数 sleepctl(on/off) と raycast-scripts/sleepctl_{on,off}.sh から
  # パスワードなしで切り替えるためのルール。引数は完全一致のみ許可する。
  # 元ネタ: skanehira/dotfiles 2a98c294 (nix/modules/darwin/sleepctl.nix)。
  # common.nix 側の extraConfig と連結される（types.lines）。
  security.sudo.extraConfig = ''
    ${username} ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
  '';

  # sleepctl on 中に蓋を閉じたら内蔵ディスプレイだけ即座に消す監視エージェント。
  # sleepctl on/off 自体 (pmset -a disablesleep) はこのエージェントの責務ではなく
  # zsh関数 sleepctl / raycast-scripts/sleepctl_{on,off}.sh 側が行う。
  # 注意: CRDセッション中に蓋を閉じるとこのagentが画面共有を止め得る。
  launchd.user.agents.sleepctlWatcher = {
    serviceConfig = {
      Label = "com.yosuke.sleepctl-watcher";
      ProgramArguments = [ "${sleepctlWatcher}/bin/sleepctl-watcher" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "${homedir}/Library/Logs/sleepctl-watcher.log";
      StandardErrorPath = "${homedir}/Library/Logs/sleepctl-watcher.log";
    };
  };
}
