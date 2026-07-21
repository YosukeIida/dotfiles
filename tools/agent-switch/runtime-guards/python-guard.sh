#!/usr/bin/env bash
# Claude Code 専用のsystem python誤用ガード。
# claude() ラッパーが PATH 先頭（nodeと同じ扱い）に注入するため、/usr/bin/python3 より
# 必ず先に見つかる。その代わり、このスクリプト自身が「devShellが有効なら本物のpythonに
# 委譲する」判定を行うことで、PATHの位置だけでは表現できない優先順位を実現する。
set -uo pipefail

prog="$(basename "$0")" # "python3" または "python"
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$prog"

# 1. nix devShell が有効（IN_NIX_SHELL）なら、devShell が提供する本物の python に委譲する
#    （自分自身と /usr/bin/<prog> は候補から除外する）。
if [[ -n "${IN_NIX_SHELL:-}" ]]; then
  while IFS= read -r candidate; do
    if [[ "$candidate" != "$self" && "$candidate" != "/usr/bin/$prog" ]]; then
      exec "$candidate" "$@"
    fi
  done < <(type -ap "$prog" 2>/dev/null)
fi

# 2. devShellが無くても、pyproject.toml/uv.lock があれば uv run python に委譲する
dir="$PWD"
while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
  if [[ -f "$dir/pyproject.toml" || -f "$dir/uv.lock" ]]; then
    exec uv run python "$@"
  fi
  dir="$(dirname "$dir")"
done

# 3. どちらの根拠も無ければ拒否する（/usr/bin の system python への無自覚なフォールバックを防ぐ）
echo "この場所はpythonプロジェクトとして認識されていません（pyproject.toml/uv.lockが見つかりません）。" >&2
echo "system pythonは方針上使用しません。'uv run python' か 'uvx' を使ってください。" >&2
exit 1
