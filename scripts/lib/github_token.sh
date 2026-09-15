# shellcheck shell=bash
# GitHub token storage and validation.
#
# The implementation lives in the dotfiles-shared repository, which both this
# installer and the Agentbot CLI resolve at runtime. Edit it there; there is no
# vendored second copy to keep in step.

if [[ -z "${DOTFILES_SHARED_LIB:-}" ]]; then
	# shellcheck source=scripts/lib/shared_resolve.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/shared_resolve.sh"
	dotfiles_shared_require "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
fi
# shellcheck source=/dev/null
source "$DOTFILES_SHARED_LIB/github_token.sh"
