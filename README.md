# agent-setup

One command installs Claude Code, Codex CLI, and Cursor CLI, then a curated
plugin/skill set into all three at the user level — across macOS, Linux, WSL,
and Git-Bash on Windows. (Native-Windows PowerShell driver: see Plan 2.)

## Quick start

```bash
git clone https://github.com/host452b/agent-setup.git
cd agent-setup
bash install.sh --dry-run        # preview: prints the plan, changes nothing
bash install.sh                  # install (prompts before high-risk steps)
```

Requires `jq`. Install hint is printed if missing.

## Flags

- `--dry-run` / `--plan` — print the resolved plan, mutate nothing
- `--status` — show what's already installed
- `--check-prereqs` — report tool presence (jq, git, node, bun, agents)
- `--install-prereqs` — opt-in: auto-install prereqs via brew/apt/winget
- `--agent <claude|codex|cursor>` — scope to one agent
- `--plugin <name>` — scope to one plugin
- `--only-method <type>` — scope to one method type
- `--agents-only` — install only the agent binaries (step 1)
- `--yes` — auto-confirm high-risk steps
- `--non-interactive` — CI mode; fail on any privileged step

## What gets installed

Agents: Claude Code, Codex CLI, Cursor CLI.
Plugins/skills: superpowers, ponytail, gstack, caveman, taste-skill,
ui-ux-pro-max, open-design, prompt-polish.

Coverage varies by agent — Cursor is a best-effort integration target
(no plugin-install CLI); see `docs/cursor.md`. The full plugin × agent ×
method matrix lives in `manifest.json`.

## Adding a plugin

Edit `manifest.json` (validated against `manifest.schema.json`). No script
changes needed for supported method types.
