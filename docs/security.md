# Security model

- **Dry-run first.** `--dry-run` prints every command and changes nothing.
- **Confirmation.** Steps marked `executes_remote_code` or `requires_admin`
  prompt before running unless `--yes` is passed. `--non-interactive` refuses
  privileged steps outright.
- **download-then-run.** Remote installers are downloaded to a temp file and
  executed from disk, never piped straight into a shell. Where the manifest
  pins `version`/`ref`/`sha256`, the download is verified first.
- **PATH-shadow guard.** Before invoking an external tool the installer
  resolves its real path and verifies the expected source. This is mandatory
  for `od` (open-design), which collides with the unix `od` octal-dump binary.
- **Least privilege.** The whole script is never run under sudo; only the
  specific subcommands that need elevation request it, and they are surfaced
  in the plan up front.
- **Global installs** (e.g. `uipro --global`) are flagged with
  `install_scope: global` and may mutate PATH depending on your npm prefix.

## Bootstrap one-liner tradeoff

`curl … | bash` is pipe-to-shell — the very pattern this project avoids for the
installers it runs. We offer it for convenience but recommend the inspect-first
variant (download `bootstrap.sh`, read it, then run it), or a plain
`git clone` + `bash install.sh`. The bootstrap itself only fetches the repo
(git clone, or a tarball downloaded to a temp file then extracted — never piped
to a shell) and then runs the local `install.sh`.
