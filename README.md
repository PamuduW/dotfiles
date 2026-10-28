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
deleted or moved.

Before installation, bootstrap reuses a valid saved or environment GitHub
token. If neither is available, it opens the optional token screen: choose
**Save or replace**, enter a read-only token, confirm, then choose **Back**.
The token is saved outside the repositories and used by downloads in this same
run. You can skip it, but unauthenticated downloads may hit GitHub rate limits.

The selected setup then runs the Dotfiles component selector and execution
plan, the Dotfiles update, Agentbot's component selector and plan, and the
Agentbot update. A destination that cannot be used safely stops the run with a
report. The script also offers your memory vault, which it cannot guess: when
Agentbot is installed and no vault is configured, it asks for
the vault's Git URL or an existing folder (Enter skips), then sets it up with
its commit and push checks. The run ends with one Agentbot Doctor. What you
choose in Agentbot's selector holds for the whole bootstrap: the Agentbot update
that follows configures only those components and reports the rest. The
selectors shape this first run only: a later `dotfiles full-update` keeps every
component current. Backing out of Agentbot's selector skips its update and the
memory step too, and a failed Agentbot phase makes the script exit non-zero.

For a first-time memory setup, create an empty private GitHub repository and
enter its SSH or HTTPS URL at the bootstrap's vault prompt. Agentbot clones it,
initializes the vault, and configures this machine. Existing vaults clone normally;
repositories containing other files or history are rejected. Setup does not push
the initial commit; see [Set up Agentbot memory](#set-up-agentbot-memory).
For a GitHub SSH URL, setup first checks authentication, handles the first host
key confirmation, and offers to reuse or create an SSH key when needed. It shows
the public key for you to add to GitHub before retrying. See the
[SSH setup flow](docs/installation.md#github-ssh-for-the-memory-vault).

To read the script before running it, or on a machine that already has Git:

```bash
sudo apt-get install -y git
git clone https://github.com/PamuduW/dotfiles "$HOME/dotfiles"
"$HOME/dotfiles"/bootstrap.sh
```

To work with an existing checkout directly. The shared library is a separate
repository that this installer loads at runtime, and `bootstrap.sh` clones it
for you; clone it yourself when you are skipping bootstrap:

```bash
git clone https://github.com/PamuduW/dotfiles-shared "$HOME/dotfiles-shared"
cd "$HOME/dotfiles"
./install.sh
```

It is found beside this checkout, or at `$HOME/dotfiles-shared`, or wherever
`DOTFILES_SHARED_DIR` points. A missing one stops with the clone command rather
than a failure part-way through.

The interactive menu offers:

```text
Check status
Install Dotfiles
Update
Full update (Dotfiles + Agentbot)
Logs
Restow
GitHub token config
Libraries
Quit
```

Every public `dotfiles` command is reachable from the menu. Check status also
carries what `dotfiles doctor` reports: when a component needs attention it
lists which, and the command that fixes it.

Install Dotfiles checks the repository, opens the component selector, shows an
execution plan, and asks for confirmation. Git identity is off by default;
other registered components start selected. Dependencies such as Portainer
requiring Docker are enforced automatically.

The execution plan offers two ways to confirm:

| Key | Meaning |
|---|---|
| `c` | Install, skipping components that are already present |
| `x` | Install, reinstalling components that are already present |

`x` exists to repair a corrupted install without deleting things by hand. It
bypasses *presence* checks only ("lazygit is already installed"). It does not
bypass *content* checks — `/etc/wsl.conf`, `/etc/docker/daemon.json` and
`~/.bash_profile` compare what is on disk and rewrite when it differs, so they
already repair themselves and forcing them would only add churn and backups.

The same behaviour is available unattended as `dotfiles full-update --force`,
which reinstalls the components it finds already present. It carries the flag
across the restart a repository update triggers, so a forced run stays forced.

Git identity ignores `x` entirely: it reads answers the plan screen has already
collected.

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
| `dotfiles full-update` | Update Dotfiles, run `agentbot full`, and perform postflight health checks (short form: `dotfiles fu`) |
| `dotfiles restow` | Reapply the `bash`, `bin`, and `readline` Stow packages |
| `dotfiles logs [--list\|--last]` | List retained action logs or print the newest |
| `dotfiles commands` | Print authoritative command and configuration metadata |
| `dotfiles packages` | Print component and apt-package metadata without probing |

For non-interactive installation, select stable component keys explicitly:

```bash
DOTFILES_COMPONENTS=system_packages,docker,portainer,dotfiles \
  ./install.sh --install
```

## Component summary

The registry contains 33 components:

| Area | Components |
|---|---|
| Base system | system packages, Python packages, PowerShell, WSL configuration |
| Languages | Go through asdf, Node.js and npm through nvm, direnv |
| Containers | Docker Engine, Portainer CE LTS, lazydocker |
| Developer tools | Graphify CLI, Boost CLI, lazygit, Kubeconform, TFLint, zizmor, Trivy, Infracost, Chrome headless shell, Ubuntu Sans Mono fonts |
| Writing and documents | Vale, CSpell, markdownlint-cli2, Mermaid CLI, yt-dlp |
| Agent CLIs | Cursor, standalone Codex, Claude, Antigravity |
| Desktop apps (WSLg) | Obsidian |
| Shell and Git | Stow packages, Git identity, Git credentials/submodule defaults |

The software catalog qualification target is Ubuntu 24.04 AMD64. ARM64 and
WSL2/Windows integration are outside the current catalog qualification claim.
Cursor CLI is an operator-managed exception: catalog installs (including forced
installs) and updates skip it, while update status reports its installed version.
Install and update Cursor manually; its own automatic updater remains outside
catalog control.

The hosted catalog workflow also tests real legacy NVM/Node and asdf/Go layouts
in a separate disposable Ubuntu home. Its frozen vendor inputs exercise refused
migration, unavailable downloads, explicit migration, repeat runs, preserved
global npm commands and configuration, and real Node execution and Go compilation.
This runtime test produces unapproved smoke evidence. A complete legacy setup,
the remaining component migrations and the full qualification controller are
still required before the first catalog can be approved.

Obsidian installs from its official amd64 `.deb`, verified against the SHA-256
GitHub publishes for it, and opens on the Windows desktop through WSLg (from the
Start menu or by running `obsidian`). The install is skipped when the session has
no GUI display, and an Obsidian installed another way is left alone. Full update
keeps it current once it is installed.

The Antigravity CLI (`agy`) installs from the release manifest its own
installer reads, verified against the SHA-512 digest in that manifest. Dotfiles
does not run the vendor one-liner or `agy install`: both append a PATH export
to `~/.bashrc` and `~/.profile`, and `~/.bashrc` is a Stow link into this
repository, so the write would land in the checkout. `~/.bashrc` already puts
`~/.local/bin` on PATH. If you ran the one-liner by hand, remove the
`# Added by Antigravity CLI installer` block from `bash/.bashrc`.

The exact keys, dependencies, defaults, and descriptions are available through
`dotfiles packages` and documented in [Component lifecycle](docs/components.md).

The `ubuntu_sans_mono_fonts` component installs the latest official Canonical
Ubuntu Sans Mono static TTFs in `~/.local/share/fonts/ubuntu-sans-mono`, with
SHA-256 verification. In WSL it also installs and registers them for the current
Windows user, so desktop VS Code and Windows Terminal can use them without
administrator access. Restart those apps if the font is not immediately listed.
If Windows interop is unavailable, WSL installation still works; install the
font on Windows manually or rerun the component after enabling interop. Windows
installation errors are reported and can be retried by rerunning the component.
Windows updates use versioned filenames so loaded font files need not be
overwritten. Previous Windows font files and extra WSL font files are retained.

This replaces the former Monaspace component. Existing Monaspace files are left
in place, but are no longer installed or updated. Ubuntu Sans Mono is the
original, unpatched family and does not include Nerd Fonts icons. The Windows
Terminal template uses it; importing that template remains a manual step.

## Existing NVM installations

The catalog preserves an existing NVM installation until you authorize migration.
The Node component lists its NVM root and active Node/npm prefix, then asks for
confirmation. For a noninteractive installation, set `DOTFILES_MIGRATE_NVM=1`
only for the command that installs or updates Node. Force reinstall does not
grant migration permission.

Migration requires the normal `~/.nvm` layout with verifiable local commands.
It keeps other Node versions, user aliases, global packages and npm settings.
Newer or unverifiable installed versions and conflicting external commands stay
unchanged. On success, the installer prints the private recovery directory holding
the old manager entrypoints and any replaced prefix. Retain it until you have
checked your setup; it can contain a full runtime and temporary installation
files. Failed activation restores the original commands and manager entrypoints.
Custom NVM roots need manual reconciliation.

## Existing Go/asdf installations

The Go component asks before migrating the normal `~/.asdf` installation.
For a noninteractive run, set `DOTFILES_MIGRATE_ASDF_GO=1` only for the command
that installs or updates Go. Force reinstall does not authorize migration.

Migration requires one global Go version and a clean Go plugin. Modified plugins,
project or environment version overrides, custom roots and external commands need
manual reconciliation. Newer or unverifiable Go/asdf versions remain unchanged.
Other plugins, language selections, shims, SDK versions and version-local user
tools are retained. On success, the installer prints a private recovery directory.

Failed activation restores the original Go paths, manager file, plugin and shims.
The approved asdf dependency installed before Go preparation can remain available;
the original manager and working legacy Go shim are preserved on failure.

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

The command re-applies the components the probes report as already applied
(leaving version upkeep to the update steps), updates every managed component,
verifies the resolved installed checkouts, runs `agentbot full` (Agentbot's one
update pass once installed), and finishes with both Doctors. It closes on a
timing block naming each of its sections. A component that needs attention
at any step, install included, turns the final line into "needs attention".

Only `dotfiles full-update` (and the bootstrap) reach this end state. The
narrower menu entries do only their part: Dotfiles **Install** installs the
components you pick, Dotfiles **Update** runs the update steps, Agentbot
**Install** installs its selected components, and Agentbot **Update** runs its
update pass; none of them runs the other product or the postflight Doctors.

### Set up Agentbot memory

For a new user's first laptop, create a new vault through Agentbot:

1. Set the user's Git name and email, and make sure Git can authenticate to
   their GitHub account.
2. Create an empty private `agent-memory` repository in that account. Leave
   the README, license, and `.gitignore` options unchecked. Do not clone it
   manually.
3. Enter its URL at the one-command installer's memory prompt and accept the
   default destination. If installation is already complete, open Agentbot's
   **Memory** menu and choose **6. Clone a vault**.
4. For the clone option, enter
   `git@github.com:YOUR_GITHUB_USERNAME/agent-memory.git` as the remote URL and
   `/home/YOUR_WSL_USERNAME/agent-memory` as the destination.
   Replace both usernames with the new user's values. An HTTPS URL also
   works when Git authentication is configured.
5. In the menu, review and confirm the preview. Agentbot creates the memory structure,
   makes the first local commit, and configures this machine. Setup does not
   push to GitHub.
6. Push the first commit and check the vault:

   ```bash
   git -C "$HOME/agent-memory" push -u origin main
   agentbot memory status
   agentbot memory validate
   ```

Choose the Memory menu option that matches the current state:

| Option | When to use it |
|---|---|
| **5. Use an existing checkout** | An initialized Agentbot memory vault is already cloned on this machine. |
| **6. Clone a vault** | A vault or an empty repository exists on GitHub. Agentbot clones it, initializes it if empty, and configures it. |
| **7. Create a new vault** | Starting memory for the first time, with an optional remote repository for sync. |

Only repositories with no Git refs and no working files are initialized by
the clone option. A README, license, `.gitignore`, or existing history requires
an already initialized vault. If you already cloned an empty repository manually,
keep that checkout and choose another unused local destination for **6** or **7**.
Both options refuse a nonempty destination, including a folder containing only
`.git`. Adjust the push command to match the location you choose.

Keep the vault on the Linux filesystem under the user's home, outside other
Git repositories. Use a location such as `~/agent-memory`, rather than `/`,
the home directory itself, or a Windows drive under `/mnt/c`.

Run `agentbot boot` inside each project repository that needs project memory.
With a configured vault, boot discovers the available agent CLIs, lets you
choose clients, previews their memory hooks and MCP files, and configures them
in that same command. Approve native workspace/tool trust in each client when
prompted. All projects use the shared vault; no extra memory setup command is
needed per project. Later `dotfiles fu` runs maintain the integrations already
enrolled in registered workspaces. Rerun boot to add a client or set up a new
workspace; updates do not silently enroll newly detected clients.
See the [Agentbot memory guide](https://github.com/PamuduW/agentbot#memory-vault)
for CLI setup, sync, and proposal review.

### Start optional services

Fresh or migrated Portainer containers are left stopped:

```bash
dpot          # Start (also: dpot start)
dpot stop     # Stop (also: dpotstop)
```

Unknown commands and extra arguments are rejected. Docker start/stop failures
return a non-zero status.

`dpot` shows the setup token before the URL when it appears in Portainer's
current startup logs. Paste it into the first-time setup screen. It waits up
to five seconds for startup logs; if they are unavailable or still incomplete,
it prints `docker logs portainer` as the fallback. It does not save the token.
Portainer needs this one-time token only before an administrator is created;
see the [setup token FAQ](https://docs.portainer.io/faqs/installing/setup-token).

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

## Setup reviews

`reviews/` holds the reports `agentbot setup-review` files: an agent CLI
reviews Dotfiles, Agentbot, the shared library and the skill sources
read-only, and Agentbot commits `reviews/review_<stamp>_<scope>.md` with a line
in `reviews/review_log.md` to the `development` branch. Paths and names in a
report are replaced with placeholders such as `/home/{user}`. After reading a
review, delete its file and mark its log line `reviewed`. The installer never
reads or writes this folder.

## Documentation

- [Technical documentation index](docs/README.md)
- [Architecture](docs/architecture.md)
- [Components](docs/components.md)
- [Installation](docs/installation.md)
- [Updates](docs/updates.md)
- [Git wrapper](docs/git-wrapper.md)
- [Codex and Remote Control](docs/codex-and-remote-control.md)
- [Security](docs/security.md)
- [Development and validation](docs/development.md)
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
