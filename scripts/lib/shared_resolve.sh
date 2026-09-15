# shellcheck shell=bash
# Locate the dotfiles-shared checkout.
#
# This is the one piece of shared logic that cannot live in dotfiles-shared,
# because it is what finds it. It is therefore carried verbatim by both
# consumers on purpose, and is kept small and dependency-free for that reason:
# nothing here may source shared code, and it must work before any runtime is
# provisioned.
#
# Resolution order, first valid checkout wins:
#
#   1. $DOTFILES_SHARED_DIR          an operator naming the checkout outright
#   2. <parent of this repo>/dotfiles-shared
#                                    the sibling layout bootstrap.sh creates
#   3. $HOME/dotfiles-shared         the bootstrap default
#
# On success it publishes DOTFILES_SHARED_ROOT and DOTFILES_SHARED_LIB. On
# failure it reports the checkout it wanted and the command that creates it,
# rather than letting the caller die on `source: No such file`.

# The CONTRACT revision this repository is written against. dotfiles-shared
# raises its CONTRACT only for a change that is not backward compatible, so the
# two must match exactly; a mismatch is a loud stop, not a warning.
DOTFILES_SHARED_CONTRACT_REQUIRED=1

DOTFILES_SHARED_URL='https://github.com/PamuduW/dotfiles-shared'

_dotfiles_shared_is_checkout() {
	[[ -f "$1/CONTRACT" && -f "$1/scripts/lib/shared/tui/colors.sh" ]]
}

# Two spaces, the left edge every other line of a run prints at.
_dotfiles_shared_err() {
	printf '  Error: %s\n' "$*" >&2
}

dotfiles_shared_resolve() {
	local repo_root="$1"
	local candidate found='' contract
	local -a candidates=()

	[[ -n "${DOTFILES_SHARED_DIR:-}" ]] && candidates+=("$DOTFILES_SHARED_DIR")
	# Parameter expansion rather than dirname: this runs before a run has
	# proven anything about PATH, and an unresolvable helper here would look
	# like a missing checkout.
	candidates+=("${repo_root%/*}/dotfiles-shared" "$HOME/dotfiles-shared")

	for candidate in "${candidates[@]}"; do
		if _dotfiles_shared_is_checkout "$candidate"; then
			found="$(cd -- "$candidate" && pwd)"
			break
		fi
	done

	if [[ -z "$found" ]]; then
		_dotfiles_shared_err "no dotfiles-shared checkout found. Looked in:"
		local -A seen=()
		for candidate in "${candidates[@]}"; do
			# The sibling and the $HOME default are the same path when the
			# repository sits directly in $HOME; listing it twice reads as a
			# bug in the message rather than one place that was checked.
			[[ -n "${seen[$candidate]:-}" ]] && continue
			seen[$candidate]=1
			printf '    %s\n' "$candidate" >&2
		done
		printf '  Clone it beside this repository, then rerun:\n' >&2
		printf '    git clone %s %s\n' \
			"$DOTFILES_SHARED_URL" "${repo_root%/*}/dotfiles-shared" >&2
		return 1
	fi

	contract=''
	[[ -r "$found/CONTRACT" ]] && read -r contract <"$found/CONTRACT"
	contract="${contract//[[:space:]]/}"
	if [[ "$contract" != "$DOTFILES_SHARED_CONTRACT_REQUIRED" ]]; then
		_dotfiles_shared_err "dotfiles-shared at $found is CONTRACT ${contract:-unreadable}, but this repository requires ${DOTFILES_SHARED_CONTRACT_REQUIRED}."
		printf '  Update both checkouts to matching revisions, then rerun:\n' >&2
		printf '    git -C %s pull\n' "$found" >&2
		return 1
	fi

	DOTFILES_SHARED_ROOT="$found"
	DOTFILES_SHARED_LIB="$found/scripts/lib/shared"
	export DOTFILES_SHARED_ROOT DOTFILES_SHARED_LIB
}

# Resolve once per shell. Files that consume shared code call this rather than
# dotfiles_shared_resolve directly, because each of them can also be sourced on
# its own -- by a test, or by a caller that did not go through the loader.
dotfiles_shared_require() {
	[[ -n "${DOTFILES_SHARED_LIB:-}" ]] && return 0
	dotfiles_shared_resolve "$1"
}
