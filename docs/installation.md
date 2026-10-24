# Installation

## One-command setup

```bash
curl -fsSL https://raw.githubusercontent.com/PamuduW/dotfiles/main/bootstrap.sh | bash
```

After cloning the shared library and before either installer starts, bootstrap
checks for a valid `GITHUB_TOKEN` in the environment or in the existing private
token store. It reuses either without prompting. If neither is available and a
terminal is attached, it opens the same GitHub token screen used by Dotfiles.
Choose **Save or replace**, enter a read-only token, confirm, then choose
**Back** to continue. The screen reads the terminal even when the script arrives
through a pipe.

The screen validates the token and saves it to
`${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/github.env` with mode `600` in a
private directory. The installers read that store for their first GitHub API
download, so the new token is available in the same run and after a restart.
It is not added to repository files or passed in curl arguments.

Token setup is optional. Choosing **Back** without saving, or running without
a terminal and without a configured token, continues with GitHub's
unauthenticated rate limit. A GitLab token does not raise GitHub's limits.

### GitHub SSH for the memory vault

When the memory URL uses `git@github.com:...` or `ssh://git@github.com/...`,
bootstrap checks SSH authentication before starting the non-interactive clone.
Local folders and HTTPS URLs do not run this SSH setup.

On the first connection, bootstrap shows GitHub's published Ed25519 host
fingerprint and asks before adding the matching public host key to
`~/.ssh/known_hosts`. It uses the key published in
[GitHub's fingerprint documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints),
rather than trusting a key returned by an unauthenticated network scan. Existing
host entries are preserved. A host verification or network failure stops the
memory step without creating an identity or weakening host verification.

If GitHub already accepts this machine's SSH identity, setup continues. Otherwise,
bootstrap offers to reuse a local SSH key, create a new Ed25519 key, or skip
memory setup. It checks OpenSSH's configured `IdentityFile` paths as well as
standard key filenames and local public-key companions. New keys use
`~/.ssh/id_ed25519` when available, or an unused
`id_ed25519_github_N` filename. Existing keys are never overwritten. OpenSSH
reads key passphrases directly from the terminal, including during a piped install.

Bootstrap reuses the current SSH agent, or starts one if needed, then runs
`ssh-add` for the selected key. It prints only the public key and the GitHub
settings URL. Add that key to the intended account as an **Authentication Key**,
then press Enter to retry. The installer does not add keys to GitHub on your
behalf. If authentication remains unavailable or you skip this step, no memory
clone runs; the rest of setup and its health check continue.
The selected identity is passed explicitly to both the authentication check and
the memory clone, including when the existing SSH configuration uses
`IdentitiesOnly yes`. Agentbot records it in the cloned vault's local
`core.sshCommand` for later syncs and pushes, using the current `SSH_AUTH_SOCK`
at runtime. This does not rewrite the user's global SSH configuration or pin
a temporary agent socket path.

An agent started by bootstrap is available to its child processes and the login
shell it opens. It cannot change the environment of the parent shell. In another
terminal, start an agent if needed and load the chosen key:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Use the filename shown during setup if you selected a different key. The account
must also have access to the private memory repository; SSH authentication alone
does not grant repository access.

## Interactive setup

Clone the repository into the operational location and run its supported entry
point:

```bash
git clone <repo-url> "$HOME/dotfiles"
cd "$HOME/dotfiles"
./install.sh
```

The boot menu offers status, installation, update, full update, logs, restow,
token configuration, reference libraries, and quit. Install Dotfiles runs the
repository gate before opening the component menu. Use arrows to navigate,
Space to toggle, and Enter to continue. The installer displays an execution
plan before applying the selection.

Git identity is prompted only when selected. Component dependencies remain
enforced while toggling.

Before installation or APT updates, Dotfiles checks the active `sudo`
implementation. If it detects `sudo-rs`, it stops that operation: this
implementation can leave APT child processes stopped indefinitely when run
through the installer. The check does not change system configuration.
If bootstrap needs to install Git, it performs the same check before that
initial APT operation, before any repositories have been cloned.

On Ubuntu, check whether traditional `sudo` is available:

```bash
sudo update-alternatives --list sudo
```

If `/usr/bin/sudo.ws` is listed, select it manually, verify the active
implementation, then rerun your Dotfiles command:

```bash
sudo update-alternatives --set sudo /usr/bin/sudo.ws
sudo --version
```

The version output should identify `Sudo version`, rather than `sudo-rs`.
If `sudo.ws` is not listed, install or configure traditional `sudo` using
your distribution's instructions before retrying.

A failed apt index refresh does not end the run. The components whose
installers need the index are reported as not run, everything else is applied,
and the summary and log location still reach the operator.

## Non-interactive setup

Without a TTY on standard input, `./install.sh` defaults to initial setup and
does not open the menu. Limit the selection with stable component keys:

```bash
DOTFILES_COMPONENTS=system_packages,dotfiles ./install.sh --install
```

Add `--force` to reinstall components that are already present. It is a flag
rather than an environment variable on purpose: an exported
`DOTFILES_FORCE_REINSTALL` would force every run with nothing on the command
line saying so.

```bash
./install.sh --install --force
```

Existing global Git identity values are used when identity is enabled without
an interactive prompt. Verified npm-to-standalone Codex migration requires the
separate `DOTFILES_MIGRATE_NPM_CODEX=1` authorization; component selection alone
does not authorize package removal.

## Installation order

The installer refreshes apt indexes once when selected components require apt.
It then follows the registry's deterministic order. Each component is attempted
and recorded independently, and the final summary distinguishes completed,
skipped, and failed work. The run closes on how long it took and which six
components were slowest, and offers `exec bash -l` only when the Stow component
applied — nothing else changes what a login shell loads.

`sudo` is primed once at the start, so its credential cache covers every later
call site and the operator is asked for a password exactly once. That prompt
goes through `SUDO_ASKPASS`, which masks it; the install's own clock starts
after it, so the reported duration is the run's rather than the operator's
typing speed.

Important boundaries:

- Docker daemon configuration is merged and conflicts fail closed.
- Portainer preserves custom layouts and the named data volume.
- Stow backs up conflicting managed home files before linking.
- Vendor scripts are downloaded and checked before execution.
- GitHub-release installers verify the selected archive checksum.
- Dotfiles installs Graphify and Boost binaries only; Agentbot owns their agent
  integration. Graphify is installed without its optional `watchdog`
  dependency, so `graphify watch` stops with "watchdog not installed"; keep a
  repository's code graph current with `graphify hook install` (git hooks that
  rebuild it after each commit, no LLM needed) or `graphify update .` instead.

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
~/bin/{dotfiles,git,ex,clip,codex-rc}
```

## After installation

Open a new terminal or source `~/.bashrc`. Changes to `/etc/wsl.conf` require
`wsl --shutdown` from Windows before a new WSL session. Reload VS Code after
Stow so its Git extension can resolve the guarded `~/bin/git` executable.

