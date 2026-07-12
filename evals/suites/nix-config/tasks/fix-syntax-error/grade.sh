#!/usr/bin/env bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out=$(nix eval --json --file ./services.nix) || { echo "nix eval failed"; exit 1; }
python3 - "$out" "$TASK_DIR/expected.json" <<'EOF'
import json, sys
got = json.loads(sys.argv[1])
expected = json.load(open(sys.argv[2]))
assert got == expected, f"eval result differs:\ngot      {got}\nexpected {expected}"
EOF
echo "pass"
