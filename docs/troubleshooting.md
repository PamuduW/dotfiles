# Troubleshooting

## Start with local inspection

```bash
dotfiles status
dotfiles doctor
dotfiles logs --last
```

Status shows all local component states without fetching. Doctor shows only
items needing attention and exits nonzero when remediation is required.

## Stow conflicts

Installation backs up existing managed shell and helper files before applying
Stow. For link-only repair, use:

```bash
dotfiles restow
```

If Stow still fails, inspect the conflicting destination and the newest action
log. Do not delete unrelated home files merely to make Stow pass.

## Docker permission denied

Docker installation adds the user to the `docker` group. Start a new login
session or run `newgrp docker`, then verify `docker version`. Dotfiles can fall
back to `sudo docker`, but persistent user access requires refreshed group
membership.

## Portainer

Portainer is deliberately stopped after fresh installation or managed-image
replacement. Start and stop it with:

```bash
dpot
dpotstop
```

Automatic replacement is refused when storage, socket, port, or restart-policy
layout is custom. Review that container manually; Dotfiles will not discard its
configuration.

## Codex ownership conflicts

Run:

```bash
which -a codex
command -v codex
readlink -f "$(command -v codex)" 2>/dev/null
dotfiles doctor
```

An external or shadowed result must be resolved by the owning installer or the
explicit verified npm migration. Do not overwrite it with a standalone binary.

## Repository update stops

Read the repository table and full dirty-path command printed by the updater.
Dirty, ahead, diverged, untrusted-origin, or fetch-failed states intentionally
stop downstream work. Preserve the recovery branch and stash if replacement
was approved; do not bypass the gate with a forced reset.

## Missing helper commands

Confirm `~/bin` precedes conflicting paths, then run `dotfiles restow` and open
a new terminal. Reload VS Code after changing the Git wrapper link. An explicit
VS Code `git.path=/usr/bin/git` bypasses the wrapper.

## WSL configuration

After changing `/etc/wsl.conf`, run `wsl --shutdown` from Windows and open a new
WSL session. See [`WSL_COMMANDS.md`](../WSL_COMMANDS.md) for instance-management
commands.

