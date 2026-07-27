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
#    候補リストは fd 3 で読む: `done < <(...)` だと exec される python の stdin が
#    候補リストに差し替わり、`python3 - <<EOF` 形式（herdr の SessionStart フック等）が
#    「候補パスの残りを Python コードとして解釈 → SyntaxError」で全滅するため。
#    （mapfile は macOS の bash 3.2 に無いので使わない）
if [[ -n "${IN_NIX_SHELL:-}" ]]; then
  while IFS= read -r candidate <&3; do
    if [[ "$candidate" != "$self" && "$candidate" != "/usr/bin/$prog" ]]; then
      exec "$candidate" "$@"
    fi
  done 3< <(type -ap "$prog" 2>/dev/null)
fi

# 2. devShellが無くても、pyproject.toml/uv.lock があれば uv run python に委譲する
dir="$PWD"
while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
  if [[ -f "$dir/pyproject.toml" || -f "$dir/uv.lock" ]]; then
    exec uv run python "$@"
  fi
  dir="$(dirname "$dir")"
done

# herdr の Claude 統合フック（~/.claude/hooks/herdr-agent-state.sh）は、pane に
# session id を報告するために標準ライブラリのみの python を必要とする
# （unix socket に JSON を 1 行書くだけ）。HERDR_HOOK_INPUT_FILE はこのフックが
# python を呼ぶときだけ設定する変数なので、対象を正確に絞れる。
# パッケージは一切入れないので「system python を汚さない」方針は維持される。
if [[ -n "${HERDR_HOOK_INPUT_FILE:-}" && -x "/usr/bin/$prog" ]]; then
  exec "/usr/bin/$prog" "$@"
fi

# 3. どちらの根拠も無ければ拒否する（/usr/bin の system python への無自覚なフォールバックを防ぐ）
echo "この場所はpythonプロジェクトとして認識されていません（pyproject.toml/uv.lockが見つかりません）。" >&2
echo "system pythonは方針上使用しません。'uv run python' か 'uvx' を使ってください。" >&2
exit 1
