#!/usr/bin/env bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmp -s test_ranges.py "$TASK_DIR/fixture/test_ranges.py" || { echo "tests modified"; exit 1; }
python3 -m unittest discover -s . -p 'test_*.py' -q || { echo "tests failed"; exit 1; }
echo "pass"
