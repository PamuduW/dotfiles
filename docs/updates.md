# Update lifecycle

## Commands

```bash
dotfiles status
dotfiles update --dry-run
dotfiles update
dotfiles full-update
dotfiles doctor
```

`status` and `doctor` are local and read-only. `update --dry-run` prints the
captured update report and stops before downstream changes. `update` performs
the repository gate and, after confirmation, applies every managed update.
`--all` is accepted for compatibility but selects nothing additional.

## Repository gate

Install and update use the same repository service. It validates the checkout
and upstream, records dirty paths, fetches `origin`, and classifies ahead,
behind, and diverged state.

- A clean strictly-behind branch may be pulled with `--ff-only` after approval.
- A successful pull stops old-process work and requests or performs a bounded
  restart from the updated checkout.
- Dirty, ahead, and diverged replacement requires approval and recoverable Git
  preservation.
- Replacement stashes tracked and untracked changes and creates a recovery
  branch for local commits before resetting.
- Ignored files are not cleaned.
- An unexpected origin or non-origin upstream fails closed.

## Managed updates

The update report separates installed, available, and action. Remote checks run
through bounded helpers so one stalled tool does not freeze the full report.
Managed update modules cover apt, Graphify, Boost, Cursor, Codex, Claude,
lazygit, lazydocker, Node.js, npm, Go, Monaspace fonts, and repository state.

Ownership checks prevent Dotfiles from replacing tools it cannot prove it
owns. Graphify updates only when `uv tool list` attributes it to `graphifyy`.
Boost updates only when Dotfiles' ownership marker matches the installed
binary. That marker stays true because Boost's own background self-updater is
off: Agentbot pins both `[update] auto_update` and the `boost-auto-update`
feature flag to false, so nothing replaces the binary behind the marker. Codex updates only an active standalone installation. External or
shadowed commands are preserved and reported.

## Timing

Install, update, and full update each close on a timing block: how long the run
took, and where the time went. The install and the update name their slowest
six; there is no point ranking a list short enough to read whole.

```text
  Update took 1m 31s. Slowest steps:
     1m 09s  apt packages
     0m 06s  npm
```

`TIMING_SUMMARY_LIMIT=0` lists every row instead and drops the word "Slowest",
which is what the full update uses: five sections named "the slowest five" says
nothing about any of them.

## Full update

`dotfiles full-update` performs one unattended maintenance sequence:

1. Run the repository gate on the Dotfiles checkout, restarting once if it
   moves forward.
2. Reinstall the components the probes report as already applied.
3. Run the Dotfiles update workflow with approved application prompts.
4. Print the resolved Dotfiles and Agentbot launchers/checkouts, and refuse an
   unexpected Agentbot checkout.
5. Delegate Agentbot's install/update sequence to `agentbot full`.
6. Run Dotfiles and Agentbot Doctor as postflight checks.
7. Report the wall clock of each section.

Agentbot warnings produce a warning outcome; a Doctor error fails postflight.

The sections are the five the operator watched go past — Dotfiles install,
Dotfiles update, Agentbot install, Agentbot update, Postflight. Agentbot's two
halves are one command from here, so it reports them through
`AGENTBOT_TIMING_FILE`: one `<stage> <seconds>` line per stage. An Agentbot that
does not know how to — an older checkout, mid-upgrade — writes nothing and the
whole delegation is recorded as one section.

Each half also reports its own figure on screen, and the run uses that figure
rather than its own clock where one is published. Wrapping the Dotfiles install
from outside starts the clock before the `sudo` prompt, so the section
disagreed with the "Install took" line a few rows above it by however long the
operator spent typing a password.

`REPO_UPDATE_CALLER_RESTARTS=1` is set for the whole sequence: this run restarts
itself when a checkout moves, so neither repository gate should tell the
operator to run setup again.

The component install in step 1 derives its selection from the probes, never
from a stored answer, so a full update never silently adds a component the
operator did not choose. Components whose installer needs an answer only the
operator can give — Git identity — are excluded.

`dotfiles full-update --force` reinstalls components that are already present,
the unattended equivalent of the execution plan's `x`. From the menu, Full
Update asks with the same keys the plan uses:

| Key | Meaning |
|---|---|
| `c` | Run the full update |
| `x` | Run it, reinstalling components that are already present |
| `q` | Back to the menu |

## Logs

Mutating commands retain timestamped logs under `log/`. Filenames stay
lexicographically newest-first so `dotfiles logs --last` and retention agree.
Each run uses an exclusive file so overlapping commands do not share a capture.

```bash
dotfiles logs
dotfiles logs --last
```

`DOTFILES_LOG_RETAIN` controls retention and defaults to 20.

The menu's Logs screen reports the count and offers the actions a menu can
usefully take on a folder: open it in Explorer or VS Code, or delete the logs.
Deleting keeps back the capture the current run is still writing.

