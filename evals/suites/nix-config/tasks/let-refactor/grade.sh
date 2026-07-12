#!/usr/bin/env bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out=$(nix eval --json --file ./paths.nix) || { echo "nix eval failed"; exit 1; }
python3 - "$out" "$TASK_DIR/expected.json" <<'EOF'
import json, sys
got = json.loads(sys.argv[1])
expected = json.load(open(sys.argv[2]))
assert got == expected, f"eval result differs:\ngot      {got}\nexpected {expected}"
EOF
count=$(grep -c '/Users/yosuke/\.config' paths.nix)
[ "$count" -eq 1 ] || { echo "literal appears $count times (want 1)"; exit 1; }
echo "pass"
