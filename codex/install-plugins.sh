#!/usr/bin/env bash
# Codex プラグインを marketplaces.txt / plugins.txt の希望状態へ冪等に同期する。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
marketplaces_file="$script_dir/marketplaces.txt"
plugins_file="$script_dir/plugins.txt"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex command not found, skipping plugin installation" >&2
  exit 0
fi

# openai-curated / openai-primary-runtime / openai-bundled は Codex 組み込みで
# 登録不要。サードパーティ（例: pbakaus/impeccable）はここで明示的に登録する。
if [ -f "$marketplaces_file" ]; then
  while IFS= read -r marketplace; do
    case "$marketplace" in
      ""|\#*)
        continue
        ;;
    esac

    echo "ensuring Codex marketplace: $marketplace"
    codex plugin marketplace add "$marketplace" >/dev/null
  done < "$marketplaces_file"
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
