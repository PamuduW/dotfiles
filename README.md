# WSL Bash dotfiles (GNU Stow)

Bootstraps a consistent Bash environment on Debian/Ubuntu WSL with an **interactive installer** and **GNU Stow** symlinks.

## What you get

- **Interactive boot menu** — choose initial setup, update, extensions, or agents; component toggle menu for installs
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
├── extensions/         # IDE extension manifests (git-tracked)
│   ├── vscode-wsl.txt
│   ├── cursor-wsl.txt
│   ├── vscode-win.txt
│   ├── cursor-win.txt
│   ├── cursor-core.txt       # lean Cursor restore target (~39 extensions)
│   ├── manifest.json         # backup metadata (timestamp, counts)
│   └── extensions-decisions.md  # prune/add checklist before applying changes
├── templates/
│   └── vscode-extensions.json  # lean workspace recommendations template
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
chmod +x install.sh bin/bin/ex bin/bin/clip bin/bin/dotfiles
./install.sh
```

When run **interactively** (stdout is a TTY), `./install.sh` shows a **boot menu** first:

```
=== Dotfiles ===
  1. Initial setup   → component install menu + confirm + install
  2. Update          → dotfiles update report, then optional upgrade
  3. Extensions      → IDE extensions menu (check / backup / restore / compare)
  4. Agents          → agentic setup (agent_bootstrap, agentboot)
  5. Quit
```

Use arrow keys to navigate and Enter to select (same TUI as the component menu).

### Boot menu

| Option | Action |
| ------ | ------ |
| Initial setup | Component toggle menu, confirm loop, then install (same behavior as before Stage 3) |
| Update | Runs `dotfiles update` (report only), then prompts **Proceed with upgrades? [y/N]** — on yes, runs `dotfiles upgrade` |
| Extensions | IDE extensions submenu (check / backup / restore / compare) |
| Agents | Agent bootstrap submenu (clone/run `agent_bootstrap` installer, `agentboot`) |
| Quit | Exit without changes |

### CLI flags

Skip the boot menu with explicit flags:

```bash
./install.sh --initial      # Initial setup (component menu)
./install.sh --update       # Update flow only
./install.sh --extensions   # Extensions menu
./install.sh --agents       # Agents menu
./install.sh --help         # Usage
```

**Non-interactive** runs (piped input, CI, or stdout not a TTY) skip the boot menu and run the **Initial setup** path directly — equivalent to `./install.sh --initial`.

When you choose **Initial setup** (boot menu option 1, or the non-interactive default), the installer will:

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
| `dotfiles update` | **Report only** — check apt, agent CLIs, runtimes, and the dotfiles repo; print what can be upgraded (no changes) |
| `dotfiles upgrade` | **Apply** — run upgrades (apt, CLIs, etc.); idempotent and safe to re-run |
| `dotfiles upgrade --all` | Same as `upgrade`, plus opt-in **Node.js** (nvm LTS), **Go** (asdf), and **Monaspace** fonts |
| `dotfiles upgrade --all` | Same as `upgrade`, plus opt-in: Node.js (nvm LTS), Go (asdf), Monaspace Nerd Fonts |
| `dotfiles status` | Installed versions + dotfiles repo git status |
| `dotfiles restow` | `stow --restow bash bin readline` |
| `dotfiles self` | `git pull` in the dotfiles repo, then restow |

Runs **unprivileged**; only the apt portion invokes `sudo` internally (single prompt). Agent CLI and npm updates stay under your user.

### `dotfiles ext` — IDE extensions

Manage VS Code and Cursor extensions across four targets: `vscode-wsl`, `cursor-wsl`, `vscode-win`, `cursor-win`.

| Subcommand | Action |
| ---------- | ------ |
| `dotfiles ext check [target\|all]` | Report installed count, CLI vs disk method, stale folders |
| `dotfiles ext backup [target\|all]` | Export manifests to `extensions/*.txt` + update `manifest.json` |
| `dotfiles ext restore [target] [manifest]` | Install from manifest (`publisher.ext@version` per line); default manifest matches target name |
| `dotfiles ext compare [target]` | Diff manifest vs installed: only-in-backup, only-installed, version drift |

**Manifest layout** (`extensions/`):

- `vscode-wsl.txt`, `cursor-wsl.txt`, `vscode-win.txt`, `cursor-win.txt` — lean inventories (one `publisher.ext@version` per line; see **Applying lean set** below)
- `cursor-core.txt` — lean Cursor restore set (keep list + recommended adds, minus prune candidates)
- `manifest.json` — `{ "generated": "<ISO>", "targets": { "<name>": { "count", "method" } } }`
- `extensions-decisions.md` — human checklist to confirm prune/add before applying changes

**Restore examples:**

```bash
# Restore lean Cursor-WSL set (primary WSL target)
dotfiles ext restore cursor-wsl extensions/cursor-core.txt

# Backup all targets after manual changes
dotfiles ext backup all

# Compare drift on Windows VS Code
dotfiles ext compare vscode-win
```

**Workspace recommendations:** copy `templates/vscode-extensions.json` to a repo's `.vscode/extensions.json` for lean team recommendations (does not auto-install).

Access via boot menu option **3. Extensions** or `./install.sh --extensions`.

### Applying lean set

Lean manifests were applied on **2026-07-08** per `extensions/extensions-decisions.md` (user confirmed prune/add on all targets). Counts:

| Target | Before | After |
| ------ | -----: | ----: |
| `cursor-wsl` | 49 | 39 |
| `cursor-win` | 96 | 40 |
| `vscode-wsl` | 82 | 45 |
| `vscode-win` | 114 | 63 |

**Canonical Cursor set:** `extensions/cursor-core.txt` (~39 extensions). `cursor-wsl.txt` and `cursor-win.txt` match this set (+ `anysphere.remote-wsl` on Windows).

**What was pruned (high confidence):** Flutter/Dart, Azure service sprawl, legacy Docker, Copilot/ChatGPT companions, Java stack, HTML preview cluster, redundant Git/GitLab/bash-pack extensions, web front-end noise, misc low-use tools. VS Code Windows also dropped AKS tools, Jupyter stack, and remote meta-pack.

**What was added:** `hashicorp.terraform`, `amazonwebservices.aws-toolkit-vscode`, `usernamehw.errorlens`, `tamasfe.even-better-toml`, `eamodio.gitlens` (WSL targets; already on vscode-win). GCP Cloud Code was **not** added (not in any prior manifest).

**Apply to live editors** (open the target editor first — restore without a running server may fail on WSL):

```bash
# Install lean manifest per target
dotfiles ext restore cursor-wsl
dotfiles ext restore cursor-win
dotfiles ext restore vscode-wsl
dotfiles ext restore vscode-win

# Then prune extras not in manifest (destructive — review with compare first)
dotfiles ext compare cursor-wsl    # optional: preview drift
dotfiles ext restore cursor-wsl --prune
# repeat --prune per target, or:
dotfiles ext restore all --prune

# Refresh manifests after live changes
dotfiles ext backup all
```

Manifest metadata: `extensions/manifest.json` (`note: lean-applied`).

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
