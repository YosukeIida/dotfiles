#!/usr/bin/env bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f fonts.nix ] || { echo "fonts.nix not created"; exit 1; }
grep -q 'import \./fonts\.nix' config.nix || { echo "config.nix does not import ./fonts.nix"; exit 1; }
out=$(nix eval --json --file ./config.nix) || { echo "nix eval config.nix failed"; exit 1; }
fonts=$(nix eval --json --file ./fonts.nix) || { echo "nix eval fonts.nix failed"; exit 1; }
python3 - "$out" "$fonts" "$TASK_DIR/expected.json" <<'EOF'
import json, sys
got = json.loads(sys.argv[1])
fonts = json.loads(sys.argv[2])
expected = json.load(open(sys.argv[3]))
assert got == expected, f"config.nix eval differs:\ngot      {got}\nexpected {expected}"
assert fonts == expected["fonts"], f"fonts.nix should eval to the fonts list, got {fonts}"
EOF
echo "pass"
