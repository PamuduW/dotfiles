# Dotfiles technical documentation

The root [README](../README.md) is the user-facing quick start. This directory
documents the repository's implementation and operational contracts. Current
scripts and tests are authoritative when prose drifts.

| Document | Scope |
|---|---|
| [Architecture](architecture.md) | Entry points, loaders, modules, Stow packages, and ownership boundaries |
| [Components](components.md) | Registry, dependencies, probes, installation, and package ownership |
| [Installation](installation.md) | Interactive and non-interactive setup, selection, and failure behavior |
| [Updates](updates.md) | Repository gate, tool updates, full update, restart limits, and postflight |
| [Git wrapper](git-wrapper.md) | Nested repositories, submodules, clone, add, and commit guards |
| [Codex and Remote Control](codex-and-remote-control.md) | Standalone Codex ownership and Codex Remote Control; Claude Remote Control auto-starts after setup |
| [Security](security.md) | Download, credential, privilege, and configuration boundaries |
| [Development](development.md) | Test layout, validation gate, formatting, and shared-library synchronization |
| [Troubleshooting](troubleshooting.md) | Stow, Docker, ownership, repository, and command recovery |

Package details are maintained separately in
[`packages/README.md`](../packages/README.md). WSL operational commands are in
[`WSL_COMMANDS.md`](../WSL_COMMANDS.md).

