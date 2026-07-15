# packages

This folder holds the package list for the WSL/Debian/Ubuntu bootstrap.

## Files

- `packages.txt`  
  The authoritative list of packages to install via `apt-get`.

## Installer behavior

`packages.txt` uses `# @tag` section headers (e.g. `@core`, `@cli`, `@python`, `@system`).
Each package entry uses `package-name  # concise description`. The installer
strips the inline comment before invoking apt, while the read-only Package Lib
uses it as display metadata. Package names remain the authoritative install set.

When you run `./install.sh` (root shim to `scripts/install.sh`), the interactive installer lets you toggle which tag groups to install. Only selected groups are passed to `apt-get install`. The installer also:

- Adds small compatibility fixes for Debian/Ubuntu quirks:
  - `fd-find` installs the `fdfind` binary (because `fd` is already taken)
  - The installer creates: `~/bin/fd -> /usr/bin/fdfind` if missing

Upstream note on `fd` naming: the `fd` project recommends adding a link to `fd` after installing `fd-find` on Debian-based systems.

## Notes on a few tools

- `duf`: friendly disk-usage viewer (like `df`, but nicer)
- `ripgrep` (`rg`): fast recursive search
- `mtr-tiny`: terminal MTR (ping + traceroute)
- `fd-find`: fast `find` alternative (binary is `fdfind`, linked to `fd` by installer)
- `fzf`: fuzzy finder (best used inside pipelines)
- `zoxide`: smarter directory jumping tool (needs shell init to enable `z`)
- `eza`: modern replacement for `ls` (icons require Nerd Font on your terminal)
- `glances`: interactive system monitor
- `magic-wormhole`: secure file transfer CLI (`wormhole send ...`)

## Optional tools that may not be available via default apt repos

`lazygit` and `lazydocker` are **not** included in `packages.txt` because they're not available in Ubuntu's default repositories.

The installer automatically downloads and installs them from official GitHub releases:
- **lazygit**: TUI for git operations
- **lazydocker**: TUI for Docker management

If you prefer not to install them, deselect lazygit/lazydocker from the interactive toggle menu when running `./install.sh`.

## Enabling zoxide

The stowed `.bashrc` already initializes zoxide automatically. After running the installer with both "System packages" and "Apply dotfiles" enabled, the `z` command is available in new shells.
