#!/usr/bin/env bash
# Claude Code プラグインを settings.json の enabledPlugins へ宣言的に同期するスクリプト。
# install だけでなく uninstall もする: enabledPlugins から**キーごと**消えたプラグインは
# 次の darwin-switch で uninstall される。skills / subagents のリンク切れ掃除や
# homebrew の cleanup="zap" と同じ「宣言が正本・削除も追従」の作法に揃えるため。
#
# `"plugin": false` は uninstall せず残す。これはこのスクリプトが定める規約で、
# 「一時的に切りたいだけなら false / 消したいならキーごと削除」を区別するため
# （実績としては enabledPlugins に false が書かれたことは一度も無い。Claude Code の
# enable/disable 状態は settings.json ではなく Claude Code 側の state に持たれており、
# UI で disable してもここに false は書かれない）。
#
# 既知の制限: `claude plugins list --json` は「依存として自動インストールされた」
# ことを示すフィールドを持たない（enabled/id/installPath/installedAt/lastUpdated/
# mcpServers/scope/version のみ）。将来そういう依存が入ると毎 switch で uninstall を
# 試みることになる。マーカが露出したら除外条件を足すこと。
#
# user スコープだけを対象にする。project / local スコープはリポジトリ側の宣言なので
# machine 単位の switch が触ってはいけない。
set -euo pipefail

# comm は sort と同じ照合順序を要求する。ロケール差で誤差分が出ないよう固定する。
export LC_ALL=C

SETTINGS="$HOME/.claude/settings.json"

# claude CLI 未導入時（新マシンの初回 darwin-switch では cask がまだ入っていない）は
# 何もせず終了する。codex/install-plugins.sh と同じガード。導入後の再 switch で入る。
if ! command -v claude >/dev/null 2>&1; then
  echo "claude command not found, skipping plugin sync (re-run darwin-switch after install)" >&2
  exit 0
fi

# jq は nix の home.packages 由来（nix/home/packages.nix）。初回 switch の途中など
# まだ PATH に乗っていない場合は何もせず抜ける。次の switch で同期される。
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found, skipping plugin sync (re-run darwin-switch after nix packages land)" >&2
  exit 0
fi

if [ ! -f "$SETTINGS" ]; then
  echo "settings.json not found, skipping"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# extraKnownMarketplaces を登録
# `claude plugins marketplace add` は <source> 一つだけを取り、marketplace名は
# 相手の marketplace.json の name フィールドから自動的に決まる(この dict の
# key は決定に関与しない、あくまで人間向けのラベル)。
jq -r '.extraKnownMarketplaces // {} | to_entries[]
       | select(.value.source.source == "github") | .value.source.repo' "$SETTINGS" \
  | while IFS= read -r repo; do
      [ -n "$repo" ] || continue
      claude plugins marketplace add "$repo" >/dev/null 2>&1 || true
    done

# marketplace add は登録するだけで、ローカルの索引が古いままのことがある。その状態だと
# enabledPlugins にあるプラグインが「marketplace に見つからない」で落ちる
# （新マシンの初回 darwin-switch で agmsg@fujibee-agmsg が実際に失敗した。上流の
# marketplace.json には存在していた）。install の前に全 marketplace を上流に合わせる。
# 名前を省略すると全件が対象。
claude plugins marketplace update >/dev/null 2>&1 || true

# 宣言側
#   declared: enabledPlugins のキー全体（true/false 問わず）= 「消さない」集合
#   wanted  : true のものだけ                              = 「入れる」集合
jq -r '.enabledPlugins // {} | keys[]' "$SETTINGS" | sort >"$work/declared.txt"
jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | .key' "$SETTINGS" | sort >"$work/wanted.txt"

# 実体側: user スコープのインストール済みプラグイン。
# 取得に失敗したら空として扱う（uninstall 側は何もしなくなる = 安全側に倒れる）。
: >"$work/installed.txt"
claude plugins list --json 2>/dev/null \
  | jq -r '.[] | select(.scope == "user") | .id' \
  | sort >"$work/installed.txt" || : >"$work/installed.txt"

# 宣言にあって未インストールのものを install
comm -23 "$work/wanted.txt" "$work/installed.txt" | while IFS= read -r plugin; do
  [ -n "$plugin" ] || continue
  echo "installing: $plugin"
  claude plugins install "$plugin"
done
comm -12 "$work/wanted.txt" "$work/installed.txt" | sed 's/^/already installed: /'

# 宣言から消えたものを uninstall。
# 掃除の失敗で switch 全体を止めない（install 側は従来どおり set -e で止まる）。
comm -13 "$work/declared.txt" "$work/installed.txt" | while IFS= read -r plugin; do
  [ -n "$plugin" ] || continue
  echo "uninstalling (enabledPlugins に無い): $plugin"
  claude plugins uninstall "$plugin" --scope user \
    || echo "warning: uninstall failed: $plugin" >&2
done
