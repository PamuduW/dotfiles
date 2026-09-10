# Component lifecycle

## Registry

`scripts/lib/components/registry.sh` defines the 20 stable component keys,
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
| Desktop and shell | `monaspace_fonts`, `dotfiles`, `wsl_conf` |

Git identity is disabled by default. Other components
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

### Interrogation and classification

A probe is two things, and they are kept apart on purpose. *Interrogation* asks
the machine and needs one; *classification* reads the answer and is pure. Three
of the five component defects found on clean machines were misreadings of an
interrogation that was itself correct, so the reading is the half that must be
testable without the state that produces it.

A probe therefore ends by calling `comp_classify <name> <argument>...` rather
than deciding anything itself. The readings live in
`scripts/lib/shared/python/probe_classify.py`, and one interpreter answers every
probe in a run: the probes run in parallel children and emit requests, and the
collector resolves all of them in a single call to the Python service described
in `docs/architecture.md`. Per-probe spawn would cost roughly a third of
`dotfiles status`.

Six probes interrogate in Python as well: the ones that read the filesystem and
Git configuration (`scripts/lib/shared/python/probes.py`), where a temporary
HOME reproduces every state exactly. They are answered by one service call that
is sent before the parallel Bash probes start and read after they finish, so
they cost no wall-clock. Probes that run a version command or query a package
manager stay in Bash, which already runs them in parallel and has no better
oracle than "it agreed on this machine today".

That shortcut applies only while `comp_probe` is the function the registry
defined. It is the documented seam, and a suite that replaces it to drive a
report without touching the machine expects every probe to go through its
version.

`scripts/lib/components/probes.sh` keeps a Bash `_comp_classify_<name>` for
every reading, and a Bash probe for every component. That is not leftover: first setup draws this table before it has
installed a runtime, so the fallback is permanent, and
`tests/test_probe_classify_parity.sh` holds the two sides in agreement. Adding
or changing a reading means changing both and adding its states there.

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
DOTFILES_COMPONENTS=docker,portainer,lazygit ./install.sh --install
```

A selection is closed over its dependencies, the same way the menu closes it:
naming `portainer` enables `docker` too, and each addition is reported on
standard error. Listing a dependency yourself is fine and changes nothing.
Unknown keys are warned about and are not silently converted into components.

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

