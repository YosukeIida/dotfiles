{ config, pkgs, ... }:

let
  username = "yosuke";
  homedir = "/Users/${username}";
  darwinConfigDir = "/Users/yosuke/workspace/github.com/YosukeIida/dotfiles";
  darwinHost = "Yosukes-MacBook-Air";

  darwinSwitch = pkgs.writeShellScriptBin "darwin-switch" ''
    exec sudo darwin-rebuild switch --flake ${darwinConfigDir}#${darwinHost} "$@"
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
    if ! brew upgrade; then
      failed=1
    fi

    echo "==> brew upgrade (casks)"
    if ! brew upgrade --cask; then
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

    # IP ranges that must bypass WARP so Tailscale can function.
    # Source: https://tailscale.com/kb/1082/firewall-ports
    # These are stable allocations published by Tailscale. Review if
    # Tailscale's firewall-ports doc is updated (last checked 2026-03).
    #
    #   100.64.0.0/10          tailnet device addresses (CGNAT)
    #   fd7a:115c:a1e0::/48    tailnet device addresses (IPv6)
    #   192.200.0.0/24         control plane (controlplane.tailscale.com)
    #   2606:B740:49::/48      control plane (IPv6)
    #   199.165.136.0/24       logging (log.tailscale.com)
    #   2606:B740:1::/48       logging (IPv6)
    #
    # Headscale (self-hosted control plane) — must also bypass WARP.
    # Background: WARP と Tailscale daemon の Network Extension が競合するため、
    # control plane への通信はすべて WARP の split-tunnel から除外する必要がある。
    # curl 等のユーザ空間ツールは WARP 経由でも到達できるが、
    # tailscaled の Network Extension 層からはルーティングが壊れて
    # connection refused になる（詳細: docs/warp-headscale-conflict.md）。
    #
    #   <headscale-server-ip>/32   headscale server (Oracle Cloud VM, IPv4)
    #
    # !! 注意: Headscale サーバの IP が変わった場合はここを更新すること。
    #    確認方法: dig <your-headscale-hostname>
    warp_exclude_ranges="
      100.64.0.0/10
      fd7a:115c:a1e0::/48
      192.200.0.0/24
      2606:B740:49::/48
      199.165.136.0/24
      2606:B740:1::/48
    "

    # Returns 0 only when all exclusions are confirmed present.
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

    # Optionally sync DERP relay IPs into the WARP split tunnel.
    # Unlike the fixed ranges above, DERP IPs change over time, so this
    # function keeps a state file and removes IPs that have left the map.
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

      # Extract IPv4 and IPv6 addresses with lightweight parsing (no jq).
      local new_ips
      new_ips="$(echo "$derp_json" \
        | grep -oE '"IPv[46]"\s*:\s*"[^"]+"' \
        | grep -oE '"[^"]+"\s*$' \
        | tr -d '"' \
        | sort -u || true)"

      # Load previously synced DERP IPs.
      local prev_ips=""
      if [ -f "$state_file" ]; then
        prev_ips="$(cat "$state_file")"
      fi

      # Return the host-route CIDR for an address (/32 for v4, /128 for v6).
      cidr_for() {
        case "$1" in
          *:*) echo "$1/128" ;;
          *)   echo "$1/32" ;;
        esac
      }

      # Remove stale entries (in prev but no longer in DERP map).
      local ip
      local sync_failed=0
      for ip in $prev_ips; do
        if ! echo "$new_ips" | grep -qxF "$ip"; then
          if ! "$warp_cli" tunnel ip remove-range "$(cidr_for "$ip")" >/dev/null 2>&1; then
            sync_failed=1
          fi
        fi
      done

      # Add new entries.
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

      # Only persist state when every warp-cli call succeeded, so that
      # the next run retries anything that was missed.
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

    # The GUI daemons are not always ready at login, so retry briefly.
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
    (import ./nix/profiles/darwin/macos-defaults.nix {
      inherit username homedir;
    })
    ./nix/profiles/darwin/fonts.nix
    ./nix/profiles/darwin/homebrew.nix
  ];

  system = {
    stateVersion = 6;
    primaryUser = username;
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-darwin";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.interactiveShellInit = ''
    if command -v brew-update-reminder >/dev/null 2>&1; then
      brew-update-reminder || true
    fi
  '';

  environment.systemPackages = with pkgs; [
    vim
    direnv
    nix-direnv
    darwinSwitch
    brewUpgradeAll
    brewUpdateReminder
    vpnCoexistenceApply
  ];

  launchd.user.agents.vpnCoexistenceApply = {
    serviceConfig = {
      Label = "com.yosuke.vpn-coexistence-apply";
      ProgramArguments = [
        "${vpnCoexistenceApply}/bin/vpn-coexistence-apply"
        "--fetch-derp"
      ];
      RunAtLoad = true;
      # Re-apply every 30 minutes to recover from WARP/Tailscale reconnects.
      StartInterval = 1800;
      StandardOutPath = "/tmp/vpn-coexistence-apply.log";
      StandardErrorPath = "/tmp/vpn-coexistence-apply.log";
    };
  };

  # Route *.ts.net DNS queries to Tailscale's resolver so that MagicDNS
  # names work even with --accept-dns=false.  This is the macOS equivalent
  # of the systemd-resolved split-DNS trick (see: man 5 resolver).
  environment.etc."resolver/ts.net" = {
    text = ''
      nameserver 100.100.100.100
    '';
  };

  # dotfiles: シンボリックリンクを冪等に管理する
  # darwin-switch 実行時に自動で展開される
  # 注意: activationScripts は root で実行されるため $HOME ではなく絶対パスを使用
  # nix-darwin はカスタム名のスクリプトを実行しないため postActivation を使用
  system.activationScripts.postActivation.text = ''
    dotfiles="${darwinConfigDir}/dotfiles"
    home="/Users/yosuke"

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

    # Claude Code
    # settings.json は Claude Code が atomic write で実ファイルに置き換えることがある。
    # その場合（= シンボリックリンクでない実ファイルが存在する場合）は、
    # 最新の内容（新しくインストールしたプラグイン等）を dotfiles へコピーしてからリンクを作り直す。
    if [ -f "$home/.claude/settings.json" ] && [ ! -L "$home/.claude/settings.json" ]; then
      cp "$home/.claude/settings.json" "$dotfiles/claude/settings.json"
    fi
    _link "$dotfiles/claude/settings.json"              "$home/.claude/settings.json"
    _link "$dotfiles/claude/settings.api.json"          "$home/.claude/settings.api.json"
    _link "$dotfiles/claude/settings.subscription.json" "$home/.claude/settings.subscription.json"
    _link "$dotfiles/claude/get_key.sh"                 "$home/.claude/get_key.sh"
    _link "$dotfiles/claude/statusline.sh"              "$home/.claude/statusline.sh"
    _link "$dotfiles/agents/AGENTS.md"                  "$home/.claude/CLAUDE.md"
    _link "$dotfiles/agents/skills"                     "$home/.claude/skills"

    # Claude Code プラグインを自動インストール（ユーザー権限で実行）
    su - yosuke -c "bash $dotfiles/claude/install-plugins.sh" || true

    # ssh
    _link "$dotfiles/ssh/config"      "$home/.ssh/config"
    _link "$dotfiles/ssh/cf_proxy.sh" "$home/.ssh/cf_proxy.sh"

    # git
    _link "$dotfiles/git/gitconfig" "$home/.gitconfig"
    _link "$dotfiles/git/ignore"    "$home/.config/git/ignore"

    # ghostty
    _link "$dotfiles/ghostty/config" "$home/.config/ghostty/config"

    # direnv
    _link "$dotfiles/direnv/direnvrc" "$home/.config/direnv/direnvrc"

    # tmux
    _link "$dotfiles/tmux/tmux.conf" "$home/.config/tmux/tmux.conf"

    # nvim
    _link "$dotfiles/nvim/init.lua" "$home/.config/nvim/init.lua"

    # hammerspoon
    _link "$dotfiles/hammerspoon/init.lua"          "$home/.hammerspoon/init.lua"
    _link "$dotfiles/hammerspoon/window_manager.lua" "$home/.hammerspoon/window_manager.lua"
    _link "$dotfiles/hammerspoon/layouts"            "$home/.hammerspoon/layouts"

    # zed
    _link "$dotfiles/zed/settings.json" "$home/.config/zed/settings.json"
    _link "$dotfiles/zed/keymap.json"   "$home/.config/zed/keymap.json"

    # gh
    _link "$dotfiles/gh/config.yml" "$home/.config/gh/config.yml"

    # karabiner
    _link "$dotfiles/karabiner/karabiner.json"                                    "$home/.config/karabiner/karabiner.json"
    _link "$dotfiles/karabiner/assets/complex_modifications/dodo.json"            "$home/.config/karabiner/assets/complex_modifications/dodo.json"

    # zsh
    _link "$dotfiles/zsh/zshenv" "$home/.zshenv"
    _link "$dotfiles/zsh/zshrc"  "$home/.zshrc"

    # codex（初回のみコピー。[projects.*] 等の自動追記を上書きしない）
    if [ ! -e "$home/.codex/config.toml" ]; then
      mkdir -p "$home/.codex"
      cp "$dotfiles/codex/config.toml" "$home/.codex/config.toml"
    fi
  '';
}
