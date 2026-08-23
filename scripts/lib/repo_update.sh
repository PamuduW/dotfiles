# shellcheck shell=bash
# Dotfiles binding for the shared repository-update state machine.
#
# The implementation lives in scripts/lib/shared/repo_update.sh and is shared
# verbatim with the sibling repository. This file only supplies the Dotfiles
# identity: recovery branches are named recovery/dotfiles-*, and the result
# table uses the shared fixed-width report layout.

if [[ "${_DOTFILES_REPO_UPDATE_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_REPO_UPDATE_LOADED=1

REPO_UPDATE_RECOVERY_PREFIX=dotfiles
export REPO_UPDATE_RECOVERY_PREFIX

# shellcheck source=scripts/lib/shared/repo_update.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/shared/repo_update.sh"
