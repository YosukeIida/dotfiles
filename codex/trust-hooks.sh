#!/usr/bin/env bash
# dotfiles が宣言した Codex の hook を、各 CODEX_HOME で信頼済みにする（darwin-switch から実行）。
#
# Codex は user layer と plugin の hook を、`/hooks` で承認するまで実行しない。承認は
# `[hooks.state."<key>"] trusted_hash` として config.toml に記録され、key は
# `<CODEX_HOME>/hooks.json:<event>:<group>:<handler>` なので CODEX_HOME ごとに別扱いになる
# （~/.codex / ~/.codex-personal / ~/.codex-labteam で同じ hooks.json を3回承認することになる）。
# hook の中身が変わる（plugin 更新を含む）と hash が変わり、再承認を求められる。
#
# ここでは TUI の `/hooks` と同じ app-server API を叩く: `hooks/list` で currentHash を得て、
# `config/batchWrite` で trusted_hash を書く（openai/codex codex-rs/tui/src/hooks_rpc.rs）。
# hash は Codex 自身が計算するので、こちらで hash の作り方を再現しない。
#
# 承認するのは dotfiles が宣言したものだけ:
#   - user layer: <CODEX_HOME>/hooks.json（dotfiles の codex/hooks.json への symlink）
#   - plugin: codex/plugins.txt に列挙した plugin
# project layer（repo の .codex/）の hook は repo の中身なので承認しない。
set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "codex command not found, skipping hook trust" >&2
  exit 0
fi

plugins_file="$(dirname "$0")/plugins.txt"
plugins_json="$(grep -vE '^[[:space:]]*(#|$)' "$plugins_file" 2>/dev/null | jq -R . | jq -sc . || echo '[]')"

trust_home() {
  local home="$1" line hooks updates count
  coproc APP { CODEX_HOME="$home" exec codex app-server 2>/dev/null; }
  # shellcheck disable=SC2154  # APP_PID は coproc が定義する
  local pid="$APP_PID"

  send() { printf '%s\n' "$1" >&"${APP[1]}"; }
  wait_id() {
    while IFS= read -r -t 30 line <&"${APP[0]}"; do
      if [[ "$(jq -r '.id // empty' <<<"$line")" == "$1" ]]; then
        printf '%s\n' "$line"
        return 0
      fi
    done
    return 1
  }

  send '{"id":0,"method":"initialize","params":{"clientInfo":{"name":"dotfiles-trust-hooks","version":"0"}}}'
  wait_id 0 >/dev/null || { echo "$home: app-server did not initialize" >&2; kill "$pid" 2>/dev/null; return 1; }
  send '{"method":"initialized"}'

  send "$(jq -nc --arg cwd "$HOME" '{id:1,method:"hooks/list",params:{cwds:[$cwd]}}')"
  hooks="$(wait_id 1)" || { echo "$home: hooks/list failed" >&2; kill "$pid" 2>/dev/null; return 1; }

  updates="$(jq -c --arg src "$home/hooks.json" --argjson plugins "$plugins_json" '
    [.result.data[].hooks[]
     | select(.trustStatus == "untrusted" or .trustStatus == "modified")
     | select((.source == "user" and .sourcePath == $src)
              or (.source == "plugin" and (.pluginId as $p | $plugins | index($p))))
     | {key: .key, value: {trusted_hash: .currentHash}}]
    | from_entries' <<<"$hooks")"
  count="$(jq 'length' <<<"$updates")"

  if [[ "$count" -gt 0 ]]; then
    send "$(jq -nc --argjson v "$updates" '{id:2,method:"config/batchWrite",params:{
      edits:[{keyPath:"hooks.state",value:$v,mergeStrategy:"upsert"}],
      filePath:null,expectedVersion:null,reloadUserConfig:true}}')"
    line="$(wait_id 2)" || { echo "$home: config/batchWrite failed" >&2; kill "$pid" 2>/dev/null; return 1; }
    if [[ "$(jq -r 'has("error")' <<<"$line")" == "true" ]]; then
      echo "$home: config/batchWrite error: $(jq -c .error <<<"$line")" >&2
      kill "$pid" 2>/dev/null
      return 1
    fi
    jq -r --arg home "$home" 'keys[] | "trusted (\($home)): \(.)"' <<<"$updates"
  fi

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

rc=0
for home in "$HOME/.codex" "$HOME"/.codex-*; do
  [[ -f "$home/config.toml" ]] || continue
  trust_home "$home" || rc=1
done
exit "$rc"
