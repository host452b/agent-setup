# Cursor: a best-effort integration target

"Cursor" here means the **Cursor CLI** — the `cursor-agent` binary (also invoked
as `agent`), installed from `cursor.com/install`. It is **not** the Cursor IDE.
Its config lives under `~/.cursor/`.

`cursor-agent` exposes `mcp` and `generate-rule` but **no plugin-install
command**. So Cursor coverage comes from each tool's own cross-agent path,
not a marketplace install:

- **gstack** — not supported on Cursor (gstack's setup has no Cursor host)
- **caveman** — its installer auto-detects Cursor
- **taste-skill** — `npx skills add` targets Cursor's skills dir
- **ui-ux-pro-max** — `npx uipro init --ai cursor` (lands in `~/.cursor/skills`)
- **open-design** — manual: install open-design first, then `od mcp install cursor` (its `od` CLI isn't auto-installable and collides with the system `od`)
- **prompt-polish** — clone + symlink the repo into `~/.cursor/skills/prompt-polish` (the installer does this automatically)
- **superpowers / ponytail** — manual: copy the rules file into the Cursor
  rules dir, or use the in-chat `/add-plugin` flow. The installer prints these
  steps; it cannot perform them.

Cursor-CLI config paths (resolved by `lib/paths.sh`) — `~/.cursor/` on every OS:

| Path | Location |
|---|---|
| user dir | `~/.cursor/` |
| skills | `~/.cursor/skills/` |
| rules | `~/.cursor/rules/` |
| mcp config | `~/.cursor/mcp.json` |
