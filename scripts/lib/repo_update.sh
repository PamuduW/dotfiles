# shellcheck shell=bash
# Dotfiles binding for the shared repository-update state machine.
#
# The implementation lives in the dotfiles-shared repository, which this
# installer and the Agentbot CLI both resolve at runtime. This file only
# supplies the Dotfiles identity: recovery branches are named
# recovery/dotfiles-*, and the result table uses the shared fixed-width layout.

if [[ "${_DOTFILES_REPO_UPDATE_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_REPO_UPDATE_LOADED=1

REPO_UPDATE_RECOVERY_PREFIX=dotfiles
export REPO_UPDATE_RECOVERY_PREFIX

if [[ -z "${DOTFILES_SHARED_LIB:-}" ]]; then
	# shellcheck source=scripts/lib/shared_resolve.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/shared_resolve.sh"
	dotfiles_shared_require "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
fi
# shellcheck source=/dev/null
source "$DOTFILES_SHARED_LIB/repo_update.sh"

# Every command that touches this checkout gates the repositories it depends on
# together, before any work: the shared library first, because either product
# loads code from it, then this repository. Only the ones actually present are
# checked, so "Dotfiles only" is gated on two and a full run on three.
#
# One gate rather than one per repository, and up front rather than when each
# is first needed: the operator learns everything that will move before
# anything moves, and a change costs one restart instead of one per repository.
#
# Contract: 0 continue, 1 stopped or declined, 2 a checkout moved and the
# caller must restart -- pulling replaces files a running shell has already
# sourced, and the CONTRACT compatibility this run checked at startup was
# checked against the checkout that pull just replaced.
# Copy one result array over another, by name. Bash has no assignment for
# associative arrays, so the keys are walked.
# Filled by the gate, read by shared_repo_status to build its row. Declared
# here, beside the code that assigns it: a caller that gates without loading
# the update registry still gets a usable associative array.
declare -gA DOTFILES_SHARED_REPO_RESULT=()

_dotfiles_repo_gate_adopt() {
	local -n _adopt_dst="$1"
	local -n _adopt_src="$2"
	local key
	_adopt_dst=()
	for key in "${!_adopt_src[@]}"; do
		_adopt_dst["$key"]="${_adopt_src[$key]}"
	done
}

dotfiles_repo_gate() {
	local decision_fn="$1" result_name="$2"
	local rc=0 changed=0

	# shellcheck disable=SC2034  # Read by shared_repo_status to build its row.
	DOTFILES_SHARED_REPO_RESULT=()
	if [[ -n "${DOTFILES_SHARED_ROOT:-}" ]]; then
		repo_update_run "$DOTFILES_SHARED_ROOT" 'shared repo' "$decision_fn" \
			DOTFILES_SHARED_REPO_RESULT 'PamuduW/dotfiles-shared' || rc=$?
		case "$rc" in
		0) ;;
		2) changed=1 ;;
		*)
			# Whichever repository stopped becomes the reported result, so a
			# caller's decline and stop handling works without having to know
			# which one it was.
			_dotfiles_repo_gate_adopt "$result_name" DOTFILES_SHARED_REPO_RESULT
			return "$rc"
			;;
		esac
	fi

	rc=0
	repo_update_run "$DOTFILES_DIR" 'dotfiles repo' "$decision_fn" "$result_name" \
		'PamuduW/dotfiles' || rc=$?
	case "$rc" in
	0) ;;
	2) changed=1 ;;
	*) return "$rc" ;;
	esac

	((changed)) && return 2
	return 0
}
