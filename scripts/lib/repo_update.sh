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
