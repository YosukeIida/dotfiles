#!/bin/bash
# Cloudflare Access SSH proxy.
#
# cf サービストークンは agenix で暗号化され、darwin-switch 時に
# ~/.config/cf/token.env (mode 600) へ復号配置される（CF_ID / CF_SECRET）。
# 互換のため、env が無ければ macOS Keychain にフォールバックする。
set -eu

TOKEN_ENV="$HOME/.config/cf/token.env"

if [ -r "$TOKEN_ENV" ]; then
  # shellcheck disable=SC1090
  . "$TOKEN_ENV"
fi

: "${CF_ID:=}"
: "${CF_SECRET:=}"

if [ -z "$CF_ID" ] || [ -z "$CF_SECRET" ]; then
  CF_ID=$(security find-generic-password -s "cf-service-token-id" -a "cf" -w 2>/dev/null || true)
  CF_SECRET=$(security find-generic-password -s "cf-service-token-secret" -a "cf" -w 2>/dev/null || true)
fi

exec cloudflared access ssh --hostname "$1" --id "$CF_ID" --secret "$CF_SECRET"
