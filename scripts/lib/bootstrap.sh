# shellcheck shell=bash
# Bootstrap paths and TTY detection when DOTFILES_DIR is not preset.
# Sourced by scripts/install.sh and menu modules — no set -euo pipefail here.

if [[ -z "${DOTFILES_DIR:-}" ]]; then
	SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
	DOTFILES_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
	export PKG_FILE="$DOTFILES_DIR/packages/packages.txt"

	# See scripts/install.sh: the controlling terminal decides this, not stdin.
	# shellcheck source=scripts/lib/shared/tui/tty.sh
	source "$DOTFILES_DIR/scripts/lib/shared/tui/tty.sh"
	export DOTFILES_INTERACTIVE_TTY=false
	if tty_available; then
		DOTFILES_INTERACTIVE_TTY=true
	fi
fi
