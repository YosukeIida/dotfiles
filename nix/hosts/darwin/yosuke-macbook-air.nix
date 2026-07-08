# Yosukes-MacBook-Air 固有設定（旧 dotfiles-private/nix/default.nix を移植）
#
# - darwin-switch は public repo の #Yosukes-MacBook-Air を指す
# - 秘密値（ssh config / cf token / headscale ip / printers / raycast pw）は
#   agenix で暗号化され、postActivation が ~/.config 以下へ復号配置する
# - private skills は private overlay（dotfiles-private）のローカルパスから symlink
{
  config,
  lib,
  pkgs,
  ...
}:

let
  username = "yosuke";
  homedir = "/Users/${username}";
  publicDir = "/Users/yosuke/workspace/github.com/YosukeIida/dotfiles";
  privateDir = "/Users/yosuke/workspace/github.com/YosukeIida/dotfiles-private";
  darwinHost = "Yosukes-MacBook-Air";

  # ad-hoc 署名／notarize なしの個人アプリは Gatekeeper の
  # "could not verify... free of malware" で毎回ブロックされる。
  # ここに明示的に追加したパスだけ switch のたびに quarantine 属性を剥がす。
  # リストに無いものには一切触れない（全アプリ一律の解除はしない）。
  quarantineAllowlist = [
    "/Applications/Zed Dev RaTeX(unofficial).app"
  ];

  # git identity + lab 固有 safe.directory。public の git/gitconfig は [include] するだけで、
  # 実体はここで生成する（他者環境ではこのファイルが無く、その人自身の identity が使われる）。
  # identity は秘密ではない（コミットに載る公開情報）ため agenix ではなく通常ファイルで扱う。
  gitconfigLocal = pkgs.writeText "gitconfig-local" ''
    [user]
    name = i2
    email = 95607264+YosukeIida@users.noreply.github.com
    [safe]
    directory = /Users/yosuke/workspace/github.com/TMLlaboratory/llm-kie-sorimachi
    directory = /Users/yosuke/workspace/github.com/TMLlaboratory/llm-kie
    directory = /Users/yosuke/workspace/github.com/TMLlaboratory/s-code
  '';

  darwinSwitch = pkgs.writeShellScriptBin "darwin-switch" ''
    exec sudo darwin-rebuild switch --flake ${publicDir}#${darwinHost} "$@"
  '';

  darwinUpdate = pkgs.writeShellScriptBin "darwin-update" ''
    set -euo pipefail
    cd ${publicDir}
    echo "==> nix flake update"
    nix flake update
    echo "==> darwin-switch"
    exec sudo darwin-rebuild switch --flake ${publicDir}#${darwinHost}
  '';

  brewUpgradeAll = pkgs.writeShellScriptBin "brew-upgrade-all" ''
    set -euo pipefail

    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    if ! command -v brew >/dev/null 2>&1; then
      echo "error: brew not found (expected /opt/homebrew/bin/brew)" >&2
      exit 1
    fi

    failed=0

    echo "==> brew update"
    if ! brew update; then
      failed=1
    fi

    echo "==> brew upgrade (formulae)"
    if ! HOMEBREW_NO_INTERACTIVE=1 brew upgrade --yes; then
      failed=1
    fi

    echo "==> brew upgrade (casks)"
    if ! HOMEBREW_NO_INTERACTIVE=1 brew upgrade --cask --yes; then
      failed=1
    fi

    exit "$failed"
  '';

  brewUpdateReminder = pkgs.writeShellScriptBin "brew-update-reminder" ''
    set -euo pipefail

    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    if ! command -v brew >/dev/null 2>&1; then
      exit 0
    fi

    : "''${HOME:=}"
    if [ -z "$HOME" ]; then
      exit 0
    fi

    state_dir="$HOME/Library/Application Support/nix-darwin"
    last_file="$state_dir/brew-update-reminder.last"
    mkdir -p "$state_dir"

    now="$(date +%s)"
    if [ -f "$last_file" ]; then
      last="$(stat -f %m "$last_file" 2>/dev/null || echo 0)"
      if [ $((now - last)) -lt 86400 ]; then
        exit 0
      fi
    fi

    touch "$last_file" || true

    outdated_formula="$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula --quiet 2>/dev/null || true)"
    outdated_cask="$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask --quiet 2>/dev/null || true)"

    if [ -n "$outdated_formula" ] || [ -n "$outdated_cask" ]; then
      echo "nix-darwin: Homebrew updates available. Run: brew-upgrade-all or darwin-switch"
    fi
  '';

  vpnCoexistenceApply = pkgs.writeShellScriptBin "vpn-coexistence-apply" ''
    set -euo pipefail

    tailscale_bin="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    warp_cli="/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli"
    disable_routes=0
    fetch_derp=0

    for arg in "$@"; do
      case "$arg" in
        --disable-tailscale-routes) disable_routes=1 ;;
        --fetch-derp) fetch_derp=1 ;;
        *)
          echo "usage: vpn-coexistence-apply [--disable-tailscale-routes] [--fetch-derp]" >&2
          exit 64
          ;;
      esac
    done

    configure_tailscale() {
      if [ ! -x "$tailscale_bin" ]; then
        return 0
      fi

      "$tailscale_bin" set --accept-dns=false --exit-node= >/dev/null

      if [ "$disable_routes" -eq 1 ]; then
        "$tailscale_bin" set --accept-routes=false >/dev/null
      fi
    }

    # WARP をバイパスさせる IP レンジ（Tailscale/Headscale を機能させるため）。
    # Source: https://tailscale.com/kb/1082/firewall-ports
    #
    #   100.64.0.0/10          tailnet device addresses (CGNAT)
    #   fd7a:115c:a1e0::/48    tailnet device addresses (IPv6)
    #   192.200.0.0/24         control plane (controlplane.tailscale.com)
    #   2606:B740:49::/48      control plane (IPv6)
    #   199.165.136.0/24       logging (log.tailscale.com)
    #   2606:B740:1::/48       logging (IPv6)
    warp_exclude_ranges="
      100.64.0.0/10
      fd7a:115c:a1e0::/48
      192.200.0.0/24
      2606:B740:49::/48
      199.165.136.0/24
      2606:B740:1::/48
    "

    # Headscale サーバ IP は agenix 暗号化 → darwin-switch 時に下記へ復号配置。
    # 復号ファイルが無い／空なら除外を追加せず残りだけ適用（fail-soft、30分毎再実行で自己修復）。
    headscale_ip=""
    hs_file="${homedir}/.config/vpn/headscale-ip"
    if [ -r "$hs_file" ]; then
      headscale_ip="$(tr -d '[:space:]' < "$hs_file" 2>/dev/null || true)"
    fi
    if [ -n "$headscale_ip" ]; then
      warp_exclude_ranges="$warp_exclude_ranges
      $headscale_ip/32"
    fi

    configure_warp() {
      if [ ! -x "$warp_cli" ]; then
        return 0
      fi

      local current_ranges failed=0
      current_ranges="$("$warp_cli" tunnel ip list --no-ansi 2>/dev/null || true)"

      for range in $warp_exclude_ranges; do
        case "$current_ranges" in
          *"$range"*) ;;
          *)
            if ! "$warp_cli" tunnel ip add-range "$range" >/dev/null 2>&1; then
              failed=1
            fi
            ;;
        esac
      done

      return "$failed"
    }

    configure_warp_derp() {
      if [ "$fetch_derp" -eq 0 ]; then
        return 0
      fi
      if [ ! -x "$warp_cli" ]; then
        return 0
      fi
      if ! command -v curl >/dev/null 2>&1; then
        echo "warning: curl not found; skipping DERP sync" >&2
        return 0
      fi

      local state_dir="''${HOME}/Library/Application Support/nix-darwin"
      local state_file="$state_dir/vpn-derp-exclusions.txt"
      mkdir -p "$state_dir"

      local derp_json
      derp_json="$(curl -fsSL --max-time 15 \
        https://controlplane.tailscale.com/derpmap/default 2>/dev/null || true)"
      if [ -z "$derp_json" ]; then
        echo "warning: could not fetch DERP map; keeping previous state" >&2
        return 0
      fi

      local new_ips
      new_ips="$(echo "$derp_json" \
        | grep -oE '"IPv[46]"\s*:\s*"[^"]+"' \
        | grep -oE '"[^"]+"\s*$' \
        | tr -d '"' \
        | sort -u || true)"

      local prev_ips=""
      if [ -f "$state_file" ]; then
        prev_ips="$(cat "$state_file")"
      fi

      cidr_for() {
        case "$1" in
          *:*) echo "$1/128" ;;
          *)   echo "$1/32" ;;
        esac
      }

      local ip
      local sync_failed=0
      for ip in $prev_ips; do
        if ! echo "$new_ips" | grep -qxF "$ip"; then
          if ! "$warp_cli" tunnel ip remove-range "$(cidr_for "$ip")" >/dev/null 2>&1; then
            sync_failed=1
          fi
        fi
      done

      local current_ranges
      current_ranges="$("$warp_cli" tunnel ip list --no-ansi 2>/dev/null || true)"
      for ip in $new_ips; do
        case "$current_ranges" in
          *"$ip"*) ;;
          *)
            if ! "$warp_cli" tunnel ip add-range "$(cidr_for "$ip")" >/dev/null 2>&1; then
              sync_failed=1
            fi
            ;;
        esac
      done

      if [ "$sync_failed" -eq 0 ]; then
        echo "$new_ips" > "$state_file"
        return 0
      else
        echo "warning: some DERP exclusions failed; state file not updated" >&2
        return 1
      fi
    }

    tailscale_pending=0
    warp_pending=1
    if [ -x "$tailscale_bin" ]; then
      tailscale_pending=1
    fi

    for _ in $(seq 1 30); do
      if [ "$tailscale_pending" -eq 1 ] && configure_tailscale 2>/dev/null; then
        tailscale_pending=0
      fi

      if [ "$warp_pending" -eq 1 ] && configure_warp 2>/dev/null; then
        warp_pending=0
      fi

      if [ "$tailscale_pending" -eq 0 ] && [ "$warp_pending" -eq 0 ]; then
        break
      fi

      sleep 2
    done

    derp_ok=0
    if ! configure_warp_derp; then
      derp_ok=1
    fi

    rc=0
    if [ "$tailscale_pending" -eq 1 ]; then
      echo "warning: tailscale settings were not applied" >&2
      rc=1
    fi
    if [ "$warp_pending" -eq 1 ]; then
      echo "warning: warp split-tunnel exclusions were not fully applied" >&2
      rc=1
    fi
    if [ "$derp_ok" -eq 1 ]; then
      echo "warning: DERP exclusions were not fully synchronized" >&2
      rc=1
    fi
    exit "$rc"
  '';
in

{
  imports = [
    ./printers.nix
  ];

  environment.interactiveShellInit = ''
    if command -v brew-update-reminder >/dev/null 2>&1; then
      brew-update-reminder || true
    fi
  '';

  environment.systemPackages = with pkgs; [
    vim
    direnv
    git-filter-repo
    nix-direnv
    zellij
    darwinSwitch
    darwinUpdate
    brewUpgradeAll
    brewUpdateReminder
    vpnCoexistenceApply
  ];

  security.sudo.extraConfig = ''
    ${username} ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';

  launchd.user.agents.vpnCoexistenceApply = {
    serviceConfig = {
      Label = "com.yosuke.vpn-coexistence-apply";
      ProgramArguments = [
        "${vpnCoexistenceApply}/bin/vpn-coexistence-apply"
        "--fetch-derp"
      ];
      RunAtLoad = true;
      StartInterval = 1800;
      # /tmp は再起動で消えるため、永続する ~/Library/Logs に出力する
      StandardOutPath = "${homedir}/Library/Logs/vpn-coexistence-apply.log";
      StandardErrorPath = "${homedir}/Library/Logs/vpn-coexistence-apply.log";
    };
  };

  # figma-pat.age の失効前チェック（週次月曜 10:00）。期限はスクリプト内の定数で管理。
  launchd.user.agents.figmaPatExpiryCheck = {
    serviceConfig = {
      Label = "com.yosuke.figma-pat-expiry-check";
      ProgramArguments = [
        "/bin/bash"
        "${publicDir}/scripts/check-figma-pat-expiry.sh"
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 10;
          Minute = 0;
        }
      ];
      StandardOutPath = "${homedir}/Library/Logs/figma-pat-expiry-check.log";
      StandardErrorPath = "${homedir}/Library/Logs/figma-pat-expiry-check.log";
    };
  };

  # Route *.ts.net DNS queries to Tailscale's resolver (MagicDNS with --accept-dns=false).
  environment.etc."resolver/ts.net" = {
    text = ''
      nameserver 100.100.100.100
    '';
  };

  system.activationScripts.postActivation.text = ''
    priv="${privateDir}"
    pub="${publicDir}"
    home="${homedir}"

    _link() {
      local src="$1" dst="$2"
      mkdir -p "$(dirname "$dst")"
      if [ -L "$dst" ]; then
        rm "$dst"
      elif [ -e "$dst" ]; then
        mv "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
      fi
      ln -sf "$src" "$dst"
    }

    # agenix 復号 secret を安定パスへ配置（agenix 未復号なら fail-soft）
    _place() {
      local src="$1" dst="$2"
      if [ -r "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        rm -f "$dst"
        install -m 600 -o ${username} -g staff "$src" "$dst"
      else
        echo "warning: agenix secret not ready: $src (skipping $dst)" >&2
      fi
    }

    # private skills を ~/.claude/skills, ~/.codex/skills に追加（private overlay が無ければ skip）
    if [ -d "$priv/agents/skills" ]; then
      for d in "$priv/agents/skills"/*/; do
        [ -d "$d" ] || continue
        _link "$d" "$home/.claude/skills/$(basename "$d")"
        _link "$d" "$home/.codex/skills/$(basename "$d")"
      done
    fi

    # agenix デーモン（org.nixos.activate-agenix）は非同期で /run/agenix へ復号する。
    # 初回 switch / boot 時は _place より後に復号が終わる可能性があるため、完了を待つ（最大 ~30秒）。
    if [ ! -e /run/agenix/ssh-config ]; then
      echo "waiting for agenix to decrypt secrets into /run/agenix ..."
      for _ in $(seq 1 60); do
        [ -e /run/agenix/ssh-config ] && break
        sleep 0.5
      done
    fi

    # agenix シークレットの安定パス配置
    _place "${config.age.secrets."ssh-config".path}"   "$home/.ssh/config"
    _place "${config.age.secrets."cf-token".path}"      "$home/.config/cf/token.env"
    _place "${config.age.secrets."headscale-ip".path}"  "$home/.config/vpn/headscale-ip"
    _place "${config.age.secrets."printers".path}"      "$home/.config/printers/printers.env"
    _place "${config.age.secrets."raycast-pw".path}"    "$home/.config/raycast/export.env"
    _place "${config.age.secrets."figma-pat".path}"     "$home/.config/figma/pat"

    # cf_proxy.sh（public）を ~/.ssh に配置
    _link "$pub/ssh/cf_proxy.sh" "$home/.ssh/cf_proxy.sh"

    # git identity を ~/.gitconfig.local に生成（public gitconfig が include する）。
    install -m 644 -o ${username} -g staff ${gitconfigLocal} "$home/.gitconfig.local"

    # Codex の安定設定を system layer（/etc/codex/config.toml）で管理する。
    # approval_policy=never・sandbox_mode=danger-full-access を含むため common ではなく
    # ここ（host 固有）で配備し、example を使う他者には渡さない。
    # ~/.codex/config.toml は projects/trust/UI 等のローカル状態として Codex に所有させる。
    _link "$pub/codex/config.toml" "/etc/codex/config.toml"
    # 旧 activation が ~/.codex/config.toml にコピーした安定設定を除去する
    # （user layer は system layer より優先されるため、残すと新しい system 設定が無視される）。
    su - ${username} -c "bash $pub/codex/migrate-user-config.sh" || true

    # Stats 設定を dotfiles（public）から毎回インポート
    if [ -f "$pub/config/Stats-current.plist" ]; then
      launchctl asuser "$(id -u -- ${username})" \
        sudo -u ${username} -- \
        defaults import eu.exelban.Stats "$pub/config/Stats-current.plist"
    fi

    # stats-export スクリプトを ~/.local/bin に配置
    sudo -u ${username} mkdir -p "$home/.local/bin"
    _link "$pub/scripts/stats-export" "$home/.local/bin/stats-export"

    # delegate-browser も同様に配置（従来は手動 symlink 依存だった）
    _link "$pub/scripts/delegate-browser" "$home/.local/bin/delegate-browser"

    # 明示的に許可したアプリだけ quarantine 属性を解除する（quarantineAllowlist 参照）。
    # 再インストール／更新でダウンロードするたびに quarantine が再付与されるため毎 switch 実行する。
    # shellcheck disable=SC2043  # リストが1件でも将来増える前提の for ループ
    for app in ${lib.concatMapStringsSep " " (p: ''"${p}"'') quarantineAllowlist}; do
      if [ -e "$app" ]; then
        xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
      fi
    done
  '';
}
