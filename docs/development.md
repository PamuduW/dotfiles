# Development and validation

## Work in the source checkout

Make changes in the development repository, not the installed `$HOME/dotfiles`
checkout. Read `AGENTS.md`, inspect Git status, and preserve unrelated staged,
modified, and untracked files.

## Complete gate

Run:

```bash
./scripts/validate.sh
```

The gate checks Bash syntax, production ShellCheck, test-harness warnings,
shfmt, JSON syntax, shared-library drift, diff whitespace, and every discovered
shell test.

To apply repository formatting and then run the gate:

```bash
./scripts/validate.sh --format
```

Formatting is mechanical; always inspect the resulting diff.

## Focused tests

Each `tests/test_*.sh` file is independently runnable. Examples:

```bash
bash tests/test_installers.sh
bash tests/test_git_wrapper.sh
bash tests/test_full_update.sh
```

`tests/run.sh` discovers the full test set. Test harnesses isolate HOME, XDG
state, logs, external commands, and network boundaries. Unconfigured network
fakes fail closed.

## Shared libraries

Dotfiles is the canonical owner of shared report, Git-repository, token, and TUI
copies used by Agentbot. Run:

```bash
./scripts/sync-shared.sh --check
```

Use `./scripts/sync-shared.sh` only when an intentional shared-library change
must update the sibling checkout. Review both repositories afterward.

## Documentation changes

Verify commands and component claims against `scripts/lib/command_metadata.sh`,
`scripts/lib/components/registry.sh`, installers, probes, update modules, and
tests. The README is an entry point; detailed behavior belongs in `docs/`.

Before handoff, run `git diff --check`, inspect `git diff`, and report the full
gate result plus any environmental or pre-existing failure.

