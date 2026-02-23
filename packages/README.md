# packages

This folder holds the package list for the WSL/Debian/Ubuntu bootstrap.

## Files

- `packages.txt`  
  The authoritative list of packages to install via `apt-get`.

## Installer behavior

When you run `dotfiles/install.sh`, it:

1. Runs `sudo apt-get update`
2. Installs everything listed in `packages.txt` using `sudo apt-get install -y ...`
3. Applies your dotfiles using GNU Stow
4. Adds small compatibility fixes for Debian/Ubuntu quirks:
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

If you prefer not to install from GitHub releases automatically, comment out the fallback installer functions in `install.sh`.

## Enabling zoxide

Installing `zoxide` is not enough. You must also initialize it in your shell.

Add this to your `.bashrc` (once):

```bash
eval "$(zoxide init bash)"
```

Then restart your shell. The `z` command will be available.
