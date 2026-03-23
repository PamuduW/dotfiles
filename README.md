# WSL Bash dotfiles (GNU Stow)

Bootstraps a consistent Bash environment on Debian/Ubuntu WSL with an **interactive installer** and **GNU Stow** symlinks.

## What you get

- **Interactive installer** with toggle menu — pick exactly which components to install
- Custom Bash prompt: time, user@host, path, git branch + status markers, exit code
- Cross-terminal history syncing (`history -a; history -n`) with 10k line history
- Modern CLI tools: `eza`, `fzf` (Ctrl+R/Ctrl+T/Alt+C), `zoxide`, `ripgrep`, `fd`
- Better readline: case-insensitive completion, arrow-key history search
- Docker Engine + Portainer CE (with `dpot`/`dpotstop` shortcuts)
- Node.js via nvm, Python 3, Go
- AI CLI tools: Cursor, Codex, Claude (with `update-all` to keep them current)
- SSH key generation with GitHub setup notes
- WSL-specific config: systemd, clean PATH, Git credential helper, clipboard helper

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
│       └── clip        # copy to Windows clipboard from WSL
├── readline/
│   └── .inputrc        # better tab completion + history search
├── packages/
│   └── packages.txt    # apt packages with @tag sections
├── log/                # install logs (gitignored)
├── install.sh
└── README.md
```

Stow packages: `bash`, `bin`, `readline`

---

## Install

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
chmod +x install.sh bin/bin/ex bin/bin/clip
./install.sh
```

The installer will:

1. Show an **interactive menu** — arrow keys to navigate, space to toggle
2. Display the **execution plan** for review
3. Ask to **confirm, edit, or quit**
4. Prompt for **git identity** only if that component is enabled
5. Run only the selected components

### Component menu

| Component | What it does |
|-----------|-------------|
| Git identity | Set global `user.name` / `user.email` (auto-disabled if `includeIf` detected) |
| System packages | Core CLI tools from apt (@core, @cli, @system) |
| Python | python3, pip, venv |
| Go | golang-go |
| Node.js | v22 via nvm |
| Docker Engine | Docker CE from official repo + docker group |
| Portainer CE | Docker management UI (requires Docker) |
| lazygit | Git TUI from GitHub releases |
| lazydocker | Docker TUI from GitHub releases (requires Docker) |
| Cursor CLI | Cursor editor CLI from cursor.com |
| Codex CLI | OpenAI Codex CLI via npm (requires Node.js) |
| Claude CLI | Anthropic Claude CLI from claude.ai |
| Monaspace fonts | GitHub Monaspace Nerd Fonts to `~/.local/share/fonts/` |
| SSH key | ed25519 key + GitHub setup notes in `~/.ssh/github-setup.txt` |
| Dotfiles | Stow bash, bin, readline into `$HOME` |
| WSL config | `systemd=true`, `appendWindowsPath=false` in `/etc/wsl.conf` |
| Git credential | Windows Credential Manager for HTTPS auth |

Dependencies are enforced automatically (e.g., disabling Docker also disables Portainer).

**Multi-identity git setups**: If your `~/.gitconfig` uses `includeIf` for per-directory identities, the installer detects this and defaults "Git identity" to OFF so it won't overwrite your configuration.

---

## What changes in `$HOME`

After stowing:

- `~/.bashrc` → `dotfiles/bash/.bashrc`
- `~/.bash_aliases` → `dotfiles/bash/.bash_aliases`
- `~/.inputrc` → `dotfiles/readline/.inputrc`
- `~/bin/ex` → `dotfiles/bin/bin/ex`
- `~/bin/clip` → `dotfiles/bin/bin/clip`

---

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

Both use full Windows paths, so they work even with `appendWindowsPath=false`.

---

## Aliases highlights

| Alias | Command |
|-------|---------|
| `ll` | `eza -alF --git` (detailed list with git status) |
| `gitlog` | `git log --oneline --graph --decorate --all` |
| `dpot` | Start Portainer at `https://localhost:9443` |
| `dpotstop` | Stop Portainer |
| `reload` | `source ~/.bashrc` |
| `aptup` | `sudo apt update && sudo apt upgrade -y` |
| `cleanzone` | Remove Windows `Zone.Identifier` files |
| `update-cursor` | Update Cursor CLI (`agent update`) |
| `update-codex` | Update Codex CLI (`npm i -g @openai/codex@latest`) |
| `update-claude` | Update Claude CLI (`claude update`) |
| `update-all` | Update system packages + all AI CLI tools |
| `cp`, `mv`, `rm` | Safety wrappers with `-i` |

---

## Update / re-apply

Symlinks point to repo files, so edits are immediate. To refresh links:

```bash
cd ~/dotfiles
stow --restow bash bin readline
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
