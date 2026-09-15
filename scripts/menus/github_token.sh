# shellcheck shell=bash
# shellcheck disable=SC2034  # The GITHUB_TOKEN_MENU_* settings are this file's published output, read by the shared screen.
# Dotfiles binding for the shared GitHub token screen.
#
# The screen itself lives in the dotfiles-shared repository, which this
# installer and the Agentbot CLI both resolve at runtime. This file supplies
# only the Dotfiles identity: the breadcrumb root and where the width comes
# from. There is no seam to refresh -- Dotfiles writes DOTFILES_TTY_* directly.

GITHUB_TOKEN_MENU_ROOT="${DOTFILES_MENU_ROOT:-Dotfiles}"
GITHUB_TOKEN_MENU_COLS_FN=menu_tty_cols

if [[ -z "${DOTFILES_SHARED_LIB:-}" ]]; then
	# shellcheck source=scripts/lib/shared_resolve.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/shared_resolve.sh"
	dotfiles_shared_require "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
fi
# shellcheck source=/dev/null
source "$DOTFILES_SHARED_LIB/github_token_menu.sh"
