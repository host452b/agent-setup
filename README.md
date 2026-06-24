# agent-setup

One command installs your coding agents **and** their plugins/skills — reproducibly, across **macOS, Linux, WSL, and Windows (Git-Bash)**.

It installs three agents — **Claude Code**, **Codex CLI**, **Cursor CLI** — then a curated plugin/skill set into all three at the user level, as far as each agent's install surface allows. Everything is declared in one `manifest.json`; the installer just reads it.

> Native-Windows PowerShell (`install.ps1` / `bootstrap.ps1`) is available (experimental) — see [Status](#status) and the Windows note below.

## One-line install

```bash
# macOS / Linux / WSL / Git-Bash (Windows)
curl -fsSL https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.sh | bash

# preview the full plan without changing anything
curl -fsSL https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.sh | bash -s -- --dry-run
```

```powershell
# native Windows PowerShell (experimental)
irm https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.ps1 | iex
# with flags: download then run — irm .../bootstrap.ps1 -OutFile bootstrap.ps1; ./bootstrap.ps1 -DryRun
```

Prerequisites (`jq`, `git`, `node`, `bun`) are **auto-installed by default** before anything else — `bun` via its user-level installer (no sudo), the rest via your package manager. Pass `--skip-prereqs` to manage them yourself. (`jq` is still required to parse the manifest; on a locked-down box without it, install `jq` first.)

**Each step shows a 3-second countdown then auto-confirms (yes)** — press `n` within the window to decline that step. Pass `--yes` to skip the countdown entirely, or `--non-interactive` to decline every privileged step (CI-safe). Use `--dry-run` to review first. Agent installers run unattended (e.g. `CODEX_NON_INTERACTIVE=1`) so they don't block on their own prompts.

Prefer to inspect before running (recommended — see [Security](docs/security.md)):

```bash
curl -fsSL https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.sh -o bootstrap.sh
less bootstrap.sh
bash bootstrap.sh
```

The bootstrap caches the repo at `~/.agent-setup` (override with `AGENT_SETUP_HOME`); re-runs are fast and idempotent. After each run a grouped report (OK / SKIPPED / MANUAL / FAILED, with reasons) prints and is saved to `~/.agent-setup/last-install-report.txt`.

## Manual install

```bash
git clone https://github.com/host452b/agent-setup.git
cd agent-setup
bash install.sh --dry-run     # preview
bash install.sh               # install (prompts before high-risk steps)
```

Requires `jq` (the installer prints an install hint if it's missing).

## What gets installed

**Agents:** Claude Code · Codex CLI · Cursor CLI.

**Plugins / skills** (per-agent coverage — the full matrix lives in [`manifest.json`](manifest.json)):

| Plugin | Claude Code | Codex CLI | Cursor |
|---|---|---|---|
| superpowers | ✅ native | ⚠️ partial | 📋 manual |
| ponytail | ✅ native | ⚠️ partial | 📋 manual |
| gstack | ✅ native | ✅ native | N/A ³ |
| caveman | ✅ auto ¹ | ✅ auto ¹ | ✅ auto ¹ |
| taste-skill | ✅ auto ² | ✅ auto ² | ✅ auto ² |
| ui-ux-pro-max | ✅ native | ✅ native | ✅ native |
| open-design | 📋 manual | 📋 manual | 📋 manual |
| prompt-polish | ✅ native | ⚠️ partial | ✅ native |

`native` = fully scripted · `partial` = scripted with a trust/interactive step · `manual` = the installer prints exact steps (no CLI exists) · `N/A` = the tool itself has no support for that agent (reported as N/A, not a failure).

¹ caveman runs one installer (`curl … | bash`) that auto-detects and configures every supported agent present.
² taste-skill installs via `npx skills add`, which lands in the detected agents' skills directories.
³ gstack's installer has no Cursor host (supports claude/codex/kiro/factory/opencode/openclaw/hermes/gbrain), so Cursor isn't a gstack target.

**Cursor is a best-effort integration target** — `cursor-agent` has no plugin-install CLI, so coverage comes from each tool's own cross-agent path (skills dir, rules file, MCP, `npx skills`). See [`docs/cursor.md`](docs/cursor.md).

## Flags

```
bash install.sh [flags]

  --dry-run | --plan     print the resolved plan, change nothing
  --status               show what is already installed
  --check-prereqs        report tool presence (jq, git, node, bun, agents)
  --skip-prereqs         do NOT auto-install prerequisites (default: auto-install)
  --agent <name>         scope to one agent: claude | codex | cursor
  --plugin <name>        scope to one plugin
  --only-method <type>   scope to one method type
  --agents-only          install only the agent binaries (step 1)
  --yes                  skip the 3s countdown; confirm everything immediately
  --non-interactive      decline every privileged step (CI-safe)
                         (default: 3s countdown per step, then auto-yes)
```

Flags pass through the bootstrap too: `… | bash -s -- --plugin gstack --dry-run`.

## How it works

`manifest.json` (validated against `manifest.schema.json`) is the single source of truth. Each `(plugin, agent)` target declares a **method**, its **coverage**, supported **platforms**, **safety** metadata, idempotency **checks**, and a **conflict policy**. The driver runs a fixed order:

```
detect OS → verify jq → validate manifest → resolve plan
   → privilege preflight → execute (or dry-run) → after-checks → report
```

Method types include `claude-plugin` / `codex-plugin` (marketplace + install), `shell-installer` (`curl`-then-run), `npx-skills`, `git-setup` (`./setup --host …`), `npm-cli` (`uipro`), `od-mcp` (`od mcp install`), `file-copy`, and `manual`. Adding a plugin is usually just a manifest edit — no script change.

## Security

- **Dry-run first** — `--dry-run` prints every command and changes nothing.
- **Confirmation** — steps that run remote code or need admin prompt unless `--yes`; `--non-interactive` refuses them.
- **download-then-run** — remote installers are downloaded to a temp file and executed from disk, never piped straight into a shell.
- **PATH-shadow guard** — external tools are resolved by real path and verified before use (notably `od`, which collides with the unix octal-dump binary).
- **Least privilege** — the script is never run under sudo wholesale; only the specific steps that need it request it, surfaced in the plan up front.

The `curl … | bash` one-liner is itself pipe-to-shell; the inspect-first and `git clone` paths above avoid that. Full details: [`docs/security.md`](docs/security.md).

## Status

- ✅ **Unix driver** (`install.sh` + `lib/*.sh`) — macOS / Linux / WSL / Git-Bash.
- ✅ **Bootstrap** (`bootstrap.sh`) — the one-line installer.
- 🧪 **Native Windows** (`install.ps1` + `bootstrap.ps1`) — experimental, mirrors the unix driver (reads the same `manifest.json` via `ConvertFrom-Json`, no jq needed). Pure-function unit tests in `tests/windows-test.ps1`.

**Windows notes:** `git-symlink` (prompt-polish/cursor) needs Developer Mode or admin for real symlinks — otherwise it falls back to a copy. `gstack` runs its bash `setup`, so it needs **Git for Windows** (bash on PATH); without it that step skips with a note. `bun`/agent installers use their PowerShell installers.

## Repo layout

```
install.sh              # unix driver
bootstrap.sh            # unix one-line installer
install.ps1             # native-Windows driver (experimental)
bootstrap.ps1           # Windows one-line installer
manifest.json           # source of truth (agents + plugins) — shared by both drivers
manifest.schema.json    # validated before any execution
lib/                    # detect, paths, prereqs, privilege, manifest, checks, methods, report
tests/                  # plain-bash test harness + suites
docs/                   # security.md, cursor.md, specs/, plans/
```

## Development

```bash
bash tests/run.sh                       # unix suites (no external test deps beyond jq)
pwsh -NoProfile -File tests/windows-test.ps1   # Windows driver pure-function tests
```

Design and implementation notes live under [`docs/superpowers/`](docs/superpowers/).
