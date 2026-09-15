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

# shellcheck source=/dev/null
source "$DOTFILES_SHARED_LIB/repo_gate.sh"

_DOTFILES_GATE_DECISION=''
_DOTFILES_GATE_RESULT=''

# One repository, named the way this product names them. The ordering, the
# aggregation and the exit contract belong to repo_gate_run.
_dotfiles_gate_one() {
	local rc=0
	case "$1" in
	shared)
		repo_update_run "$DOTFILES_SHARED_ROOT" 'shared repo' "$_DOTFILES_GATE_DECISION" \
			DOTFILES_SHARED_REPO_RESULT 'PamuduW/dotfiles-shared' || rc=$?
		# A stop here is the one the caller reports, so it is adopted before
		# the gate returns and the Dotfiles repository is never reached.
		((rc == 0 || rc == 2)) ||
			repo_gate_adopt "$_DOTFILES_GATE_RESULT" DOTFILES_SHARED_REPO_RESULT
		;;
	own)
		repo_update_run "$DOTFILES_DIR" 'dotfiles repo' "$_DOTFILES_GATE_DECISION" \
			"$_DOTFILES_GATE_RESULT" 'PamuduW/dotfiles' || rc=$?
		;;
	esac
	return "$rc"
}

# Every command that touches this checkout gates the repositories it depends on
# together, before any work: the shared library first, because either product
# loads code from it, then this repository. Only the ones present are checked,
# so "Dotfiles only" is gated on two and a full run on three.
dotfiles_repo_gate() {
	_DOTFILES_GATE_DECISION="$1"
	_DOTFILES_GATE_RESULT="$2"
	local -a targets=()

	# shellcheck disable=SC2034  # Read by shared_repo_status to build its row.
	DOTFILES_SHARED_REPO_RESULT=()
	[[ -n "${DOTFILES_SHARED_ROOT:-}" ]] && targets+=(shared)
	targets+=(own)

	repo_gate_run _dotfiles_gate_one "${targets[@]}"
}
