#!/usr/bin/env bash
# Codex プラグインを plugins.txt の希望状態へ冪等に同期する。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugins_file="$script_dir/plugins.txt"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex command not found, skipping plugin installation" >&2
  exit 0
fi

if [ ! -f "$plugins_file" ]; then
  echo "Codex plugin list not found, skipping: $plugins_file" >&2
  exit 0
fi

while IFS= read -r plugin; do
  case "$plugin" in
    ""|\#*)
      continue
      ;;
  esac

  echo "ensuring Codex plugin: $plugin"
  codex plugin add "$plugin" --json >/dev/null
done < "$plugins_file"
