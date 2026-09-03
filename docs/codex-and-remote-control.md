# Codex and Remote Control

## Standalone Codex ownership

Dotfiles owns Codex only when the visible `~/.local/bin/codex` link resolves
into `~/.codex/packages/standalone/` and that standalone command is active on
`PATH`. Status distinguishes absent, standalone, standalone shadowed, and
external states.

Install explicitly with:

```bash
DOTFILES_COMPONENTS=codex_cli ./install.sh --initial
```

The component uses OpenAI's standalone installer and has no Node.js dependency.
It preserves `~/.codex`, including configuration, authentication, sessions,
skills, and local state.

## npm migration

When every external Codex command is a verified NVM installation of
`@openai/codex`, interactive setup inventories all Node trees and requests a
dedicated migration confirmation. Non-interactive migration requires:

```bash
DOTFILES_COMPONENTS=codex_cli \
DOTFILES_MIGRATE_NPM_CODEX=1 \
./install.sh --initial
```

Migration fails closed for unrelated commands, unverifiable package paths,
missing npm, uninstall failures, or remaining commands/package directories.
`dotfiles update` never implicitly authorizes npm removal.

The completed machine-specific migration procedure is retained in the parent
workspace's historical documentation. This repository's shipped behavior and
tests are the current operational contract.

## Codex Remote Control

The `codex-rc` helper accepts exactly one action:

```bash
codex-rc start
codex-rc stop
```

It delegates to the active `codex remote-control` command. Pairing is a separate
operator action. Pairing output is secret and must not be redirected, logged,
saved, committed, pasted into chat, or captured in screenshots.

## Claude Remote Control

`claude-rc start` launches one background server for the current project and
stores private PID, process-start, directory, and log state under
`${XDG_STATE_HOME:-$HOME/.local/state}/claude-rc/`. `claude-rc stop` verifies
both PID and process start time before sending a signal, which prevents PID
reuse from stopping an unrelated process.

Use `claude-rc` separately for each intended project lifecycle; it manages one
recorded server at a time.

