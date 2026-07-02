#!/usr/bin/env bash
# ~/.codex/config.toml から system layer 管理へ移した設定だけを除去する。
set -euo pipefail

config="${CODEX_HOME:-$HOME/.codex}/config.toml"

if [ ! -f "$config" ]; then
  echo "Codex user config not found, skipping: $config"
  exit 0
fi

# マルチアカウント運用では ~/.codex-<name>/config.toml は ~/.codex/config.toml への
# symlink。末尾の mv が symlink を実ファイルで置き換えて共有を壊さないよう、実体を解決する。
config="$(readlink -f "$config")"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

awk '
  # Keep these lists in sync with the durable settings managed in
  # codex/config.toml. Any managed key left in ~/.codex/config.toml has higher
  # precedence than /etc/codex/config.toml and will silently override it.
  function managed_table(header) {
    return header == "[mcp_servers.exa]"
  }

  BEGIN {
    current_table = ""
  }

  /^\[/ {
    current_table = $0
    skip = managed_table($0)
    in_features = ($0 == "[features]")
  }

  skip {
    next
  }

  current_table == "" &&
  /^(model|model_reasoning_effort|personality|web_search|model_context_window|model_auto_compact_token_limit|approval_policy|sandbox_mode|cli_auth_credentials_store|mcp_oauth_credentials_store)[[:space:]]*=/ {
    next
  }

  in_features && /^multi_agent[[:space:]]*=/ {
    next
  }

  {
    print
  }
' "$config" > "$tmp"

if cmp -s "$config" "$tmp"; then
  echo "Codex user config already migrated: $config"
  exit 0
fi

timestamp="$(date +%Y%m%d%H%M%S)"
backup="$config.bak.$timestamp"
cp -p "$config" "$backup"

mode="$(stat -f "%Lp" "$config" 2>/dev/null || stat -c "%a" "$config" 2>/dev/null || echo 600)"
chmod "$mode" "$tmp"
mv "$tmp" "$config"
trap - EXIT

echo "Migrated Codex user config: $config"
echo "Backup: $backup"
