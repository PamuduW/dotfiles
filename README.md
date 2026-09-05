# WSL Bash dotfiles

An interactive Debian/Ubuntu WSL setup and maintenance environment built with
Bash and GNU Stow.

## What you get

- A component-based installer with an execution plan and local health probes.
- Bash prompt, shared history, modern CLI defaults, and improved Readline.
- Stow-managed helper commands for Dotfiles, Git, WSL, and Codex Remote Control.
- Optional language runtimes, Docker and Portainer, developer tools, fonts, and
  coding-agent CLIs.
- Safe repository-first updates and one-command Dotfiles plus Agentbot
  maintenance.

## Requirements

- Debian or Ubuntu under WSL2.
- Bash, Git, and network access for initial installation.
- `sudo` access for selected system components.
- A normal user-owned clone, conventionally at `$HOME/dotfiles`.

Windows Terminal configuration is provided under `windows/` for manual import.
It is not installed by Stow.

## Quick start

On a clean machine, one command does everything — it asks what to install,
obtains the repositories, opens the component selector, then installs and
updates:

```bash
curl -fsSL https://raw.githubusercontent.com/PamuduW/dotfiles/main/bootstrap.sh | bash
```

It asks first:

```text
What should this machine get?

  1) Dotfiles and Agentbot   (recommended)
  2) Dotfiles only
  3) Agentbot only
```

Dotfiles is cloned to `$HOME/dotfiles` and Agentbot to `$HOME/agentbot`; they
must stay siblings because `dotfiles full-update` resolves Agentbot that way.
An existing destination is reused when it is a clean checkout of the same
repository, and anything else stops the run with a report — nothing is ever
deleted or moved. After the Dotfiles phases finish, bootstrap asks before
installing Agentbot.

To read the script before running it, or on a machine that already has Git:

```bash
sudo apt-get install -y git
git clone https://github.com/PamuduW/dotfiles "$HOME/dotfiles"
"$HOME/dotfiles"/bootstrap.sh
```

To work with an existing checkout directly:

```bash
cd "$HOME/dotfiles"
./install.sh
```

The interactive menu offers:

```text
Check Status
Install Dotfiles
Update
Full Update (Dotfiles + Agentbot)
GitHub Token Config
Libraries
Quit
```

Install Dotfiles checks the repository, opens the component selector, shows an
execution plan, and asks for confirmation. Git identity and SSH-key generation
are off by default; other registered components start selected. Dependencies
such as Portainer requiring Docker are enforced automatically.

After installation, open a new terminal or run:

```bash
source ~/.bashrc
```

Changes to `/etc/wsl.conf` require `wsl --shutdown` from Windows.

## Main commands

| Command | Behavior |
|---|---|
| `dotfiles` or `dotfiles menu` | Open the interactive boot menu on a TTY |
| `dotfiles status` | Show local component and repository state without fetching |
| `dotfiles doctor` | Show only components needing attention; exit nonzero when any do |
| `dotfiles update --dry-run` | Print the captured update report without applying updates |
| `dotfiles update` | Run the repository gate, then update every managed component after confirmation |
| `dotfiles full-update` | Update Dotfiles, run `agentbot full`, and perform postflight health checks |
| `dotfiles restow` | Reapply the `bash`, `bin`, and `readline` Stow packages |
| `dotfiles logs [--list\|--last]` | List retained action logs or print the newest |
| `dotfiles commands` | Print authoritative command and configuration metadata |
| `dotfiles packages` | Print component and apt-package metadata without probing |

`dotfiles update --all` remains a compatibility no-op because one confirmed
update already selects every managed update.

For non-interactive installation, select stable component keys explicitly:

```bash
DOTFILES_COMPONENTS=system_packages,docker,portainer,dotfiles \
  ./install.sh --initial
```

## Component summary

The registry contains 21 components:

| Area | Components |
|---|---|
| Base system | system packages, Python packages, PowerShell, WSL configuration |
| Languages | Go through asdf, Node.js and npm through nvm, direnv |
| Containers | Docker Engine, Portainer CE LTS, lazydocker |
| Developer tools | Graphify CLI, Boost CLI, lazygit, Monaspace fonts |
| Agent CLIs | Cursor, standalone Codex, Claude |
| Shell and Git | Stow packages, Git identity, Git credentials/submodule defaults, SSH key |

The exact keys, dependencies, defaults, and descriptions are available through
`dotfiles packages` and documented in [Component lifecycle](docs/components.md).

## Codex CLI migration

Dotfiles installs the standalone Codex CLI and preserves external or shadowed
commands until an explicit verified migration is authorized. See [Codex and
Remote Control](docs/codex-and-remote-control.md) for ownership states,
non-interactive authorization, and safety boundaries.

## Common workflows

### Inspect before changing anything

```bash
dotfiles status
dotfiles doctor
dotfiles update --dry-run
```

### Repair only Stow links

```bash
dotfiles restow
```

### Maintain Dotfiles and Agentbot

```bash
dotfiles full-update
```

The command verifies the resolved installed checkouts, delegates Agentbot's
internal lifecycle to `agentbot full`, and finishes with both Doctors. Current
full update updates managed components but does not yet rerun all previously
selected installers; that expansion remains on the workspace roadmap.

### Start optional services

Fresh or migrated Portainer containers are left stopped:

```bash
dpot
dpotstop
```

Codex Remote Control accepts explicit start/stop actions:

```bash
codex-rc start
codex-rc stop
```

Claude Remote Control starts automatically after Claude CLI setup. Dotfiles
does not ship a separate lifecycle helper for it.

Treat Codex pairing values as terminal-only secrets. Do not redirect, log,
save, commit, screenshot, or paste them into chat.

### Add an existing nested repository as a submodule

```bash
git sub add path/to/repository
```

The Stow-managed Git wrapper prevents `git add --all` and editor Commit All
from silently staging undeclared nested repositories as gitlinks. Git aliases
that expand to `commit`, `add`, `clone`, or `sub add` use the same guards.
See the [Git wrapper contract](docs/git-wrapper.md).

## Documentation

- [Technical documentation index](docs/README.md)
- [Architecture](docs/architecture.md)
- [Installation](docs/installation.md)
- [Updates](docs/updates.md)
- [Codex and Remote Control](docs/codex-and-remote-control.md)
- [Security](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Package policy](packages/README.md)
- [WSL command reference](WSL_COMMANDS.md)

## Development

Work in the development checkout rather than the installed operational clone.
Run the complete gate before handoff:

```bash
./scripts/validate.sh
```

The gate covers syntax, ShellCheck, formatting, JSON, shared-library drift,
whitespace, and every shell test. See [Development and
validation](docs/development.md) for focused commands and ownership rules.
