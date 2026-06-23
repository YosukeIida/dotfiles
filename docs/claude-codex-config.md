# Claude Code / Codex configuration map

Claude Code and Codex share instructions and personal skills, but their
configuration files divide durable configuration and local state differently.

## Managed configuration

| Purpose | Source in this repository | Runtime location |
|---|---|---|
| Shared instructions | `agents/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` |
| Public skills | `agents/skills/*` | `~/.claude/skills/*`, `~/.codex/skills/*` |
| Private skills | `dotfiles-private/agents/skills/*` | `~/.claude/skills/*`, `~/.codex/skills/*` |
| Claude settings and plugin declarations | `claude/settings.json` | `~/.claude/settings.json` |
| Codex durable settings and MCP declarations | `codex/config.toml` | `/etc/codex/config.toml` |
| Codex plugin desired state | `codex/plugins.txt` | Installed by `codex/install-plugins.sh` |

Managed configuration files and skill directories are symlinked by
`darwin-switch`. Codex plugins are the exception: the switch applies their
desired state through the Codex CLI because plugin installation state must be
recorded in the user config. Public skills are linked first and private skills
are linked afterward, so a private skill with the same directory name takes
precedence.

## Local state excluded from dotfiles

| Product | Local state |
|---|---|
| Claude Code | `~/.claude.json`, `~/.claude/plugins/`, OAuth credentials, project history |
| Codex | `~/.codex/config.toml`, `~/.codex/auth.json`, `~/.codex/plugins/`, sessions, logs, caches |

Claude stores project trust, UI state, and user MCP registrations in
`~/.claude.json`, separately from the managed `settings.json`.

Codex writes both user preferences and local state to `~/.codex/config.toml`.
To avoid committing `[projects.*]`, desktop settings, marketplace cache paths,
and plugin-generated MCP settings, durable defaults are placed in the official
system configuration layer at `/etc/codex/config.toml`. The user config has
higher precedence and remains writable by Codex.

Repository-specific Codex settings belong in that repository's
`.codex/config.toml`; they are not part of this global configuration.

## Plugins and MCP

Claude plugin declarations live in its managed settings file. Codex's plugin
manager records installation state in the user config, even when the same
`[plugins.*]` table exists in the system config. Therefore Codex plugin desired
state is kept in `codex/plugins.txt`, and `darwin-switch` idempotently runs
`codex plugin add` for each entry. The generated user-config entries,
downloaded bundles, and marketplace snapshots remain local.

MCP server definitions may be managed, but OAuth credentials are always local.
After provisioning a new machine, authenticate managed MCP servers explicitly:

```bash
codex mcp login exa
```

Claude's official Exa plugin includes both the hosted Exa MCP server and an Exa
research skill. Do not also keep a standalone user-scoped Exa MCP registration;
authenticate the plugin-provided server and remove the duplicate.

## Migration

After changing from the old copied Codex config to the system layer, run:

```bash
darwin-switch
bash ~/workspace/github.com/YosukeIida/dotfiles/codex/migrate-user-config.sh
```

The migration script creates a timestamped backup and removes only settings now
owned by `/etc/codex/config.toml`. Project trust, desktop settings,
marketplaces, notifications, and plugin-generated local MCP servers remain in
`~/.codex/config.toml`.
