# agent-switch — account switchers for Claude Code (cc) and Codex (cx)
#
# Source this file from your zshrc:
#   source /path/to/agent-switch/agent-switch.plugin.zsh
#
# This plugin has ZERO side effects at source time: it only defines functions.
# Default-account exports (e.g. `export CODEX_HOME=~/.codex-work`) belong in
# your own zshenv/zshrc, guarded with [[ -d ... ]] — see README.md.
#
# Configuration (set before sourcing; all optional):
#   AGSW_CLAUDE_HOME_PREFIX  account dir prefix       (default: $HOME/.claude-)
#   AGSW_CODEX_HOME_PREFIX   account dir prefix       (default: $HOME/.codex-)
#   AGSW_CODEX_APP_AUTH      app-facing auth symlink  (default: $HOME/.codex/auth.json)
#   AGSW_CLAUDE_ASSETS_DIR   dotfiles-managed settings for setup-claude-account (optional)

typeset -g _AGSW_DIR="${0:A:h}"

source "$_AGSW_DIR/lib/claude.zsh"
source "$_AGSW_DIR/lib/codex.zsh"
