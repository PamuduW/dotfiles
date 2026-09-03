# Component lifecycle

## Registry

`scripts/lib/components/registry.sh` defines the 21 stable component keys,
labels, plan details, descriptions, package tags, dependencies, and installation
order. Keep those records synchronized with probes, install dispatch, update
logic, Command Lib, Package Lib, and user documentation.

| Group | Components |
|---|---|
| Identity and Git | `git_identity`, `git_credential` |
| System and language runtimes | `system_packages`, `python`, `powershell`, `go`, `nodejs`, `direnv` |
| Containers | `docker`, `portainer`, `lazydocker` |
| Development tools | `graphify_cli`, `boost_cli`, `lazygit` |
| Agent CLIs | `cursor_cli`, `codex_cli`, `claude_cli` |
| Desktop and shell | `monaspace_fonts`, `ssh_key`, `dotfiles`, `wsl_conf` |

Git identity and SSH-key generation are disabled by default. Other components
start selected. Dependencies are enforced by the registry; Portainer and
lazydocker depend on Docker, and Stow deployment depends on system packages.

## State flow

```text
registry metadata
  -> component selection
  -> execution plan
  -> install dispatch
  -> component probe
  -> install summary / status / Doctor
```

Probes must report observable local state. They must not fetch remote metadata
or mutate the machine. `dotfiles status` shows every component; `dotfiles
doctor` shows only components needing attention and exits nonzero when any are
missing or unhealthy.

An installer success is not enough for the summary. The orchestration records
the installer result and checks the component probe so an existing artifact
cannot hide a failed installer.

## Package ownership

`packages/packages.txt` is the canonical apt catalog. Tag groups separate core,
CLI, system, and Python packages. `packages/README.md` explains package policy.
Do not add project-specific libraries to the default global catalog merely
because one repository needs them.

## Selected component automation

Set `DOTFILES_COMPONENTS` to comma-separated stable keys for non-interactive
selection:

```bash
DOTFILES_COMPONENTS=docker,portainer,lazygit ./install.sh --initial
```

The installer applies dependency closure. Unknown keys are warned about and
are not silently converted into components.

## Install versus update

Installers establish or reconcile component configuration. The update workflow
checks and upgrades the tools it explicitly owns. Current `full-update` runs
the update path; it does not yet rerun every previously selected installer.
Adding that behavior is roadmap work, not a current guarantee.

## Portainer

Portainer follows `portainer/portainer-ce:lts` unless `PORTAINER_IMAGE` is
deliberately set. The installer pulls the requested image and compares image
IDs. It creates fresh containers stopped. It replaces an outdated container
only when its data volume, Docker socket, ports, and restart policy match the
Dotfiles-managed layout. The replacement reuses `portainer_data` and remains
stopped. A custom layout is preserved and reported for manual review.

