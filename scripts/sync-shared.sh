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

# Identify a checkout by what it contains, never by its directory name. The
# name-based version silently mistook any checkout not called "dotfiles" for
# the sibling: --check then passed without comparing anything, and sync could
# delete a repository's own shared tree and refill it from an unrelated
# directory that merely had the right name.
repo_role() {
	local dir="$1"
	[[ -d "$dir/scripts/lib/shared" ]] || return 1
	if [[ -f "$dir/scripts/install.sh" && -f "$dir/bin/bin/dotfiles" ]]; then
		printf 'canonical\n'
		return 0
	fi
	if [[ -f "$dir/src/cli.py" && -f "$dir/agentos.yaml" ]]; then
		printf 'sibling\n'
		return 0
	fi
	return 1
}

if ! own_role="$(repo_role "$REPO_DIR")"; then
	printf 'Error: %s is neither the %s nor the %s checkout.\n' \
		"$REPO_DIR" "$CANONICAL_REPO_NAME" "$SIBLING_REPO_NAME" >&2
	exit 1
fi

if [[ "$own_role" == canonical ]]; then
	wanted_role='sibling'
	wanted_name="$SIBLING_REPO_NAME"
else
	wanted_role='canonical'
	wanted_name="$CANONICAL_REPO_NAME"
fi

parent_dir="$(dirname -- "$REPO_DIR")"
counterparts=()
for candidate in "$parent_dir"/*/; do
	candidate="${candidate%/}"
	[[ -d "$candidate" && "$candidate" != "$REPO_DIR" ]] || continue
	[[ "$(repo_role "$candidate" || true)" == "$wanted_role" ]] || continue
	counterparts+=("$candidate")
done

if ((${#counterparts[@]} > 1)); then
	printf 'Error: more than one %s checkout beside %s: %s\n' \
		"$wanted_name" "$REPO_DIR" "${counterparts[*]}" >&2
	exit 1
fi

if ((${#counterparts[@]} == 0)); then
	# A directory with the expected name that fails identification is a
	# different problem from an absent sibling, and must not pass as one.
	if [[ -d "$parent_dir/$wanted_name" ]]; then
		printf 'Error: %s exists but is not a %s checkout.\n' \
			"$parent_dir/$wanted_name" "$wanted_name" >&2
		exit 1
	fi
	printf 'Sibling repository not checked out; nothing to sync.\n'
	exit 0
fi

if [[ "$own_role" == canonical ]]; then
	canonical_root="$REPO_DIR"
	sibling_root="${counterparts[0]}"
else
	canonical_root="${counterparts[0]}"
	sibling_root="$REPO_DIR"
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
