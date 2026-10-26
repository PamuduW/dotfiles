# Codex and Remote Control

## Standalone Codex ownership

Dotfiles recognizes its catalog receipt and visible `~/.local/bin/codex`
link. It also recognizes the earlier standalone layout under
`~/.codex/packages/standalone/` for migration. Status distinguishes absent,
standalone, standalone shadowed, and external commands.

Install explicitly with:

```bash
DOTFILES_COMPONENTS=codex_cli ./install.sh --install
```

The component installs the complete bundle selected by the approved software
catalog, including its helpers and resources. It verifies the archive digest,
package identity and exact version before publishing the command. It has no
Node.js dependency. Normal installs and updates do not run the floating vendor
installer or select an upstream latest release.

Catalog-managed releases live under `~/.local/share/dotfiles-catalog/codex_cli/`.
The installer preserves `~/.codex/config.toml`, authentication, sessions and
skills. Before executing Codex it disables the daemon updater through
`app-server-daemon/settings.json` under `CODEX_HOME` (default `~/.codex`). It
preserves other settings and refuses malformed or unsafe settings files.

Updates select the approved catalog version. Missing approval, invalid bundle
bytes or an unverifiable newer installation blocks replacement. The catalog
seed remains unqualified until the required platform tests pass; these local
changes do not provide an approved release catalog yet.

## npm migration

When every external Codex command is a verified NVM installation of
`@openai/codex`, interactive setup inventories all Node trees and requests a
dedicated migration confirmation. Non-interactive migration requires:

```bash
DOTFILES_COMPONENTS=codex_cli \
DOTFILES_MIGRATE_NPM_CODEX=1 \
./install.sh --install
```

After consent, migration verifies the complete approved bundle before moving
any npm files. It moves each verified NVM command and `@openai/codex` package
into a temporary directory under the NVM root. It keeps them there until
standalone publication succeeds, then removes the backups. It does not run npm
removal scripts or remove other global packages.

An unverified command or package, a failed move, or failed publication stops
migration. Failure restores the original npm commands and packages. If rollback
itself fails, the error identifies the retained recovery directory.
`dotfiles update` never implicitly authorizes npm removal.

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

Claude Remote Control starts automatically after Claude CLI setup. Dotfiles
does not provide a `claude-rc` lifecycle command.

During setup or restow, Dotfiles removes an obsolete managed `~/bin/claude-rc`
symlink when that link points at this checkout. Regular files, directories, and
symlinks owned elsewhere are left unchanged. `codex-rc` is unaffected.

