# Guarded Git wrapper

The Stow-managed `~/bin/git` is an executable wrapper so terminal commands and
editors such as VS Code use the same nested-repository policy. It delegates to
`${DOTFILES_REAL_GIT:-/usr/bin/git}` and preserves ordinary Git behavior outside
the guarded operations below.

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

1. Resolves the current upstream.
2. Fetches it and stops if fetch fails.
3. Fast-forwards with `git pull --ff-only` when behind.
4. Stops if local state prevents the fast-forward.
5. Displays `git status`.
6. Rejects staged gitlinks absent from `.gitmodules`.

A branch without an upstream warns and continues without fetch/pull. The
wrapper does not merge, rebase, force-push, or create submodules during commit.

## Global Git defaults

The Git configuration component sets recursive checkout/fetch/status behavior
and checked submodule pushes. Windows GCM is used for HTTPS credentials when
available; its absence does not erase an existing helper or block the submodule
defaults.

## Validation

Run `bash tests/test_git_wrapper.sh`. The suite invokes the wrapper while using
`/usr/bin/git` as the deterministic system Git implementation.

