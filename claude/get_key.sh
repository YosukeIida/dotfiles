#!/bin/sh
set -eu
ENV_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/anthropic.env"
# shellcheck disable=SC1090
. "$ENV_FILE"
printf "%s" "$ANTHROPIC_API_KEY"


