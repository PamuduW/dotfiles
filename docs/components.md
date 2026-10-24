# Component lifecycle

## Registry

`scripts/lib/components/registry.sh` defines the 33 component keys,
labels, plan details, descriptions, package tags, dependencies, and installation
order. Keep those records synchronized with probes, install dispatch, update
logic, Command lib, Package lib, and user documentation.

| Group | Components |
|---|---|
| Identity and Git | `git_identity`, `git_credential` |
| System and language runtimes | `system_packages`, `python`, `powershell`, `go`, `nodejs`, `direnv` |
| Containers | `docker`, `portainer`, `lazydocker` |
| Development tools | `graphify_cli`, `boost_cli`, `lazygit`, `kubeconform`, `tflint`, `zizmor`, `trivy`, `infracost`, `chrome_headless` |
| Writing and documents | `vale`, `yt_dlp`, `markdownlint_cli2`, `cspell`, `mermaid_cli` |
| Agent CLIs | `cursor_cli`, `codex_cli`, `claude_cli`, `antigravity_cli` |
| Desktop and shell | `ubuntu_sans_mono_fonts`, `obsidian`, `dotfiles`, `wsl_conf` |

Git identity is disabled by default. Other components
start selected. Dependencies are enforced by the registry; Portainer and
lazydocker depend on Docker, and Stow deployment depends on system packages.

Kubeconform, TFLint, zizmor, Vale, yt-dlp, Trivy and Infracost share one installer
(`scripts/lib/installers/release_cli.sh`) and one row table
(`RELEASE_CLI_TOOLS` in `scripts/lib/managed_tool_state.sh`). Each installs the
latest GitHub release to `~/.local/bin` after checking the SHA-256 digest GitHub
publishes for the asset, extracts only the binary, and writes an ownership
stamp to `~/.local/share/dotfiles/<key>.version`, as Boost does. A copy
Dotfiles did not install is reported as external and never replaced.

Dotfiles owns only the executables. TFLint provider plugins and `.tflint.hcl`,
zizmor configuration and any GitHub token for its online audits, and
Kubernetes schema caches, Vale styles and `.vale.ini`, and yt-dlp
configuration belong to the repository that uses them. yt-dlp's release asset
is the binary itself, so nothing is extracted.

Trivy runs with `TRIVY_DISABLE_TELEMETRY=true` and `TRIVY_SKIP_VERSION_CHECK=true`
from the stowed `.bashrc`; its vulnerability database cache is about 1.6 GB in
`~/.cache/trivy`, refreshed by a 127 MiB download when older than a day. No
plugins, server mode or image scanning are set up. Infracost needs a login once
per machine, by the operator (`infracost auth login`); `infracost setup`, which
installs agent skills and IDE and CI integration, is never run. `.bashrc` sets
`INFRACOST_CLI_PLUGIN_AUTO_UPDATE=false`, so its plugins (about 446 MB, fetched
on first use) change only when refreshed, and
`INFRACOST_CLI_CLAUDE_PATH=/nonexistent/claude`: otherwise every Infracost run,
even `--version`, starts `claude plugin list` to look for Infracost's own agent
plugin. Its CLI update check on each run has no setting. zizmor runs
offline; Kubeconform fetches schemas on demand unless pointed at local ones.
Kubeconform checks schemas only and does not replace `kubectl
--dry-run=server`.

`chrome_headless` installs the latest Stable build of Chrome for Testing's
headless shell (`scripts/lib/installers/chrome_headless.sh`), the browser the
Archify skill drives for its browser gate. The whole build unpacks to
`~/.local/share/chrome-headless-shell`, `~/.local/bin/chrome-headless-shell`
links to it, and the stamp is `~/.local/share/dotfiles/chrome_headless.version`;
ownership needs both the link into that directory and the stamp. The stowed
`.bashrc` exports `ARCHIFY_CHROME` when the link exists, and
`ARCHIFY_UPDATE_CHECK_DISABLED=1` so Archify does not check GitHub on every
render. Agentbot installs the skill itself.

markdownlint-cli2, CSpell and Mermaid CLI share the npm installer
(`scripts/lib/installers/npm_cli.sh`) and its row table (`NPM_CLI_TOOLS` in
`scripts/lib/managed_tool_state.sh`). Each is the latest npm release,
installed with `--ignore-scripts` into its own prefix under
`~/.local/share/dotfiles-npm/<key>`, so a Node version change does not remove
it. `~/.local/bin/<command>` links to a wrapper in that prefix, and the stamp
is `~/.local/share/dotfiles/<key>.version`. They depend on `nodejs`. Mermaid
CLI's wrapper sets `PUPPETEER_EXECUTABLE_PATH` to the Chrome headless shell
unless the caller set it, so Puppeteer's own Chrome is never downloaded; its
npm dependencies alone are about 460 MB. Rules, dictionaries and Mermaid
configuration belong to each repository.

## direnv

The direnv installer checks the latest GitHub release before downloading its
binary. A current or newer copy at `~/.local/bin/direnv` is retained unless
forced reinstall was requested. The `~/bin/direnv` shortcut is maintained on
both the skip and install paths.

Fresh installs and upgrades use direnv's published Linux binary, verify its
GitHub SHA-256 digest and exact version, then replace the installed executable
with a rename on the same filesystem. Download, checksum and version failures
preserve the working copy and report failure. Temporary files are removed.
Downloads use a 10-second connection timeout, a 180-second limit per attempt,
and up to two retries, including receive errors. The retry window is 180
seconds; an attempt started within that window can finish after it. Release
metadata must be available and verifiable; a failed check is not reported as
already current. See [direnv's installation guide](https://direnv.net/docs/installation.html).

## State flow

```text
registry metadata
  -> component selection
  -> execution plan
  -> install dispatch
  -> component probe
  -> install summary / status
```

Probes must report observable local state. They must not fetch remote metadata
or mutate the machine. `dotfiles status` shows every component and, when any
needs attention, the ones that do and the command that fixes each. `dotfiles
doctor` prints those same two blocks without the full table and exits nonzero
when anything needs attention, which is what full update's postflight and any
scripted check read.

### Interrogation and classification

A probe is two things, and they are kept apart on purpose. *Interrogation* asks
the machine and needs one; *classification* reads the answer and is pure. Three
of the five component defects found on clean machines were misreadings of an
interrogation that was itself correct, so the reading is the half that must be
testable without the state that produces it.

A probe therefore ends by calling `comp_classify <name> <argument>...` rather
than deciding anything itself. The readings live in
`python/probe_classify.py` in dotfiles-shared, and one interpreter answers every
probe in a run: the probes run in parallel children and emit requests, and the
collector resolves all of them in a single call to the Python service described
in `docs/architecture.md`. Per-probe spawn would cost roughly a third of
`dotfiles status`.

Six probes interrogate in Python as well: the ones that read the filesystem and
Git configuration (`python/probes.py` in dotfiles-shared), where a temporary
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
cannot hide a failed installer. Generic version probes report nonzero command
exits as needing attention, including a crashed executable. A command that
succeeds with empty version output keeps the installed-label fallback.

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
checks and upgrades the tools it explicitly owns. `full-update` first selects
installed or configured components from local probes and reruns their
installers, then runs the update path. Components covered by a dedicated
update step skip the initial reinstall unless forced or their probe is
inconclusive. Components requiring operator input, such as Git identity, are
excluded. Missing components are not silently enrolled.

## Portainer

Portainer follows `portainer/portainer-ce:lts` unless `PORTAINER_IMAGE` is
deliberately set. The installer pulls the requested image and compares image
IDs. It creates fresh containers stopped. It replaces an outdated container
only when its data volume, Docker socket, ports, and restart policy match the
Dotfiles-managed layout. The replacement reuses `portainer_data` and remains
stopped. A custom layout is preserved and reported for manual review.

