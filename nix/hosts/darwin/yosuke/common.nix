# Yosuke の全 Mac に共通の個人設定（旧 yosuke-macbook-air.nix）。
#
# 機種を問わない部分だけをここに置き、機種固有は同ディレクトリの
# macbook-air.nix / mac-studio.nix が受け持つ。
#
# - darwin-switch / darwin-update は public repo の #${darwinHost} を指す
#   （darwinHost は flake.nix から渡す。ホスト名は各機の `hostname -s` と一致させること）
# - 秘密値（ssh config / cf token / headscale ip / printers / raycast pw）は
#   agenix で暗号化され、postActivation が ~/.config 以下へ復号配置する
# - private skills は private overlay（dotfiles-private）のローカルパスから symlink
#
# 対比: ../common/ は「他人も fork して使える層」（example 構成が import する）。
# こちらは username / git identity / 研究室パスまで直書きした Yosuke 専用層。
{ darwinHost }:

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
  skillsPubDir = "/Users/yosuke/workspace/github.com/YosukeIida/personal-agent-skills";

  # ad-hoc 署名／notarize なしの個人アプリは Gatekeeper の
  # "could not verify... free of malware" で毎回ブロックされる。
  # ここに明示的に追加したパスだけ switch のたびに quarantine 属性を剥がす。
  # リストに無いものには一切触れない（全アプリ一律の解除はしない）。
  quarantineAllowlist = [
    "/Applications/Zed Dev RaTeX(unofficial).app"
    "/Applications/PowerGlance.app"
    "/Applications/Pindrop.app"
  ];

  # 上と同じ目的だが、Homebrew cask のバージョン番号を含むパス
  # （更新のたびにディレクトリ名が変わる）向け。glob展開させるため要素は
  # double-quote しない（= 各要素にスペースを含めないこと）。
  #
  # codex cask が同梱する rg（ripgrep）バイナリに quarantine が付き、Codex実行時に
  # 毎回 Gatekeeper でブロックされる事例（2026-07-10）。brew install ripgrep の
  # /opt/homebrew/bin/rg とは別物。
  quarantineGlobAllowlist = [
    "/opt/homebrew/Caskroom/codex/*/codex-path/rg"
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

  # Homebrew の cask には .pkg やシステム拡張を使うものがあり（Acrobat・Chrome Remote
  # Desktop Host・Cloudflare WARP・ScanSnap・Karabiner 等）、Homebrew はその都度
  # sudo を呼ぶ。sudo の timestamp は既定 5 分で切れるので、巨大な cask のダウンロードを
  # 挟むと何度もパスワードを聞かれ、switch の間ずっと端末に張り付く羽目になる。
  #
  # 最初に一度だけ認証し、実行中はバックグラウンドで timestamp を延命することで
  # 無人実行にする。sudoers は緩めない（NOPASSWD を足すと installer 経由で任意の
  # root 実行を許すことになるため、こちらは採らない）。
  #
  # Touch ID があれば体感の負担は小さいが（macos-defaults.nix の touchIdAuth）、
  # Mac Studio にはセンサーが無いので実際に問題になる。
  sudoKeepalive = ''
    # 非対話実行（Claude Code 等）では sudo -v がパスワード待ちで固まるので何もしない。
    if [ -t 0 ]; then
      sudo -v
      # $$ は exec 後も同じ PID を指すので、darwin-rebuild が終われば このループも抜ける。
      while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
    fi
  '';

  darwinSwitch = pkgs.writeShellScriptBin "darwin-switch" ''
    export DARWIN_HOST=${lib.escapeShellArg darwinHost}
    ${builtins.readFile ../scripts/check-node-deps.sh}
    check_node_deps || exit 1
    ${sudoKeepalive}
    exec sudo darwin-rebuild switch --flake ${publicDir}#${darwinHost} "$@"
  '';

  darwinUpdate = pkgs.writeShellScriptBin "darwin-update" ''
    set -euo pipefail
    cd ${publicDir}
    echo "==> nix flake update"
    nix flake update
    echo "==> darwin-switch"
    ${sudoKeepalive}
    exec sudo darwin-rebuild switch --flake ${publicDir}#${darwinHost}
  '';

  brewUpgradeAll = pkgs.writeShellScriptBin "brew-upgrade-all" ''
    set -euo pipefail

    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    # auto_updates な cask を brew upgrade の対象から外す（Homebrew 6 の既定は対象）。
    # ~/.homebrew/brew.env（homebrew/brew.env、理由の詳細もそちら）と同じ設定だが、
    # brew.env が未配備でも日次実行のこのスクリプトだけは意図どおり動くよう明示する。
    export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1

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

    # skill の更新有無も日次で拾う（読み取り専用。取り込みは手動で diff を目視する）。
    # exit 1 は「更新あり」で異常ではないため、set -e で落ちないよう終了コードを受ける。
    echo "==> agent skills"
    skills_rc=0
    "${agentSkillsOutdated}/bin/agent-skills-outdated" || skills_rc=$?
    case "$skills_rc" in
      0 | 1) ;; # 最新 / 更新あり（内容は上に出力済み）
      *) failed=1 ;; # 判定できなかった場合だけ失敗として扱う
    esac

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

  # Zed Dev RaTeX(unofficial) は yosukeiida/casks-personal の zed-dev-ratex cask で
  # 管理する（homebrew.nix 参照）。以前はここに zed-latex-upgrade という自作コマンドが
  # あったが、cask と二重管理になり /Applications を brew の記録の裏で書き換えるため
  # Caskroom のバージョンと実体がずれる問題を起こしていたので削除した。
  # 週次リリースへの追従は zed 側の latex_weekly_release.yml が cask を bump する。

  # skill の更新有無だけを表示する（brew outdated 相当）。内容は一切書き換えない。
  # 取り込みを自動化しないのは、外部 skill の更新時は目視 diff を必須とする方針
  # （CLAUDE.md、プロンプトインジェクション対策）に従うため。
  #
  # なぜラッパーが必要か: `gh skill update --dry-run` は更新の有無に関わらず exit 0 を
  # 返し、`--json` も未実装（2026-07 実測。cli/cli#13215 で要望中）。スクリプトから
  # 判定できないため、ここで exit code の契約を与える:
  #   0 = 全て最新 / 1 = 更新あり / 2 = エラー
  agentSkillsOutdated = pkgs.writeShellScriptBin "agent-skills-outdated" ''
    # -e は付けない: grep が「該当なし」で 1 を返すのが正常系のため。
    set -uo pipefail

    PATH="/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    verbose=0
    quiet=0
    for arg in "$@"; do
      case "$arg" in
        --verbose) verbose=1 ;;
        --quiet) quiet=1 ;;
        *)
          echo "usage: agent-skills-outdated [--verbose] [--quiet]" >&2
          exit 2
          ;;
      esac
    done

    if ! command -v gh >/dev/null 2>&1; then
      echo "agent-skills-outdated: gh (GitHub CLI) not found" >&2
      exit 2
    fi

    updates=0
    errors=0
    report=""

    add_report() {
      report="$report$1"$'\n'
    }

    # --- gh skill 経路 -----------------------------------------------------
    # metadata.github-* を持つ skill（sync-lab-skills.sh が注入）を比較する。
    #
    # --all は必須: 付けないと metadata の無い skill について「どの GitHub repo 由来か」を
    # 対話的に尋ね、無人実行が stdin 待ちで固まる（sync-lab-skills.sh に実機確認の記録あり）。
    # </dev/null で二重に担保する。
    scan_gh_skill() {
      dir="$1"
      label="$2"

      [ -d "$dir" ] || return 0

      result="$(gh skill update --dry-run --all --dir "$dir" 2>&1 </dev/null)"

      if printf '%s\n' "$result" | grep -q 'update(s) available'; then
        updates=1
        add_report "[$label]"
        add_report "$(printf '%s\n' "$result" \
          | awk '/update\(s\) available/,0' \
          | grep -v 'no GitHub metadata' \
          | sed '/^[[:space:]]*$/d')"
      elif printf '%s\n' "$result" | grep -qE 'All skills are up to date\.|No installed skills found'; then
        : # 最新、または gh が skill として認識するものが無い
      else
        # 想定外の出力を「更新なし」と誤読すると、静かに古いまま放置される。
        # ネットワーク断や gh の出力形式変更はエラーとして鳴らす。
        errors=1
        add_report "[$label] cannot interpret gh skill output:"
        add_report "$result"
      fi

      if [ "$verbose" -eq 1 ]; then
        printf '%s\n' "$result" | grep 'no GitHub metadata' | sed "s/^/[$label] /" || true
      fi
    }

    # --- vendor-* pin 経路 -------------------------------------------------
    # gh skill はリポジトリ直下の SKILL.md を扱えない（`gh skill preview
    # ogulcancelik/herdr` が "no standard skills found" を返す）。そうした vendor コピーは
    # frontmatter に vendor-* を持たせ、その SKILL.md を触った commit だけを比較する。
    # キー名を github-* にしないのは、gh 側がリポジトリルートの tree を見て upstream の
    # 全 commit を「更新あり」と誤検知するのを避けるため。
    # $1=repo $2=pin $3=latest: pin が latest の変更を既に含んでいるかを判定する。
    # 単純な文字列完全一致（旧実装）だと、1つの vendor-commit で複数ファイルを
    # まとめて pin する skill（例: gws-multi-account が SKILL.md・hooks/hook.js・
    # references/auth-login.md をそれぞれ異なる最終変更commitのまま1つのHEADで
    # pin している）で、pin が latest より新しいのに文字列としては一致せず
    # 恒久的に「更新あり」と誤検知する（2026-08-12 darwin-switch で実測）。
    # compare(pin...latest) の status で「pin が既に latest を含むか」を見る。
    commit_is_covered() {
      if [ "$2" = "$3" ]; then
        return 0
      fi
      cmp_status="$(gh api "repos/$1/compare/$2...$3" --jq '.status' 2>/dev/null)"
      case "$cmp_status" in
        identical|behind) return 0 ;;
        *) return 1 ;;
      esac
    }

    scan_vendor_pins() {
      dir="$1"
      label="$2"

      [ -d "$dir" ] || return 0

      for skill in "$dir"/*/SKILL.md; do
        [ -f "$skill" ] || continue

        repo="$(sed -nE 's/^[[:space:]]*vendor-repo:[[:space:]]*(.+)$/\1/p' "$skill" | head -n1)"
        [ -n "$repo" ] || continue

        name="$(basename "$(dirname "$skill")")"
        vpath="$(sed -nE 's/^[[:space:]]*vendor-path:[[:space:]]*(.+)$/\1/p' "$skill" | head -n1)"
        pin="$(sed -nE 's/^[[:space:]]*vendor-commit:[[:space:]]*(.+)$/\1/p' "$skill" | head -n1)"

        if [ -z "$vpath" ] || [ -z "$pin" ]; then
          errors=1
          add_report "[$label] $name: vendor-repo があるが vendor-path/vendor-commit が無い"
          continue
        fi

        latest="$(gh api "repos/$repo/commits?path=$vpath&per_page=1" --jq '.[0].sha' 2>/dev/null)"

        if [ -z "$latest" ]; then
          # 到達できないだけならエラーにはしないが、黙って飛ばすと「最新」と
          # 見分けがつかなくなるので必ず報告する（lab PAT は別 repo 用スコープなので、
          # postActivation では公開 repo にも届かないことがある）。
          add_report "[$label] $name: 未確認（$repo に到達できず）"
          continue
        fi

        if ! commit_is_covered "$repo" "$pin" "$latest"; then
          updates=1
          add_report "[$label] $name: $repo:$vpath updated"
          add_report "  pinned $pin -> $latest"
        fi

        # vendor-extra-paths: SKILL.md 以外に extra_files で一緒に vendor した
        # ファイル（例: gws-multi-account の hooks/hook.js）。SKILL.md 自体は
        # 変わらずこちらだけ upstream が更新した場合を拾うため、同じ pin
        # （vendor-commit、全ファイル共通の rev）を基準に個別チェックする。
        extra_paths="$(sed -nE 's/^[[:space:]]*vendor-extra-paths:[[:space:]]*(.+)$/\1/p' "$skill" | head -n1)"
        for ep in $extra_paths; do
          elatest="$(gh api "repos/$repo/commits?path=$ep&per_page=1" --jq '.[0].sha' 2>/dev/null)"
          if [ -z "$elatest" ]; then
            add_report "[$label] $name: 未確認（$repo:$ep に到達できず）"
            continue
          fi
          if ! commit_is_covered "$repo" "$pin" "$elatest"; then
            updates=1
            add_report "[$label] $name: $repo:$ep updated (extra file)"
            add_report "  pinned $pin -> $elatest"
          fi
        done
      done
    }

    pub="${publicDir}"
    priv="${privateDir}"
    skillsPub="${skillsPubDir}"
    lab_pat="${homedir}/.config/gh/lab-skills-pat"

    # 認証を先に確定させる。対話シェルからは環境の gh 認証で足りるが、postActivation の
    # su - 経由では keyring が見えないため、agenix 管理の読み取り専用 PAT に切り替える。
    #
    # ここで必ず検証するのは、**認証が無くても gh skill update --dry-run が
    # "All skills are up to date." と報告する**ため（2026-07 実測）。確認できていないのに
    # 最新と表示すると、古い skill を静かに使い続けることになる。
    # 判定に gh auth status を使わないこと（2026-07-27 実測）。同コマンドは hosts.yml に
    # 登録された全アカウント／全ホストを検査し、**1件でも失敗すると exit 1** を返す。
    # su - 経由では keyring のアカウントが必ず失敗するため、有効な GH_TOKEN を渡した
    # フォールバック側まで道連れで非ゼロになり、PAT があるのに「認証なし」と誤判定していた。
    # gh api user は「いま実際に効いている資格情報で認証付き API を叩けるか」だけを見る
    # （未認証なら exit 4）。rate_limit は未認証でも 200 が返る経路があるため user を使う。
    token=""
    if gh api user --silent >/dev/null 2>&1; then
      : # 環境の認証を使う
    elif [ -r "$lab_pat" ] && GH_TOKEN="$(cat "$lab_pat")" gh api user --silent >/dev/null 2>&1; then
      token="$(cat "$lab_pat")"
      export GH_TOKEN="$token"
    else
      echo "agent-skills-outdated: GitHub 認証が無いため確認できなかった" >&2
      echo "  gh skill は未認証でも \"All skills are up to date.\" と報告するため、最新とは見なさない" >&2
      exit 2
    fi

    scan_gh_skill "$pub/agents/skills" "public vendor"
    scan_gh_skill "$priv/agents/skills" "private overlay"
    scan_gh_skill "$skillsPub" "personal-agent-skills"

    scan_vendor_pins "$pub/agents/skills" "public vendor"

    if [ -n "$report" ]; then
      printf '%s' "$report"
    fi

    if [ "$errors" -eq 1 ]; then
      echo "agent-skills-outdated: 判定できない箇所があった（上記参照）" >&2
      exit 2
    fi

    if [ "$updates" -eq 1 ]; then
      echo "agent skills: 更新があります。取り込みは sync スクリプトを手動実行して diff を目視すること"
      exit 1
    fi

    if [ "$quiet" -eq 0 ]; then
      echo "agent skills: all up to date"
    fi
    exit 0
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
    darwinSwitch
    darwinUpdate
    brewUpgradeAll
    brewUpdateReminder
    agentSkillsOutdated
    vpnCoexistenceApply
  ];

  # sleepctl 関連の sudo ルールは蓋のある機種だけ（macbook-air.nix）。
  # security.sudo.extraConfig は types.lines なので、複数モジュールの指定は連結される。
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

  # Codex App 用 auth.json（~/.codex/auth.json）の実ファイル化を監視して通知する。
  # CODEX_HOME 未指定の生 `codex login` が共有 symlink を上書きする事故（2026-07-11 発生）
  # を早期に気づけるようにする。修復はしない（cx 実行時に codex-auth-doctor が担当）。
  # スクリプト本体は agent-switch 配下に置き（自己完結・将来独立repo化予定）、nix はそれを叩くだけ。
  # /bin/bash を挟まずスクリプトを直に指す（shebang + 実行権限あり）。挟むと
  # 「ログイン項目とバックグラウンドで実行可能な項目」での表示名が basename 由来の
  # "bash" になり、同じ形の agent と区別がつかなくなるため。
  launchd.user.agents."codex-auth-watch" = {
    serviceConfig = {
      Label = "com.yosuke.codex-auth-watch";
      ProgramArguments = [
        "${publicDir}/tools/agent-switch/bin/codex-auth-watch"
      ];
      WatchPaths = [
        "${homedir}/.codex/auth.json"
      ];
      RunAtLoad = true;
      ThrottleInterval = 60;
      StandardOutPath = "${homedir}/Library/Logs/codex-auth-watch.log";
      StandardErrorPath = "${homedir}/Library/Logs/codex-auth-watch.log";
    };
  };

  # figma-pat.age の失効前チェック（週次月曜 10:00）。期限はスクリプト内の定数で管理。
  # /bin/bash を挟まない理由は codex-auth-watch と同じ（表示名が "bash" になるため）。
  launchd.user.agents.figmaPatExpiryCheck = {
    serviceConfig = {
      Label = "com.yosuke.figma-pat-expiry-check";
      ProgramArguments = [
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

  # cctag spoke は launchd 常駐をやめ、1つのターミナルで手動起動する運用に変更した
  # (2026-07-27)。同じ owner の Spoke が2つ繋がると Hub が古い接続を切り、KeepAlive で
  # 蘇った側と手動起動側が永久に蹴り合う再接続ストームになったため。ログも
  # ~/Library/Logs に隠れて気づきにくかった。復活させる場合は cctag 側の
  # 単一起動ガード (src/spoke/lock.ts) が入った版であることを確認すること。

  # sleepctl-watcher（蓋を閉じたときの監視エージェント）は macbook-air.nix にある。

  # Route *.ts.net DNS queries to Tailscale's resolver (MagicDNS with --accept-dns=false).
  environment.etc."resolver/ts.net" = {
    text = ''
      nameserver 100.100.100.100
    '';
  };

  system.activationScripts.postActivation.text = ''
    priv="${privateDir}"
    pub="${publicDir}"
    skillsPub="${skillsPubDir}"
    home="${homedir}"

    # postActivation は root で走る。素の mkdir でディレクトリを作ると root 所有になり、
    # 以後ユーザー権限で動く CLI が書き込めなくなる。実際 ~/.codex が root 所有で作られ、
    # codex が marketplace ディレクトリを作れず失敗した（2026-08-19、Mac Studio 初回）。
    # 既存機ではディレクトリが先にユーザー所有で存在するため顕在化しない。
    _userdir() {
      install -d -o ${username} -g staff "$1"
    }

    # 既に root 所有で作られてしまった場合の自己修復。
    for _d in "$home/.claude" "$home/.codex" "$home/.config" "$home/.local"; do
      if [ -d "$_d" ] && [ "$(stat -f %Su "$_d")" != "${username}" ]; then
        echo >&2 "repairing ownership: $_d"
        chown -R ${username}:staff "$_d" || true
      fi
    done

    _link() {
      local src="$1" dst="$2"
      _userdir "$(dirname "$dst")"
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
        chown ${username}:staff "$(dirname "$dst")"
        rm -f "$dst"
        install -m 600 -o ${username} -g staff "$src" "$dst"
      else
        echo "warning: agenix secret not ready: $src (skipping $dst)" >&2
      fi
    }

    # claude-memory: pending を manifest に確定し、memory を git 同期する。
    # postActivation は root で走るので **必ず su - でユーザー権限に落とす** —
    # root が claude-memory/ 配下や state にファイルを作ると Claude が更新できなくなる。
    # run-locked が host 単位の排他を取り、競合時は retry_wait にして exit 0 する。
    # network 不通・認証失敗も retry_wait 止まりで、switch は失敗させない。
    # promote と sync は **同じ lock の中で**連続実行する。別々に走らせると、
    # promote が pending を消費している最中に registrar が追記した行を取りこぼす。
    if [ -x "$priv/claude-memory.sh" ]; then
      su - ${username} -c "'$priv/claude-memory.sh' run-locked -- sh -c \"'$priv/claude-memory.sh' promote && '$priv/claude-memory.sh' sync --push\"" || true
      # 未移行の memory を **通知だけ**する（read-only）。移行は手動という決定
      # （decision-001）なので、放置に気づけるようにするのがこの行の役目。
      su - ${username} -c "'$priv/claude-memory.sh' check" || true
    fi

    # skills リポジトリが未 clone なら **通知する**。clone 自体は activation ではやらない
    # （private repo には gh の Keychain 認証が要り、root の非対話 activation からは
    # ログインキーチェーンを開けない。bootstrap.sh の Step 3 の担当）。
    # 黙って skip すると「skills が丸ごと無い」状態に気づけないので、毎回目に入るようにする。
    if [ ! -d "$priv/agents/skills" ]; then
      echo >&2 "warning: private skills が未配備（$priv が無い）"
      echo >&2 "  gh repo clone YosukeIida/dotfiles-private $priv && darwin-switch"
    fi
    if [ ! -d "$skillsPub" ]; then
      echo >&2 "warning: 自作の公開 skills が未配備（$skillsPub が無い）"
      echo >&2 "  gh repo clone YosukeIida/personal-agent-skills $skillsPub && darwin-switch"
    fi

    # private skills を ~/.claude/skills, ~/.codex/skills に追加
    if [ -d "$priv/agents/skills" ]; then
      for d in "$priv/agents/skills"/*/; do
        [ -d "$d" ] || continue
        _link "$d" "$home/.claude/skills/$(basename "$d")"
        _link "$d" "$home/.codex/skills/$(basename "$d")"
      done
    fi

    # public skills（personal-agent-skills repo）を ~/.claude/skills, ~/.codex/skills に追加。
    # root-level レイアウト（<skill>/SKILL.md）なので README.md 等は */ glob で自然に除外される。
    if [ -d "$skillsPub" ]; then
      for d in "$skillsPub"/*/; do
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
    _place "${
      config.age.secrets."cctag-slack_tmllab_workspace".path
    }" "$home/.config/cctag/slack_tmllab_workspace.env"
    _place "${config.age.secrets."gh-lab-skills-pat".path}" "$home/.config/gh/lab-skills-pat"

    # skill（研究室 tmllab-* と外部 vendor）の更新有無を通知のみ表示する
    # （brew outdated 相当）。内容は一切書き換えない（読み取り専用）。
    #
    # 以前は sync-lab-skills.sh --check を直接呼んでいたが、tmllab-* 以外の vendor skill も
    # 見たいので agent-skills-outdated に集約した。同コマンドは gh の keyring 認証が
    # 使えない場合に限り agenix の PAT へフォールバックする（su - 経由の非対話 activation
    # からはログインキーチェーンを開けないため）。上の _place より後に置くこと。
    #
    # exit 1 は「更新あり」なので失敗ではない。TMLlabメンバーでない・アクセス不可・
    # PAT未配備でも正常終了するようコマンド側で担保しているが、switch を絶対に
    # 失敗させないため || true も残す。
    su - ${username} -c "${agentSkillsOutdated}/bin/agent-skills-outdated --quiet" || true

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

    # arc-favorites: 新マシンで Arc の Favorites を移すときに使う（Favorites は
    # machineID 紐づきで同期されないため。詳細は private の docs/arc-profiles.md）。
    _link "$pub/scripts/arc-favorites" "$home/.local/bin/arc-favorites"

    # 明示的に許可したアプリだけ quarantine 属性を解除する（quarantineAllowlist 参照）。
    # 再インストール／更新でダウンロードするたびに quarantine が再付与されるため毎 switch 実行する。
    # shellcheck disable=SC2043  # リストが1件でも将来増える前提の for ループ
    for app in ${lib.concatMapStringsSep " " (p: ''"${p}"'') quarantineAllowlist}; do
      if [ -e "$app" ]; then
        xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
      fi
    done

    # 上と同じだが glob 対応（quarantineGlobAllowlist 参照）。
    for pattern in ${lib.concatStringsSep " " quarantineGlobAllowlist}; do
      for app in $pattern; do
        if [ -e "$app" ]; then
          xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
        fi
      done
    done
  '';
}
