# Guarded Git wrapper

The Stow-managed `~/bin/git` is an executable wrapper so terminal commands and
editors such as VS Code use the same nested-repository policy. It delegates to
`${DOTFILES_REAL_GIT:-/usr/bin/git}` and preserves ordinary Git behavior outside
the guarded operations below.

Guards apply to Git aliases that expand to `commit`, `add`, `clone`, or
`sub add`. The wrapper looks up `alias.<name>` through system Git (including
`-c` / `-C` prefixes), splices a non-shell expansion in place of the alias
name, and then runs the same checks as the expanded command. Git shell aliases
(`!…`) and alias loops are passed through unchanged. POSIX shell aliases such
as `alias gcm='git commit'` are outside this wrapper.

## Clone

`git clone` adds `--recurse-submodules` unless the command already contains an
explicit recursion or no-recursion option.

## Declaring a submodule

Use this repository-specific convenience command for an existing nested Git
repository:

```bash
git sub add path/to/repository
```

The wrapper verifies the folder is a Git worktree, reads its `origin`, and runs
`git submodule add <origin> <folder>`. This is the only implicit conversion from
an existing nested repository to a declared submodule.

## Add guard

Ordinary `git add`, including `git add --all`, does not turn a newly encountered
nested repository into an undeclared gitlink. If Git stages such a gitlink, the
wrapper removes only that newly staged entry and leaves the nested repository
untracked. Updated declared submodules continue to stage normally.

## Commit guard

Before committing, the wrapper:

1. Continues without fetch/pull when the repository has no remotes.
2. Resolves the current upstream when at least one remote is configured.
3. Fetches it and stops if fetch fails.
4. Fast-forwards with `git pull --ff-only` when behind.
5. Stops if local state prevents the fast-forward.
6. Displays `git status`.
7. Unstages newly added gitlinks that are absent from `.gitmodules`, leaving
   those nested repositories untracked, then continues the commit. Gitlinks
   already recorded in `HEAD` without `.gitmodules` are left as they are.

A repository with remotes but no upstream warns and continues without
fetch/pull. Local-only tracking (no remotes) is not treated as an upstream
sync. Nested repositories that were never declared as submodules do not block
the commit. The wrapper does not merge, rebase, force-push, or create
submodules during commit.

## Global Git defaults

The Git configuration component sets recursive checkout/fetch/status behavior
and checked submodule pushes. Windows GCM is used for HTTPS credentials when
available; its absence does not erase an existing helper or block the submodule
defaults.

## Validation

Run `bash tests/test_git_wrapper.sh`. The suite invokes the wrapper while using
`/usr/bin/git` as the deterministic system Git implementation.

