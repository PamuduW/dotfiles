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
binary. Codex updates only an active standalone installation. External or
shadowed commands are preserved and reported.

## Full update

`dotfiles full-update` performs one unattended maintenance sequence:

1. Run the Dotfiles update workflow with approved application prompts.
2. Restart once if the Dotfiles repository changes.
3. Print the resolved Dotfiles and Agentbot launchers/checkouts.
4. Refuse an unexpected Agentbot checkout.
5. Delegate Agentbot's install/update sequence to `agentbot full`.
6. Run Dotfiles and Agentbot Doctor as postflight checks.

Agentbot warnings produce a warning outcome; a Doctor error fails postflight.
Current full update does not reinstall all previously selected Dotfiles
components. That expansion is tracked in the workspace roadmap.

## Logs

Mutating commands retain timestamped logs under `log/`. Use:

```bash
dotfiles logs
dotfiles logs --last
```

`DOTFILES_LOG_RETAIN` controls retention and defaults to 20.

