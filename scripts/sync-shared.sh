#!/usr/bin/env bash
set -euo pipefail

# Keep scripts/lib/shared/ byte-identical between this repository and its
# sibling.
#
# Both repositories carry a complete copy, so each one runs standalone and
# neither depends on the other at runtime. This script (and the test that calls
# it with --check) is the only thing that looks at the sibling, and it is a
# no-op when the sibling is not checked out.
#
#   scripts/sync-shared.sh           copy canonical -> sibling
#   scripts/sync-shared.sh --check   fail if they differ, change nothing
#
# The canonical copy is the one in the Dotfiles repository. Edit that, then run
# this without --check.

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="$(basename "$REPO_DIR")"
SHARED_RELS=('scripts/lib/shared' 'tests/lib/shared')
CANONICAL_REPO_NAME='dotfiles'
SIBLING_REPO_NAME='agent_bootstrap'

mode="${1:-sync}"
case "$mode" in
sync | --check) ;;
*)
	printf 'Usage: %s [--check]\n' "$(basename "$0")" >&2
	exit 2
	;;
esac

if [[ "$REPO_NAME" == "$CANONICAL_REPO_NAME" ]]; then
	canonical_root="$REPO_DIR"
	sibling_root="$(dirname -- "$REPO_DIR")/$SIBLING_REPO_NAME"
else
	canonical_root="$(dirname -- "$REPO_DIR")/$CANONICAL_REPO_NAME"
	sibling_root="$REPO_DIR"
fi

if [[ ! -d "$canonical_root" || ! -d "$sibling_root" ]]; then
	printf 'Sibling repository not checked out; nothing to sync.\n'
	exit 0
fi

diverged=0
for rel in "${SHARED_RELS[@]}"; do
	canonical_dir="$canonical_root/$rel"
	sibling_dir="$sibling_root/$rel"
	[[ -d "$canonical_dir" ]] || continue

	if [[ "$mode" == --check ]]; then
		if [[ ! -d "$sibling_dir" ]]; then
			printf '\nMissing shared tree in sibling: %s\n' "$rel" >&2
			diverged=1
			continue
		fi
		diff -ru "$canonical_dir" "$sibling_dir" || diverged=1
		continue
	fi

	# Sync is one-way and confined to the shared tree, so it can never touch
	# anything else in the sibling repository.
	mkdir -p -- "$sibling_dir"
	rsync --archive --delete "$canonical_dir/" "$sibling_dir/" 2>/dev/null ||
		{
			rm -rf -- "${sibling_dir:?}/"
			mkdir -p -- "$sibling_dir"
			cp -a -- "$canonical_dir/." "$sibling_dir/"
		}
	printf 'Synced %s\n' "$rel"
done

if [[ "$mode" == --check ]]; then
	if ((diverged)); then
		printf '\nShared copies have diverged.\n' >&2
		printf 'Edit the copy in %s/, then run scripts/sync-shared.sh\n' "$CANONICAL_REPO_NAME" >&2
		exit 1
	fi
	printf 'Shared copies are identical.\n'
fi
