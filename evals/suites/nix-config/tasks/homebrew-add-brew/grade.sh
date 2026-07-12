#!/usr/bin/env bash
set -euo pipefail
out=$(nix eval --json --file ./homebrew.nix) || { echo "nix eval failed"; exit 1; }
python3 - "$out" <<'EOF'
import json, sys
d = json.loads(sys.argv[1])
brews, casks = d["brews"], d["casks"]
assert "ripgrep" in brews, f"ripgrep missing: {brews}"
assert brews == sorted(brews), f"brews not sorted: {brews}"
assert brews == ["backlog-md", "gh", "jq", "ripgrep"], f"unexpected brews: {brews}"
assert casks == ["cmux", "obsidian"], f"casks changed: {casks}"
EOF
echo "pass"
