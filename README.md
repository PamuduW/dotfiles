# WSL Bash dotfiles (GNU Stow)

Bootstraps a consistent Bash environment on Debian/Ubuntu WSL with an **interactive installer** and **GNU Stow** symlinks.

## What you get

- **Interactive boot menu** — `dotfiles` / `dotfiles menu` or `./install.sh`; loops through status, install, update, token, library, and Agentbot actions
- Custom Bash prompt: time, user@host, path, git branch + status markers, exit code
- Cross-terminal history syncing (`history -a; history -n`) with 10k line history
- Modern CLI tools: `eza`, `fzf` (Ctrl+R/Ctrl+T/Alt+C), `zoxide`, `ripgrep`, `fd`
- Better readline: case-insensitive completion, arrow-key history search
- Docker Engine + Portainer CE (with `dpot`/`dpotstop` shortcuts)
- Node.js via nvm, Python 3, Go (asdf), PowerShell, direnv
- AI CLI tools: Cursor, Codex, Claude, Copilot (updated through the explicit `dotfiles update` workflow)
- SSH key generation with GitHub setup notes
- WSL-specific config: systemd, Windows PATH interop (`appendWindowsPath=true`), Git credential helper, clipboard helper

**Bonus:** See [WSL_COMMANDS.md](WSL_COMMANDS.md) for a guide to managing WSL instances.

---

## Repo layout

```
.
├── bash/
│   ├── .bashrc
│   └── .bash_aliases
├── bin/
│   └── bin/
│       ├── ex          # open Windows Explorer from WSL
│       ├── clip        # copy to Windows clipboard from WSL
│       └── dotfiles    # status, update, command/package libraries
├── readline/
│   └── .inputrc        # better tab completion + history search
├── packages/
│   └── packages.txt    # apt packages with @tag sections
├── windows/
│   └── terminal-settings.json  # Windows Terminal profile export (manual import)
├── log/                # install logs (gitignored)
├── scripts/
│   ├── install.sh      # real installer
│   ├── lib/            # TUI, bootstrap helpers
│   └── menus/          # main + submenus (plan8)
├── install.sh          # shim → scripts/install.sh
└── README.md
```

Stow packages: `bash`, `bin`, `readline`

---

## Install

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
chmod +x install.sh bin/bin/ex bin/bin/clip bin/bin/dotfiles
./install.sh
```

### agent_bootstrap sibling path

The **Agentbot** action expects `agent_bootstrap` as a **sibling** of this repo (not a fixed `~/Dev` path):

```text
parent/
├── dotfiles/           # this repo
└── agent_bootstrap/    # sibling target for Agentbot
```

Clone manually or use **Agentbot**. The bridge validates `install.sh` and the Git origin before launching. A standalone `agent_bootstrap` clone still works when launched directly.

Entry points (interactive TTY):

- `dotfiles` or `dotfiles menu` — boot menu (after stow)
- `./install.sh` — same menu via root shim

The main menu **loops** until you choose Quit:

```
=== Dotfiles ===
  Check Status
  Install Dotfiles
  Update
  GitHub Token Config
  Command Lib
  Package Lib
  Agentbot
  Quit
```

Use arrow keys to navigate and Enter to select.

### Boot menu

| Option | Submenu / action |
| ------ | ---------------- |
| Check Status | Read-only local component and repository report; remote and apt freshness are labelled unchecked. |
| Install Dotfiles | Select components, review the execution plan, and apply setup. |
| Update | Repo-first fetch/classify/pull gate, then confirmed downstream updates. |
| GitHub Token Config | Configure the optional shared API token without blocking anonymous use. |
| Command Lib | Read-only command and mutation matrix. |
| Package Lib | Read-only component and system-package catalog. |
| Agentbot | Validate/clone the sibling `agent_bootstrap` repository, then launch it as a child. |
| Quit | Exit |

### CLI flags

Skip the boot menu with explicit flags:

```bash
./install.sh --status       # Read-only status
./install.sh --update       # Update submenu
./install.sh --agents       # Agentbot sibling bridge
./install.sh --help         # Usage
```

**Non-interactive** runs (no TTY on stdin — CI, piped, or redirected input) skip the boot menu and component toggle/confirm prompts. Behavior depends on the flag:

| Invocation | Behavior |
| ---------- | -------- |
| `./install.sh` (no flag, no TTY) | Runs the explicit non-interactive install path |
| `./install.sh --status` (no TTY) | Prints local status without fetch, apt refresh, or writes |
| `./install.sh --update` | Runs update flow (non-interactive where applicable) |
| `./install.sh --agents` | Launches Agentbot as a sibling child after validation |

Set `DOTFILES_COMPONENTS` to a comma-separated list of component keys to install only those (e.g. `DOTFILES_COMPONENTS=docker,portainer,lazygit`). When git identity is enabled but not prompted, existing `git config --global` values are used.

When you choose **Run setup** interactively (TTY), the installer will:

1. Show an **interactive menu** — arrow keys to navigate, space to toggle
2. Display the **execution plan** for review
3. Ask to **confirm, edit, or quit**
4. Prompt for **git identity** only if that component is enabled
5. Run only the selected components

### Component menu

| Component       | What it does                                                                  |
| --------------- | ----------------------------------------------------------------------------- |
| Git identity    | Set global `user.name` / `user.email` (auto-disabled if `includeIf` detected) |
| System packages | Core CLI tools from apt (@core, @cli, @system)                                |
| Python          | python3, pip, venv                                                            |
| PowerShell      | Microsoft PowerShell from official Microsoft apt repository                   |
| Go              | Latest Go via asdf                                                            |
| Node.js         | v24 LTS via nvm                                                               |
| direnv          | Directory-based env loader + bash hook                                        |
| Docker Engine   | Docker CE from official repo + docker group                                   |
| Portainer CE    | Docker management UI (requires Docker)                                        |
| lazygit         | Git TUI from GitHub releases                                                  |
| lazydocker      | Docker TUI from GitHub releases (requires Docker)                             |
| Cursor CLI      | Cursor editor CLI from cursor.com                                             |
| Codex CLI       | OpenAI Codex CLI via npm (requires Node.js)                                   |
| Claude CLI      | Anthropic Claude CLI from claude.ai                                           |
| Copilot CLI     | GitHub Copilot CLI via gh.io/copilot-install                                  |
| Monaspace fonts | GitHub Monaspace Nerd Fonts to `~/.local/share/fonts/`                        |
| SSH key         | ed25519 key + GitHub setup notes in `~/.ssh/github-setup.txt`                 |
| Dotfiles        | Stow bash, bin, readline into `$HOME`                                         |
| WSL config      | `systemd=true`, `appendWindowsPath=true` in `/etc/wsl.conf`                   |
| Git credential  | Windows Credential Manager for HTTPS auth                                     |

Dependencies are enforced automatically (e.g., disabling Docker also disables Portainer).

**Multi-identity git setups**: If your `~/.gitconfig` uses `includeIf` for per-directory identities, the installer detects this and defaults "Git identity" to OFF so it won't overwrite your configuration.

## Security notes

- Some tools are installed via `curl … | bash` from their official vendor channels (Cursor, Claude, Copilot, nvm, direnv). These are not checksum-verified; review the upstream scripts if you need stronger supply-chain guarantees.
- GitHub-release binaries (lazygit, lazydocker) are checksum-verified during install.
- The generated SSH key prompts for a passphrase (press Enter to skip).

---

## What changes in `$HOME`

After stowing:

- `~/.bashrc` → `dotfiles/bash/.bashrc`
- `~/.bash_aliases` → `dotfiles/bash/.bash_aliases`
- `~/.inputrc` → `dotfiles/readline/.inputrc`
- `~/bin/ex` → `dotfiles/bin/bin/ex`
- `~/bin/clip` → `dotfiles/bin/bin/clip`
- `~/bin/dotfiles` → `dotfiles/bin/bin/dotfiles`

---

## `dotfiles` command

Global command (stowed to `~/bin/dotfiles`, on PATH like `ex` and `clip`):

| Subcommand | Action |
| ---------- | ------ |
| `dotfiles` | On a TTY, opens the boot menu; otherwise prints help |
| `dotfiles menu` | Boot menu (same as `./install.sh`) |
| `dotfiles update` | **Apply after confirmation** — repo-first gate, then apt/CLI/tool changes |
| `dotfiles update --all` | Same as `update`, plus opt-in **Node.js**, **Go**, and **Monaspace** fonts |
| `dotfiles status` | Local installed versions + repo state; no fetch or apt refresh |
| `dotfiles commands` | Read-only command behavior matrix |
| `dotfiles packages` | Read-only component/package catalog |
| `dotfiles token` | Optional shared GitHub token configuration |
| `dotfiles agentbot` | Validated sibling Agentbot launch |
| `dotfiles restow` | `stow --restow bash bin readline` |

Runs **unprivileged**; only the apt portion invokes `sudo` internally (single prompt). Agent CLI and npm updates stay under your user.

The interactive Update action clears the menu before starting. It checks the
repository first; an available pull is shown in a colored repository table and
requires confirmation. After a pull, press Enter to restart `install.sh` from
the updated checkout. When the repository is current, Update shows the full
colored installed/available/action report, asks whether to upgrade, then asks
whether to include the Node.js, Go, and Monaspace opt-ins. It finishes with a
colored result table and returns to the menu after Enter.

### Agentbot — `agent_bootstrap`

The **Agentbot** action validates or clones [`agent_bootstrap`](https://github.com/PamuduW/agent_bootstrap) as a sibling of this dotfiles repo, then launches it as a child process.

| Action | What it does |
| ------ | ------------ |
| Existing sibling | Requires executable `install.sh` and an allowlisted origin |
| Missing sibling | Shows exact URL/destination and asks before cloning |
| Child launch | Runs `SETUP_CALLER=dotfiles ../agent_bootstrap/install.sh` and returns on exit |

**Environment overrides (advanced):**

| Variable | Default | Notes |
| -------- | ------- | ----- |
| `DOTFILES_AGENTBOT_URL` | `git@github.com:PamuduW/agent_bootstrap.git` | Clone URL; must match the allowlist |
| `AGENTBOT_HOME` | sibling `agent_bootstrap` | Explicit validated sibling override |

Clone URLs never contain credentials. `SETUP_CALLER=agentbot` makes the child hide its Dotfiles route.

## Bash prompt

Shows on every command:

- Blank line separator
- Time (24h), `user@host`, working directory
- Git branch + status: `✚` staged, `✱` modified, `?` untracked
- Exit code on failure: `✗1`

Examples: `(main)` clean, `(main ✚✱?)` everything dirty.

---

## Key features

### fzf keybindings

- **Ctrl+R** — fuzzy search command history
- **Ctrl+T** — fuzzy find files
- **Alt+C** — fuzzy cd into directories

### readline improvements (`.inputrc`)

- Case-insensitive tab completion
- Up/Down arrow searches history based on what you've typed
- Colored completions with file type indicators
- No bell

### WSL helpers

- `ex .` — open Windows Explorer here
- `echo "text" | clip` — copy to Windows clipboard

Both use full Windows paths, so they work even with `appendWindowsPath=true`.

---

## Aliases highlights

| Alias            | Command                                            |
| ---------------- | -------------------------------------------------- |
| `ll`             | `eza -alF --git` (detailed list with git status)   |
| `gitlog`         | `git log --oneline --graph --decorate --all`       |
| `dpot`           | Start Portainer at `https://localhost:9443`        |
| `dpotstop`       | Stop Portainer                                     |
| `reload`         | `source ~/.bashrc`                                 |
| `aptup`          | `sudo apt update && sudo apt upgrade -y`           |
| `cleanzone`      | Remove Windows `Zone.Identifier` files             |
| `update-cursor`  | Update Cursor CLI (`agent update`, installer fallback) |
| `update-codex`   | Update Codex CLI (`npm i -g @openai/codex@latest`) |
| `update-claude`  | Update Claude CLI (`claude update`)                |
| `update-copilot` | Update Copilot CLI (`copilot update`)              |
| `update-all`     | Use `dotfiles update --all` (apt + CLIs)            |
| `cp`, `mv`, `rm` | Safety wrappers with `-i`                          |

---

## Update / re-apply

Apply the repo-first update workflow (the downstream plan is confirmed before mutation):

```bash
dotfiles update
```

Include opt-in runtime/font upgrades (Node.js via nvm, Go via asdf, Monaspace):

```bash
dotfiles update --all
```

Symlinks point to repo files, so edits are immediate. To refresh links manually:

```bash
dotfiles restow
# or:
cd ~/dotfiles && stow --restow bash bin readline
```

## Uninstall

```bash
cd ~/dotfiles
stow -D bash bin readline
```

---

## Logging

Every run of `install.sh` writes a timestamped log to `log/` (gitignored). Useful for debugging failed installs.

---

## Troubleshooting

### Stow conflicts

A real file exists where Stow wants a symlink. Back up and remove it, then re-run.

### `ex` or `clip` doesn't work

WSL interop may be disabled. Test with `/mnt/c/Windows/notepad.exe`. If that fails, check [WSL troubleshooting](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting).

### Docker permission denied

Log out and back in (or run `newgrp docker`) after install to activate the docker group.
