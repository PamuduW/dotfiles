# WSL Bash dotfiles (GNU Stow)

Bootstraps a consistent Bash environment on Debian/Ubuntu WSL with an **interactive installer** and **GNU Stow** symlinks.

## What you get

- **Interactive boot menu** — `dotfiles` / `dotfiles menu` or `./install.sh`; loops through initial setup, update, and agents
- Custom Bash prompt: time, user@host, path, git branch + status markers, exit code
- Cross-terminal history syncing (`history -a; history -n`) with 10k line history
- Modern CLI tools: `eza`, `fzf` (Ctrl+R/Ctrl+T/Alt+C), `zoxide`, `ripgrep`, `fd`
- Better readline: case-insensitive completion, arrow-key history search
- Docker Engine + Portainer CE (with `dpot`/`dpotstop` shortcuts)
- Node.js via nvm, Python 3, Go (asdf), PowerShell, direnv
- AI CLI tools: Cursor, Codex, Claude, Copilot (with `dotfiles upgrade` / `update-all` to keep them current)
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
│       └── dotfiles    # report/apply upgrades, status, restow, self
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

The **Agents** submenu expects `agent_bootstrap` as a **sibling** of this repo (not a fixed `~/Dev` path):

```text
parent/
├── dotfiles/           # this repo
└── agent_bootstrap/    # clone target for Agents → Clone/update repo
```

Clone manually or use **Agents → Clone/update repo**. `AGENT_BOOTSTRAP_HOME` is set from the sibling path when `install.sh` exists there. A standalone `agent_bootstrap` clone elsewhere still works for direct `./install.sh` use; override with `AGENT_BOOTSTRAP_ALLOW_OVERRIDE=1` if dotfiles should point at a non-sibling path.

Entry points (interactive TTY):

- `dotfiles` or `dotfiles menu` — boot menu (after stow)
- `./install.sh` — same menu via root shim

The main menu **loops** until you choose Quit:

```
=== Dotfiles ===
  Initial setup
  Update
  Agents
  Quit
```

Use arrow keys to navigate and Enter to select.

### Boot menu

| Option | Submenu / action |
| ------ | ---------------- |
| Initial setup | **Check status** — component install summary table · **Run setup** — toggle menu, confirm loop, install · **Back** |
| Update | **Update & upgrade** — `dotfiles update` report, then optional `dotfiles upgrade` (prompts for `--all`) · **Back** |
| Agents | **Check status** · **Clone/update repo** · **Run full bootstrap** · **Refresh skills only** · **Link agentboot** · **Scaffold repo (agentboot)** · **Run doctor** · **Back** |
| Quit | Exit |

### CLI flags

Skip the boot menu with explicit flags:

```bash
./install.sh --initial      # Initial setup submenu (or run setup if non-interactive)
./install.sh --update       # Update submenu
./install.sh --agents       # Agents submenu
./install.sh --help         # Usage
```

**Non-interactive** runs (no TTY on stdin — CI, piped, or redirected input) skip the boot menu and component toggle/confirm prompts. Behavior depends on the flag:

| Invocation | Behavior |
| ---------- | -------- |
| `./install.sh` (no flag, no TTY) | Runs **Initial setup → Run setup** with all components enabled by default |
| `./install.sh --initial` (no TTY) | Same as above — prints execution plan to stdout, then installs |
| `./install.sh --update` | Runs update flow (non-interactive where applicable) |
| `./install.sh --agents` | Opens agents submenu (requires TTY for interactive menu) |

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
| `dotfiles update` | **Report only** — check apt, agent CLIs, runtimes, and the dotfiles repo; print what can be upgraded (no changes) |
| `dotfiles upgrade` | **Apply** — run upgrades (apt, CLIs, **dotfiles git pull + restow**, etc.); idempotent and safe to re-run |
| `dotfiles upgrade --all` | Same as `upgrade`, plus opt-in **Node.js** (nvm LTS), **Go** (asdf), and **Monaspace** fonts |
| `dotfiles status` | Installed versions + dotfiles repo git status |
| `dotfiles restow` | `stow --restow bash bin readline` |
| `dotfiles self` | Fast-forward pull in a **clean** dotfiles worktree, then restow; commit or stash local changes first |

Runs **unprivileged**; only the apt portion invokes `sudo` internally (single prompt). Agent CLI and npm updates stay under your user.

### Agents — `agent_bootstrap`

The **Agents** submenu clones and bootstraps [`agent_bootstrap`](https://github.com/PamuduW/agent_bootstrap) as a sibling of this dotfiles repo (e.g. `~/Dev/agent_bootstrap` next to `~/Dev/dotfiles`).

| Action | What it does |
| ------ | ------------ |
| Check status | Repo path, git state, skills count, doctor summary |
| Clone/update repo | `git clone` or `git pull` at the sibling path |
| Run full bootstrap | `./install.sh` in the clone |
| Refresh skills only | `./install.sh skills update` |
| Link agentboot | Symlink `bin/agentboot` → `~/bin/agentboot` |
| Scaffold repo | Run `agentboot` in a chosen git repo |
| Run doctor | `./install.sh doctor` |

**Environment overrides (advanced):**

| Variable | Default | Notes |
| -------- | ------- | ----- |
| `AGENT_BOOTSTRAP_REPO_URL` | `git@github.com:PamuduW/agent_bootstrap.git` | Clone URL; must match the allowlist unless bypass is set |
| `AGENT_BOOTSTRAP_REPO_URL_ALLOW_ANY` | unset | Set to `1` to clone any URL (**unsafe** — disables supply-chain guard) |
| `AGENT_BOOTSTRAP_CLONE_HOME` | sibling of dotfiles | Override clone target directory |
| `AGENT_BOOTSTRAP_ALLOW_OVERRIDE` | unset | Set to `1` to use a non-canonical `AGENT_BOOTSTRAP_HOME` (**unsafe** — can point bootstrap at an arbitrary tree) |

When `AGENT_BOOTSTRAP_REPO_URL` is overridden, clone is refused unless the URL is `git@github.com:PamuduW/agent_bootstrap.git` or `https://github.com/PamuduW/agent_bootstrap.git`, or `AGENT_BOOTSTRAP_REPO_URL_ALLOW_ANY=1` is set.

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
| `update-cursor`  | Update Cursor CLI (`agent update`)                 |
| `update-codex`   | Update Codex CLI (`npm i -g @openai/codex@latest`) |
| `update-claude`  | Update Claude CLI (`claude update`)                |
| `update-copilot` | Update Copilot CLI (`copilot update`)              |
| `update-all`     | Delegates to `dotfiles upgrade` (apt + CLIs)       |
| `cp`, `mv`, `rm` | Safety wrappers with `-i`                          |

---

## Update / re-apply

Check what can be upgraded without changing anything:

```bash
dotfiles update
```

Apply upgrades (apt, agent CLIs, etc.):

```bash
dotfiles upgrade
# or the alias:
update-all
```

Include opt-in runtime/font upgrades (Node.js via nvm, Go via asdf, Monaspace):

```bash
dotfiles upgrade --all
```

Pull latest dotfiles and refresh symlinks:

```bash
dotfiles self
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
