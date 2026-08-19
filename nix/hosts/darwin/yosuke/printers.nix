# プリンター設定（headscale 経由の LAN プリンター）
#
# IP / 機種名 / 設置場所ラベルは agenix で暗号化され、darwin-switch 時に
# ~/.config/printers/printers.env (mode 600) へ復号配置される。
# printers.env 形式:
#   KYOCERA_IP=...
#   KYOCERA_DESC=...
#   BROTHER_IP=...
#   BROTHER_DESC=...
#   LOCATION=...
#
# headscale 接続中に `printer-setup` を実行すると登録される。
{ pkgs, ... }:

let
  printerSetup = pkgs.writeShellScriptBin "printer-setup" ''
    set -uo pipefail

    ENV_FILE="$HOME/.config/printers/printers.env"
    if [ ! -r "$ENV_FILE" ]; then
      echo "error: $ENV_FILE が見つかりません（darwin-switch で復号配置されます）" >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    . "$ENV_FILE"

    setup_printer() {
      local name="$1" ip="$2" desc="$3"
      if [ -z "$ip" ]; then
        echo "warning: $name の IP が未設定（printers.env を確認）" >&2
        return 0
      fi
      if lpstat -p "$name" >/dev/null 2>&1; then
        echo "$name: 登録済みです"
      elif ! ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
        echo "warning: $ip に到達できません ($name をスキップ)" >&2
      else
        lpadmin -p "$name" -E -v "ipp://$ip/ipp/print" -m everywhere \
          -D "$desc" -L "''${LOCATION:-}"
        echo "$name: 追加しました"
      fi
    }

    setup_printer "kyocera-411" "''${KYOCERA_IP:-}" "''${KYOCERA_DESC:-Kyocera}"
    setup_printer "brother-411" "''${BROTHER_IP:-}" "''${BROTHER_DESC:-Brother}"

    # 1台でも追加できていればデフォルトに設定（未設定の場合のみ）
    if ! lpstat -d 2>/dev/null | grep -q "宛先:"; then
      if lpstat -p "kyocera-411" >/dev/null 2>&1; then
        lpoptions -d "kyocera-411"
        echo "デフォルトプリンターを kyocera-411 に設定しました"
      fi
    fi
  '';
in

{
  environment.systemPackages = [ printerSetup ];
}
