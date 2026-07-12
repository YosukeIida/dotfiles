#!/usr/bin/env bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmp -s test_users.py "$TASK_DIR/fixture/test_users.py" || { echo "tests modified"; exit 1; }
grep -q 'def _normalize_email' users.py || { echo "_normalize_email helper not found"; exit 1; }
# 重複解消の確認: 検証ロジックの実体が1箇所にまとまっていること
count=$(grep -c 'rsplit("@", 1)' users.py || true)
[ "$count" -le 1 ] || { echo "validation logic still duplicated ($count sites)"; exit 1; }
python3 -m unittest discover -s . -p 'test_*.py' -q || { echo "tests failed"; exit 1; }
echo "pass"
