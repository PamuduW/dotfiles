# Installation

## Interactive setup

Clone the repository into the operational location and run its supported entry
point:

```bash
git clone <repo-url> "$HOME/dotfiles"
cd "$HOME/dotfiles"
./install.sh
```

The boot menu offers status, installation, update, full update, token
configuration, reference libraries, and quit. Install Dotfiles runs the
repository gate before opening the component menu. Use arrows to navigate,
Space to toggle, and Enter to continue. The installer displays an execution
plan before applying the selection.

Git identity is prompted only when selected. SSH-key generation is also an
explicit opt-in. Component dependencies remain enforced while toggling.

## Non-interactive setup

Without a TTY on standard input, `./install.sh` defaults to initial setup and
does not open the menu. Limit the selection with stable component keys:

```bash
DOTFILES_COMPONENTS=system_packages,dotfiles ./install.sh --initial
```

Existing global Git identity values are used when identity is enabled without
an interactive prompt. Verified npm-to-standalone Codex migration requires the
separate `DOTFILES_MIGRATE_NPM_CODEX=1` authorization; component selection alone
does not authorize package removal.

## Installation order

The installer refreshes apt indexes once when selected components require apt.
It then follows the registry's deterministic order. Each component is attempted
and recorded independently, and the final summary distinguishes completed,
skipped, and failed work.

Important boundaries:

- Docker daemon configuration is merged and conflicts fail closed.
- Portainer preserves custom layouts and the named data volume.
- Stow backs up conflicting managed home files before linking.
- Vendor scripts are downloaded and checked before execution.
- GitHub-release installers verify the selected archive checksum.
- Dotfiles installs Graphify and Boost binaries only; Agentbot owns their agent
  integration.

## Files changed outside the repository

Depending on selection, setup may modify apt state, Docker configuration,
`/etc/wsl.conf`, global Git configuration, user runtime managers, `$HOME` Stow
links, local fonts, and private token state. Review the execution plan before
confirmation. System changes invoke `sudo` only where required.

Stow manages these targets:

```text
~/.bashrc
~/.bash_aliases
~/.inputrc
~/bin/{dotfiles,git,ex,clip,codex-rc,claude-rc}
```

## After installation

Open a new terminal or source `~/.bashrc`. Changes to `/etc/wsl.conf` require
`wsl --shutdown` from Windows before a new WSL session. Reload VS Code after
Stow so its Git extension can resolve the guarded `~/bin/git` executable.

