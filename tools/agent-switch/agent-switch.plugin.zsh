# agent-switch — account switchers for Claude Code (cc) and Codex (cx)
#
# Source this file from your zshrc:
#   source /path/to/agent-switch/agent-switch.plugin.zsh
#
# At source time this plugin defines functions and never modifies any file.
# The only visible action is a read-only warning check (interactive shells only)
# when Codex's app-facing auth.json is a real file or a broken symlink — it prints
# a warning but repairs nothing (repair happens only on an explicit `cx`). See README.md.
# Default-account exports (e.g. `export CODEX_HOME=~/.codex-work`) belong in
# your own zshenv/zshrc, guarded with [[ -d ... ]] — see README.md.
#
# Configuration (set before sourcing; all optional):
#   AGSW_CLAUDE_HOME_PREFIX  account dir prefix       (default: $HOME/.claude-)
#   AGSW_CODEX_HOME_PREFIX   account dir prefix       (default: $HOME/.codex-)
#   AGSW_CODEX_APP_AUTH      app-facing auth symlink  (default: $HOME/.codex/auth.json)
#   AGSW_CLAUDE_ASSETS_DIR   dotfiles-managed settings for setup-claude-account (optional)
#   AGSW_ALLOW_RAW_LOGIN     set to 1 to bypass the codex login/logout symlink guard

typeset -g _AGSW_DIR="${0:A:h}"

source "$_AGSW_DIR/lib/claude.zsh"
source "$_AGSW_DIR/lib/codex.zsh"
