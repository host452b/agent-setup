# agent-setup — Design

Date: 2026-06-24
Status: Approved-direction, pending spec review
Repo: github.com/host452b/agent-setup

## 1. Purpose

One repo, one command per OS, that:

1. **Installs coding agents** — Claude Code, Codex CLI, Cursor CLI.
2. **Installs a curated plugin/skill set** into all three agents at the **user level**, as far as each agent's install surface allows.

Target OSes: **macOS, Linux, WSL, Windows (10 & 11)**. WSL is modeled separately from Linux.

Core principle:

> Describe install **intent** in a manifest. Resolve the **environment** with detect/paths/privilege. Execute **controlled actions** via methods. **Prove** results with checks/report.

## 2. Scope

### Agents (step 1)

| Agent | Install (unix) | Install (windows) |
|---|---|---|
| Claude Code | `curl -fsSL https://claude.ai/install.sh \| bash` | `irm https://claude.ai/install.ps1 \| iex` (or `winget install Anthropic.ClaudeCode`) |
| Codex CLI | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` (`CODEX_NON_INTERACTIVE=1`) | `irm https://chatgpt.com/codex/install.ps1 \| iex` |
| Cursor CLI | `curl https://cursor.com/install -fsS \| bash` | `irm 'https://cursor.com/install?win32=true' \| iex` |

### Plugins / skills (step 2)

superpowers, ponytail, gstack, caveman, taste-skill, ui-ux-pro-max, open-design, prompt-polish.

### Coverage matrix (plugin × agent × method × coverage)

`coverage` ∈ `native | partial | manual | unsupported`.

| Plugin | Claude Code | Codex CLI | Cursor |
|---|---|---|---|
| superpowers | `claude-plugin` (obra/superpowers-marketplace) — native | `codex-plugin` — partial (trust-gated) | `manual` (`/add-plugin`, no CLI) |
| ponytail | `claude-plugin` (DietrichGebert/ponytail) — native | `codex-plugin` + trust hooks — partial | `file-copy` rules → `CURSOR_RULES_DIR` — native |
| gstack | `git-setup` (clone + `./setup`) — native | `git-setup --host codex` — native | `git-setup --host cursor` — native |
| caveman | `shell-installer` (auto-detect) — native | same installer — native | same installer — native |
| taste-skill | `npx-skills` — native | `npx-skills` — partial | `npx-skills` — native |
| ui-ux-pro-max | `npm-cli` (`uipro init --ai claude --global`) — native | `--ai codex` — native | `--ai cursor` — native |
| open-design | `od-mcp` (`od mcp install claude`) — partial¹ | `od mcp install codex` — partial¹ | `od mcp install cursor` — partial¹ |
| prompt-polish | `claude-plugin` (host452b/polish, installs `polish@polish`) — native | `codex-plugin` (host452b/polish, installs `polish@polish`) — partial | `git-symlink` (`skills/prompt-polish`) — native |

¹ open-design requires the `od` binary present **and** PATH-shadow resolved (`/usr/bin/od` is the unix octal-dump tool). If `od` is absent or shadowed → degrade to `manual`.

Cursor is a **best-effort integration target**, never a marketplace install. This fact is reflected in schema, dry-run, report, and README.

## 3. Verified install surfaces

- **Claude Code**: `claude plugin marketplace add <src>` + `claude plugin install <plugin>@<mkt>` — fully non-interactive. ✓
- **Codex CLI**: `codex plugin marketplace add <src>` + `codex plugin add <plugin>` — scriptable; hook-trust steps may stay interactive. Partial.
- **Cursor**: `cursor-agent` exposes `mcp`, `generate-rule` — **no** plugin-install command. File-level integration only.

## 4. Repo layout

```
agent-setup/
├── install.sh                 # bootstrap: macOS / Linux / WSL / Git-Bash
├── install.ps1                # bootstrap: native Windows
├── manifest.json              # SINGLE SOURCE OF TRUTH
├── manifest.schema.json       # validated before any execution
├── lib/
│   ├── detect.{sh,ps1}        # OS taxonomy + which agents present + structured paths
│   ├── paths.{sh,ps1}         # per-OS agent config/rules/skills/mcp path resolution
│   ├── prereqs.{sh,ps1}       # jq (mandatory) + node/git/bun (check by default)
│   ├── privilege.{sh,ps1}     # sudo/admin planning + preflight
│   ├── manifest.{sh,ps1}      # load + schema-validate + resolve plan
│   ├── methods.{sh,ps1}       # one executor per method type
│   ├── checks.{sh,ps1}        # before/after predicates (idempotency + verification)
│   └── report.{sh,ps1}        # plan/status/report emission
├── docs/
│   ├── security.md            # remote-exec policy, pinning, PATH-shadow
│   ├── cursor.md              # cursor as best-effort integration target
│   └── superpowers/specs/     # this design doc
├── tests/
│   ├── fixtures/
│   ├── test_manifest_schema.sh
│   ├── test_detect.sh
│   ├── test_dry_run.sh
│   ├── test_paths.sh
│   └── test_privilege.sh
└── README.md
```

## 5. Startup order (both drivers)

```
1. detect OS (darwin | linux | windows | wsl)
2. load prereq helpers
3. verify jq (unix) — hard-fail with install hint if missing
4. load + schema-validate manifest.json
5. resolve agents present + structured paths (detect/paths)
6. build execution plan (plugin × agent × method × platform × coverage × safety)
7. privilege preflight — surface every sudo/admin step up front
8. execute plan (or print, in dry-run)
9. run after-checks, write report + log
```

JSON parsing: **`jq` mandatory** on unix — no raw `awk`/`sed`/`grep` fallback (silent-bug risk). PowerShell uses native `ConvertFrom-Json`.

## 6. Method types

Each `method` is a controlled executor. Manifest tags every (plugin, agent) target with one.

`claude-plugin`, `codex-plugin`, `shell-installer`, `npx-skills`, `git-setup`, `npm-cli`, `od-mcp`, `file-copy`, `dir-copy`, `symlink-file`, `symlink-dir`, `template-render`, `json-merge`, `manual`.

(The original coarse `file-copy`/`symlink` is split — distinct failure modes: overwrite, dir-merge, Windows symlink perms, var-substitution, JSON corruption.)

## 7. Manifest schema (per target)

```json
{
  "method": "git-setup",
  "coverage": "native | partial | manual | unsupported",
  "platforms": ["darwin", "linux", "windows", "wsl"],
  "requires": ["git", "node", "jq"],
  "install_scope": "user | global",
  "requires_path_mutation": false,
  "args": {},
  "safety": {
    "risk": "low | medium | high",
    "network": true,
    "executes_remote_code": true,
    "writes_global_config": false,
    "requires_admin": false,
    "may_prompt_for_sudo": false,
    "requires_confirmation": true
  },
  "checks": {
    "before": [{ "type": "file_exists", "path": "${CURSOR_RULES_DIR}/gstack.md" }],
    "after":  [{ "type": "file_exists", "path": "${CURSOR_RULES_DIR}/gstack.md" }]
  },
  "conflict_policy": "skip | backup | overwrite | merge | prompt",
  "manual": {
    "reason": "Cursor has no marketplace plugin CLI.",
    "steps": ["Open Cursor Settings", "Go to MCP", "Add the server config below"],
    "verification": ["Restart Cursor", "Confirm MCP server enabled"]
  }
}
```

`manifest.schema.json` validates this before execution; unknown method / missing required field → fail closed.

## 8. Environment resolution (detect / paths)

Cursor config paths are resolved centrally (never hardcoded in methods), exported as variables:
`CURSOR_USER_DIR`, `CURSOR_RULES_DIR`, `CURSOR_MCP_CONFIG`, `CURSOR_SKILLS_DIR`.

| OS | Cursor user config |
|---|---|
| macOS | `~/Library/Application Support/Cursor/User/` |
| Linux | `~/.config/Cursor/User/` |
| WSL | Linux path, with Windows-interop detection when Cursor lives on the Windows side (`/mnt/c/Users/.../AppData/Roaming/Cursor/User/`) |
| Windows | `%APPDATA%\Cursor\User\` |

`detect` emits a **structured** result (JSON on unix → read with `jq`; native object in PowerShell), e.g. `{ os, agents: { cursor: { present, user_dir, rules_dir, mcp_config, skills_dir } } }`.

### WSL specifics (first-class, not folded into linux)

- Cursor may be installed on Windows while the script runs in WSL.
- Path interop: `/mnt/c/Users/.../AppData/Roaming/...`.
- `cmd.exe` / `powershell.exe` interop availability varies.
- symlink semantics differ; Node/Git may exist in both Windows and WSL.

## 9. Privilege model

Privileges planned **before** execution, never discovered mid-run.

- Unix: never `sudo` the whole script. `sudo` only the specific subcommands that need it; surface them in the plan; dry-run shows sudo requirements; non-interactive/CI hitting a sudo requirement → fail with a clear message.
- Windows: `Test-IsAdmin`; if a step needs admin and the shell isn't elevated, stop that step up front rather than leaving an inconsistent state after a mid-run UAC.

## 10. Prereqs policy

- Default: `--check-prereqs` (detect + advise only). Auto-install is opt-in via `--install-prereqs` (brew/apt/winget).
- **`jq` is the sole exception** on unix — required to parse the manifest. Even so, default behavior prints the install command (`brew install jq` / `sudo apt install jq`) rather than silently installing.
- Node/git/bun: checked, not auto-installed by default. `npx-skills` and `npm-cli` methods declare `requires: ["node"]`.
- Prefer `npx` / `bunx` / `pnpm dlx` over `npm install -g`. Where global is unavoidable (`uipro`), the target sets `install_scope: "global"`, `requires_path_mutation: true`, and dry-run warns it may need elevation depending on the npm prefix.

## 11. Safety / remote-execution model

`docs/security.md` defines defaults:

- High-risk steps (`executes_remote_code` / `requires_admin`) require confirmation unless `--yes`.
- `--dry-run` prints commands, executes nothing.
- Prefer **download-then-run** over pipe-to-shell:
  ```bash
  tmp="$(mktemp)"; curl -fsSL "$url" -o "$tmp"; [ optional sha256 verify ]; bash "$tmp"
  ```
- Network sources pinned where possible — manifest supports `version` / `ref` / `sha256`.
- **PATH-shadow guard** is a general capability (not just `od`): before invoking any external tool (`od`, `node`, `npm`, `npx`, `bun`, `claude`, `codex`, `cursor-agent`, `git`), verify via `command -v` + `realpath` + version, detect duplicate/shadowing binaries, and confirm the expected source.

## 12. Idempotency & verification

Every method answers: already installed? safe to rerun? what proves success? what changed? what next?

Checks use a **fixed predicate vocabulary** (no arbitrary shell):
`command_exists`, `file_exists`, `dir_exists`, `json_contains`, `json_path_exists`, `mcp_server_registered`, `claude_plugin_installed`, `codex_plugin_installed`, `cursor_rule_exists`.

`before` checks short-circuit already-satisfied targets; `after` checks prove success.

## 13. Conflict policy defaults

| Target type | Default |
|---|---|
| Cursor rules markdown | `backup` |
| skills directory | `skip` or `backup` |
| MCP JSON config | `merge` |
| symlink target exists | `prompt` |
| generated templates | `backup` |

## 14. CLI surface

```
./install.sh --check-prereqs        # default-ish: detect + advise
./install.sh --install-prereqs      # opt-in auto-install
./install.sh --dry-run | --plan     # show plan, mutate nothing
./install.sh --status               # what's installed now
./install.sh --agent cursor         # scope to one agent
./install.sh --plugin gstack        # scope to one plugin
./install.sh --only-method git-setup
./install.sh --agents-only
./install.sh --yes                  # auto-confirm high-risk
./install.sh --non-interactive      # CI; fail on sudo/trust gates
```

Plan/dry-run/status/report each surface: agent, plugin, method, coverage, platform, commands, files to write, conflict policy, sudo/admin needs, trust-gated steps, verification checks, manual next-steps.

Artifacts per run:
```
~/.agent-setup/runs/<timestamp>/report.json
~/.agent-setup/logs/<timestamp>.log
```

`install.ps1` mirrors the same flags and behavior on native Windows.

## 15. Structured manual steps

`manual` targets are data, not free text (see schema §7) — reused by dry-run, README generation, and the run report.

## 16. Testing

`tests/` covers: schema validation, detect (per-OS path resolution incl. WSL interop), dry-run plan correctness, paths, privilege preflight. Fixtures simulate each OS's detect output so dry-run is testable without the real agents installed.

## 17. Out of scope (YAGNI)

- Agent **authentication** / login (each agent prompts on first run; documented, not automated).
- Uninstall flows (future; each tool ships its own uninstaller).
- GUI / TUI.
- Non-listed agents (Gemini, Copilot, etc.) — manifest is extensible if added later.
```
