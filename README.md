# WSL Bash dotfiles (GNU Stow)

Bootstraps a consistent Bash environment on Debian/Ubuntu WSL with an **interactive installer** and **GNU Stow** symlinks.

## What you get

- **Interactive boot menu** — `dotfiles` / `dotfiles menu` or `./install.sh`; loops through status, install, update, token, and library actions
- Custom Bash prompt: time, user@host, path, git branch + status markers, exit code
- Cross-terminal history syncing (`history -a; history -n`) with 10k line history
- Modern CLI tools: `eza`, `fzf` (Ctrl+R/Ctrl+T/Alt+C), `zoxide`, `ripgrep`, `fd`
- Better readline: case-insensitive completion, arrow-key history search
- Docker Engine + Portainer CE (with `dpot`/`dpotstop` shortcuts)
- Node.js via nvm, Python 3, Go (asdf), PowerShell, direnv
- Optional Graphify CLI (`graphifyy` through `uv`; selected by default)
- Optional verified Boost CLI preview binary (disabled by default)
- AI CLI tools: Cursor, Codex, Claude, Copilot (updated through the explicit `dotfiles update` workflow)
- SSH key generation with GitHub setup notes
- WSL-specific config: systemd, Windows PATH interop (`appendWindowsPath=true`), Git credentials and recursive-submodule defaults, clipboard helper

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
│       ├── codex-rc    # start or stop Codex Remote Control
│       ├── claude-rc   # manage one background Claude Remote Control server
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
│   ├── validate.sh     # syntax, static analysis, formatting, and test gate
│   ├── lib/            # TUI, component, update, and installer modules
│   │   └── updates/    # focused system, runtime, integration, and repo updates
│   └── menus/          # main + submenus
├── tests/
│   └── run.sh          # discovers and runs every shell test file
├── install.sh          # shim → scripts/install.sh
└── README.md
```

Stow packages: `bash`, `bin`, `readline`

---

## Install

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles 
chmod +x install.sh bin/bin/ex bin/bin/clip bin/bin/codex-rc bin/bin/claude-rc bin/bin/dotfiles
./install.sh
```

Entry points (interactive TTY):

- `dotfiles` or `dotfiles menu` — boot menu (after stow)
- `./install.sh` — same menu via root shim

The main menu **loops** until you choose Quit:

```
=== Dotfiles ===
  Check Status
  Install Dotfiles
  Update
  Full Update (Dotfiles + Agentbot)
  GitHub Token Config
  Libraries
  Quit
```

Use arrow keys to navigate and Enter to select.

### Boot menu

| Option | Submenu / action |
| ------ | ---------------- |
| Check Status | Read-only local report for all 22 setup components. |
| Install Dotfiles | Run the shared repository gate, then select components, review the execution plan, and apply setup. |
| Update | Repo-first fetch/classify/pull gate, then confirmed downstream updates. |
| Full Update (Dotfiles + Agentbot) | Confirms once, then runs `dotfiles full-update` unattended: Dotfiles update, then Agentbot install and update. |
| GitHub Token Config | Configure the optional shared API token without blocking anonymous use. |
| Libraries | Opens the read-only Command Lib and Package Lib submenu; `q` returns. |
| Quit | Exit |

### CLI flags

Skip the boot menu with explicit flags:

```bash
dotfiles status             # Read-only status
./install.sh --update       # Update submenu
./install.sh --help         # Usage
```

**Non-interactive** runs (no TTY on stdin — CI, piped, or redirected input) skip the boot menu and component toggle/confirm prompts. Behavior depends on the flag:

| Invocation | Behavior |
| ---------- | -------- |
| `./install.sh` (no flag, no TTY) | Runs the explicit non-interactive install path |
| `dotfiles status` | Prints local status without fetch, apt refresh, or writes |
| `./install.sh --update` | Runs update flow (non-interactive where applicable) |

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
| Git identity    | Set global `user.name` / `user.email` (disabled by default)                   |
| System packages | Core CLI tools from apt (@core, @cli, @system)                                |
| Python          | python3, pip, venv                                                            |
| Graphify CLI    | Optional `graphifyy` package through `uv`; exposes the `graphify` command (selected by default) |
| Boost CLI       | Checksum-verified Boost preview binary (disabled by default) |
| PowerShell      | Microsoft PowerShell from official Microsoft apt repository                   |
| Go              | Latest Go via asdf                                                            |
| Node.js         | v24 LTS via nvm                                                               |
| direnv          | Directory-based env loader + bash hook                                        |
| Docker Engine   | Docker CE from official repo + docker group                                   |
| Portainer CE    | Docker management UI (requires Docker)                                        |
| lazygit         | Git TUI from GitHub releases                                                  |
| lazydocker      | Docker TUI from GitHub releases (requires Docker)                             |
| Cursor CLI      | Cursor editor CLI from cursor.com                                             |
| Codex CLI       | OpenAI Codex CLI from the official standalone installer                       |
| Claude CLI      | Anthropic Claude CLI from claude.ai                                           |
| Copilot CLI     | GitHub Copilot CLI via gh.io/copilot-install                                  |
| Monaspace fonts | GitHub Monaspace Nerd Fonts to `~/.local/share/fonts/`                        |
| SSH key         | ed25519 key + GitHub setup notes in `~/.ssh/github-setup.txt`                 |
| Dotfiles        | Stow bash, bin, readline into `$HOME`                                         |
| WSL config      | `systemd=true`, `appendWindowsPath=true` in `/etc/wsl.conf`                   |
| Git config (credentials + submodules) | Windows GCM for HTTPS when available; recursive checkout/fetch/status defaults |

Dependencies are enforced automatically (e.g., disabling Docker also disables Portainer).

## Codex CLI migration

Dotfiles owns Codex only when `~/.local/bin/codex` resolves into
`~/.codex/packages/standalone/` and that same command is active on `PATH`. The
Codex component uses the official standalone installer and has no Node.js
dependency:

```bash
DOTFILES_COMPONENTS=codex_cli ./install.sh --initial
```

Inspect ownership before installing or updating:

```bash
which -a codex
command -v codex
readlink -f "$(command -v codex)" 2>/dev/null
dotfiles status
dotfiles doctor
```

An `external` result means the active command is outside the standalone tree.
A `standalone shadowed` result means the managed standalone link exists, but a
different command wins on `PATH`.

When every external Codex command is a verified NVM installation of the
`@openai/codex` package, the interactive Codex component inventories all Node
trees, shows every path and version, and asks for a dedicated migration
confirmation. Approval removes the package from each verified tree, proves no
Codex command or package directory remains there, and then installs standalone.
It never deletes `~/.codex`, which contains configuration, authentication,
sessions, skills, and local state.

Non-interactive installation requires separate migration authorization:

```bash
DOTFILES_COMPONENTS=codex_cli \
DOTFILES_MIGRATE_NPM_CODEX=1 \
./install.sh --initial
```

Without that exact opt-in, the non-interactive installer preserves npm Codex
and fails with migration guidance. Dotfiles also refuses migration when the
active command is unrelated, a command does not resolve into its exact
`@openai/codex` package directory, npm is unavailable in a detected tree, an
uninstall fails, or any command or package artifact remains afterwards. Resolve
those states explicitly rather than forcing the standalone installer over them.

`dotfiles update` updates an installed, active standalone Codex through the
same official installer. It skips an absent Codex and preserves external or
shadowing commands; it never implicitly authorizes npm removal.
`dotfiles full-update` follows that Dotfiles lifecycle and
then runs Agentbot; Agentbot manages policy under `~/.codex`, not the Codex
executable.

On Linux, `codex-code-mode-host` stays inside
`~/.codex/packages/standalone/current/bin/`. A separate
`~/.local/bin/codex-code-mode-host` link is not required.

### Remote Control handoff

Remote Control is an explicit operator step after standalone ownership is
healthy. Start the daemon, inspect it, and request a short-lived pairing code:

```bash
codex remote-control start --json
codex doctor --json | jq '.checks["app_server.status"]'
codex remote-control pair --json
```

The pairing command prints secret pairing fields to the current terminal. Read
the manual code there and enter it in the client. Do not redirect, log, save,
screenshot, commit, or paste the code into chat. Stop the daemon later with
`codex remote-control stop --json` when Remote Control is no longer needed.

### Optional Graphify CLI

`graphify_cli` is a selectable component enabled by default. It requires Python
3.10+ and installs the official Graphify package as a user tool with
`uv tool install graphifyy`; the installed command is `graphify`. If `uv` is
missing, the component may install it through Astral's official installer.

Dotfiles owns only this CLI component. It does not install Graphify's
assistant skill or edit project `AGENTS.md`, Cursor rules, hooks, or graph data.
After installing the CLI, use Agentbot separately if you want its optional
Graphify Agent Skills integration. Direct `agentbot graphify status` and
`agentbot graphify setup` remain available for inspection and repair; Dotfiles
does not launch or update Agentbot.

### Optional Boost CLI

`boost_cli` is disabled by default. A fresh selection resolves the latest
official Boost release for the current amd64/arm64 architecture, verifies its
published SHA-256 digest, and installs only `boost` to `~/.local/bin`.
Dotfiles never runs `boost init`, accepts agreements, or edits assistant files.

After installing the CLI, run Agentbot setup. `agentbot install` previews and
configures only the Claude and Codex shell-output integration with BoostGraph
disabled. `agentbot boost status|setup|off` provides explicit inspection,
repair, and removal commands.

### Git config (credentials + submodules)

This component always writes these idempotent global Git defaults:

```bash
git config --global submodule.recurse true
git config --global fetch.recurseSubmodules on-demand
git config --global status.submoduleSummary true
```

They make supported Git commands recurse into initialized submodules, fetch
changed populated submodules on demand, and show changed-submodule commit
summaries in long `git status` output. They affect real Git submodules only,
not unrelated sibling repositories.

When Git for Windows provides `git-credential-manager.exe`, the same component
sets it as WSL Git's `credential.helper` for HTTPS authentication and Windows
credential storage. If GCM is unavailable, the submodule defaults still apply
and any existing credential helper remains unchanged. SSH remotes do not use
this credential helper. The stable component key remains `git_credential` for
existing `DOTFILES_COMPONENTS` automation.

**Multi-identity git setups**: "Git identity" defaults to OFF, so an existing
`includeIf`-based per-directory identity is not overwritten unless you
explicitly select this component.

## Security notes

- Vendor shell installers (Cursor, Claude, Copilot, nvm, direnv) are downloaded over HTTPS to a temporary file and syntax-checked before Bash executes them. The vendor URLs are still moving channels rather than checksum-pinned artifacts; review upstream when stronger provenance is required.
- GitHub-release binaries (lazygit, lazydocker) are checksum-verified during install.
- Portainer uses an explicit image version (`portainer/portainer-ce:2.43.0` by default); set `PORTAINER_IMAGE` deliberately to override it.
- The generated SSH key prompts for a passphrase (press Enter to skip).

---

## What changes in `$HOME`

After stowing:

- `~/.bashrc` → `dotfiles/bash/.bashrc`
- `~/.bash_aliases` → `dotfiles/bash/.bash_aliases`
- `~/.inputrc` → `dotfiles/readline/.inputrc`
- `~/bin/ex` → `dotfiles/bin/bin/ex`
- `~/bin/clip` → `dotfiles/bin/bin/clip`
- `~/bin/codex-rc` → `dotfiles/bin/bin/codex-rc`
- `~/bin/claude-rc` → `dotfiles/bin/bin/claude-rc`
- `~/bin/dotfiles` → `dotfiles/bin/bin/dotfiles`

---

## `dotfiles` command

Global command (stowed to `~/bin/dotfiles`, on PATH like `ex` and `clip`):

| Subcommand | Action |
| ---------- | ------ |
| `dotfiles` | On a TTY, opens the boot menu; otherwise prints help |
| `dotfiles menu` | Boot menu (same as `./install.sh`) |
| `dotfiles update` | **Apply after one confirmation** — repo-first gate, then all managed apt/CLI/runtime/font changes |
| `dotfiles update --all` | Accepted for compatibility; selects nothing extra (one approval already runs every managed update) |
| `dotfiles update --dry-run` | Print the update report, then stop before any downstream change |
| `dotfiles full-update` | Unattended Dotfiles and Agentbot update, followed by read-only health checks |
| `dotfiles doctor` | Only the components needing attention, plus the command that fixes each; exits nonzero when anything does |
| `dotfiles status` | Local installed versions + repo state; no fetch or apt refresh |
| `dotfiles logs [--list\|--last]` | List retained action logs, or print the newest |
| `dotfiles commands` | Read-only full command, option, configuration, and integration reference |
| `dotfiles packages` | Read-only component/package catalog |
| `dotfiles restow` | `stow --restow bash bin readline` |

The interactive **Command Lib** is a selectable command index: open one command
for its focused usage, options, effects, examples, and related commands, then
return directly to the index. `dotfiles commands` and `dotfiles help` continue
to print the complete reference. All three views are read-only and use the same
authoritative metadata.

`dotfiles status` runs independent local component probes concurrently while
preserving the component registry order. External version checks are bounded;
a stalled tool is reported as needing attention instead of freezing the status
screen.

Most CLI updates run as your user. System package, PowerShell, Docker,
`/etc/wsl.conf`, `/usr/local/bin`, and Docker-group changes invoke `sudo` when
needed; the terminal may reuse the active sudo credential cache.

When Graphify is selected, `dotfiles update` (including `dotfiles update --all`)
updates it with `uv tool upgrade graphifyy` only when `uv tool list` proves that
the installed `graphify` command is owned by the `graphifyy` tool. If that
upgrade fails, Dotfiles retries once with
`uv tool upgrade graphifyy --system-certs`. An external or otherwise unproven
Graphify installation is preserved and reported as externally managed; update
it through its own owner instead. Dotfiles does not run any Graphify assistant
installer during install or update.
After a successful CLI upgrade, Dotfiles prints a non-mutating handoff for an
already-enabled Agentbot integration: run `agentbot graphify setup` or
`agentbot update` to refresh the installed skill version. The CLI and skill may
otherwise remain temporarily out of sync; Dotfiles never calls Agentbot or
enables the skill automatically.

Install and an explicitly approved `dotfiles update` use the same latest-release
path. The release tag and architecture-specific asset digest come from one
GitHub Releases API snapshot; a missing or invalid digest fails closed and
preserves an installed binary or leaves a fresh install untouched.
Missing or externally managed Boost binaries are skipped. Dotfiles never runs
Boost initialization during an install or update, and Boost's own auto-update
remains disabled by Agentbot.

Install and Update call the same repository-update service before doing any
setup or downstream work. It validates the repository and upstream, captures
local changes, fetches `origin`, and classifies the verified ahead/behind
state. Dirty, ahead, and diverged checkouts can be replaced after approval.
Before replacement, the updater stashes tracked and untracked changes and
creates a timestamped `recovery/dotfiles-*` branch for local commits. It stops
if either backup fails, never runs `git clean`, and leaves ignored files alone.

For a clean repository, an available pull is shown in a colored repository
table and requires confirmation. After a pull, press Enter to restart
`install.sh` from the updated checkout. When the repository is current, Update
shows the full colored installed/available/action report and asks once whether
to continue. An affirmative answer includes Node.js, npm, Go, and Monaspace.
It finishes with a colored result table and returns to the menu after Enter.

The npm updater captures one
exact registry target, asks NVM for the latest compatible npm, and then checks
the installed version instead of trusting command output or exit status. If
NVM does not reach the target, Dotfiles retries that exact version with
command-local `--engine-strict --allow-remote=all` settings and verifies again.
A still-old npm is reported as a failed step with a copyable retry command.
Dotfiles never writes this remote-package policy to an npmrc file.

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

### Remote Control helpers

- `codex-rc start` / `codex-rc stop` — delegate to Codex's native persistent Remote Control daemon.
- `claude-rc start` — start one background Claude Remote Control server rooted at the current directory.
- `claude-rc stop` — stop that server safely from any directory.

Claude server state and its private log live under
`${XDG_STATE_HOME:-$HOME/.local/state}/claude-rc/`. A second start reports the
existing server instead of creating another one. After WSL shuts down, run the
appropriate `*-rc start` command again; device pairings remain separate from
the local server process.

---

## Aliases highlights

| Alias            | Command                                            |
| ---------------- | -------------------------------------------------- |
| `ll`             | `eza -alF --git` (detailed list with git status)   |
| `gitlog`         | `git log --oneline --graph --decorate --all`       |
| `dpot`           | Start Portainer at `https://localhost:9443`        |
| `dpotstop`       | Stop Portainer                                     |
| `reload`         | `source ~/.bashrc`                                 |
| `codex-safe`     | Codex workspace-write sandbox with model-requested approval |
| `codex-host`     | Codex automatic approval review with workspace-write sandbox |
| `aptup`          | `sudo apt update && sudo apt upgrade -y`           |
| `cleanzone`      | Remove Windows `Zone.Identifier` files             |
| `update-cursor`  | Update Cursor CLI (`agent update`, installer fallback) |
| `update-codex`   | Run the guarded `dotfiles update` workflow        |
| `update-claude`  | Update Claude CLI (`claude update`)                |
| `update-copilot` | Update Copilot CLI (`copilot update`)              |
| `update-all`     | Use `dotfiles update --all` (apt + CLIs)            |
| `cp`, `mv`, `rm` | Safety wrappers with `-i`                          |

`codex-host` no longer means danger-full-access. It selects Codex's automatic
approval review while retaining the workspace-write sandbox. Full access
remains an explicit direct Codex invocation and is not wrapped by Dotfiles.

---

## Update / re-apply

Apply the repo-first update workflow (the downstream plan is confirmed before mutation):

```bash
dotfiles update
```

`--all` is still accepted so existing scripts and the `update-all` alias keep
working, but it selects nothing extra — one approved update already includes
Node.js, npm, Go, and the Monaspace fonts:

```bash
dotfiles update --all
```

Update Dotfiles, install Agentbot, and update Agentbot with one unattended
application-level command (also available from the boot menu as
**Full Update (Dotfiles + Agentbot)**, which confirms once before starting):

```bash
dotfiles full-update
```

This command automatically restarts once after either repository changes. It
also authorizes recoverable replacement of dirty, ahead, or diverged local Git
state. `sudo` may still request system authentication.

Before crossing into Agentbot, the command prints the resolved Dotfiles and
Agentbot launchers and checkout roots. It refuses to run an Agentbot launcher
outside the sibling `agent_bootstrap` checkout (or the explicit
`FULL_UPDATE_EXPECTED_AGENTBOT_HOME` used by test and recovery workflows).
After both update stages, it runs `dotfiles doctor` and `agentbot doctor`
without repairing anything. A healthy postflight prints `Full system update
completed.`; Agentbot warnings print `completed with warnings` and still exit
zero; Dotfiles Doctor failures or Agentbot errors print `Updates succeeded;
system needs attention` and exit nonzero.

It stops at the first failing stage rather than pressing on. In particular, a
skill source that fails to install makes `agentbot install` exit nonzero, which
ends the run before the Agentbot update stage. Read the log in `log/`, fix the
source, and rerun.

Inspect preserved work with:

```bash
git branch --list 'recovery/*'
git stash list
git show recovery/dotfiles-YYYYMMDD-HHMMSS
git stash show --stat <stash-object-id>
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

Mutating install and update actions — including `dotfiles full-update` — write a
timestamped log to `log/` (gitignored). Read-only menu navigation and `--help` do
not initialize a log. The newest 20 logs are kept; older ones and any orphaned
`.log.raw` capture from an interrupted run are pruned when the next log starts.
Override the count with `DOTFILES_LOG_RETAIN`.

## Development validation

Run the complete local gate before committing:

```bash
scripts/validate.sh
```

It checks Bash syntax, runs ShellCheck, verifies `shfmt` formatting, and
discovers every test through `tests/run.sh`. Use `scripts/validate.sh --format`
to format shell sources before running the same gate. GitHub Actions runs the
same command.

---

## Troubleshooting

### Stow conflicts

A real file exists where Stow wants a symlink. Back up and remove it, then re-run.

### `ex` or `clip` doesn't work

WSL interop may be disabled. Test with `/mnt/c/Windows/notepad.exe`. If that fails, check [WSL troubleshooting](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting).

### Docker permission denied

Log out and back in (or run `newgrp docker`) after install to activate the docker group.
