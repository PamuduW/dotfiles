# Dotfiles architecture

## Purpose

This repository installs and maintains a Debian/Ubuntu WSL environment. It is a
Bash application with an interactive TUI, a non-interactive installer, a
command-line maintenance interface, and three GNU Stow packages.

## Entry points

| Entry point | Responsibility |
|---|---|
| `install.sh` | Thin shim to `scripts/install.sh` |
| `scripts/install.sh` | Loads modules and selects the boot menu, initial setup, or update flow |
| `bin/bin/dotfiles` | Public `dotfiles` command dispatcher |
| `scripts/validate.sh` | Complete repository validation gate |

An interactive `./install.sh` or `dotfiles menu` opens the main menu. A
non-interactive installer run defaults to initial setup. Explicit `dotfiles`
subcommands use the command metadata and focused library functions instead of
reimplementing installer logic.

## Module boundaries

```text
scripts/install.sh
├── scripts/lib/load.sh                 shared UI, Git, token, Docker, and utility services
├── scripts/lib/installers/load.sh      component installer implementations
├── scripts/lib/components/load.sh      registry, probes, plans, dispatch, and component menu
└── scripts/menus/*.sh                  interactive adapters

bin/bin/dotfiles
├── scripts/lib/command_metadata.sh     public command contract
├── scripts/lib/update_workflow.sh      update orchestration
├── scripts/lib/full_update.sh          Dotfiles and Agentbot sequencing
└── component/status libraries          local status and Doctor
```

The component registry declares what exists. Probes report local state.
Install dispatch invokes one installer per selected component. Update modules
own remote/version checks and upgrades. TUI modules render these services but
do not own installation policy.

## Stow boundary

Only `bash`, `bin`, and `readline` are Stow packages. They deploy shell files,
the public helper executables, and Readline configuration into `$HOME`.
Windows Terminal configuration under `windows/` is a manual export and is not
stowed.

## Repository boundaries

Dotfiles owns system packages, executable installation, Stow links, WSL
configuration, and the public maintenance command. Agentbot owns agent policy,
skill reconciliation, managed assistant outputs, and optional Graphify/Boost
integration. `dotfiles full-update` delegates Agentbot's internal lifecycle to
`agentbot full`; it does not reproduce Agentbot logic.

The development checkout and installed checkout are separate evidence. Make
source changes under the development repository, validate them there, and do
not describe them as installed until the operational checkout is updated.

## Sources of truth

- Commands: `scripts/lib/command_metadata.sh`
- Components: `scripts/lib/components/registry.sh`
- Apt packages: `packages/packages.txt`
- Installation behavior: `scripts/lib/components/install_dispatch.sh` and
  `scripts/lib/installers/`
- Update behavior: `scripts/lib/update_workflow.sh`, `scripts/lib/updates/`, and
  `scripts/lib/full_update.sh`
- User-visible behavior: tests under `tests/`

