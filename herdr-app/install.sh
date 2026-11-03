#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
dst="${HERDR_APP_HOME:-$HOME/.config/herdr-app}"
state="$dst/.dotfiles-managed"
mkdir -p "$dst/layouts" "$dst/mods"

# symlink にしないのは、Herdr app が symlink の mod folder を hot reload しないため
# （yama-lei/herdr-editor-layout の install.sh）。Herdr app が mod folder に書く
# jsconfig.json・gpui-kit.d.ts・隠しファイルは除外し、--delete でも消さない。
managed=()
for d in "$src"/mods/*/; do
  n=$(basename "$d")
  rsync -a --delete --exclude gpui-kit.d.ts --exclude jsconfig.json --exclude '.*' "$d" "$dst/mods/$n/"
  managed+=("mods/$n")
done
for f in "$src"/layouts/*.json; do
  cp "$f" "$dst/layouts/"
  managed+=("layouts/$(basename "$f")")
done

if [ -f "$state" ]; then
  while read -r p; do
    [[ -n "$p" && " ${managed[*]} " != *" $p "* ]] && rm -rf "${dst:?}/$p"
  done < "$state"
fi
printf '%s\n' "${managed[@]}" > "$state"
