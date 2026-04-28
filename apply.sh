#!/usr/bin/env bash
set -euo pipefail

host=$(hostname -s)
echo "Applying nix-darwin config for: $host"
sudo darwin-rebuild switch --flake ".#$host" "$@"
