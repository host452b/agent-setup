# Cursor: a best-effort integration target

`cursor-agent` exposes `mcp` and `generate-rule` but **no plugin-install
command**. So Cursor coverage comes from each tool's own cross-agent path,
not a marketplace install:

- **gstack** — not supported on Cursor (gstack's setup has no Cursor host)
- **caveman** — its installer auto-detects Cursor
- **taste-skill** — `npx skills add` targets Cursor's skills dir
- **ui-ux-pro-max** — `npx uipro init --ai cursor` (lands in `~/.cursor/skills`)
- **open-design** — manual: install open-design first, then `od mcp install cursor` (its `od` CLI isn't auto-installable and collides with the system `od`)
- **superpowers / ponytail** — manual: copy the rules file into the Cursor
  rules dir, or use the in-chat `/add-plugin` flow. The installer prints these
  steps; it cannot perform them.

Cursor config paths (resolved by `lib/paths.sh`):

| OS | Cursor user dir |
|---|---|
| macOS | `~/Library/Application Support/Cursor/User/` |
| Linux | `~/.config/Cursor/User/` |
| WSL | Linux path (or `/mnt/c/Users/.../AppData/Roaming/Cursor/User/` if Cursor is on the Windows side) |
| Windows | `%APPDATA%\Cursor\User\` |
