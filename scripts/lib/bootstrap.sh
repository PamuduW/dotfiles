# shellcheck shell=bash
# Bootstrap paths and TTY detection when DOTFILES_DIR is not preset.
# Sourced by scripts/install.sh and menu modules — no set -euo pipefail here.

if [[ -z "${DOTFILES_DIR:-}" ]]; then
	SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
	DOTFILES_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

	# See scripts/install.sh: the controlling terminal decides this, not stdin.
	# shellcheck source=scripts/lib/shared/tui/tty.sh
	source "$DOTFILES_DIR/scripts/lib/shared/tui/tty.sh"
	export DOTFILES_INTERACTIVE_TTY=false
	if tty_available; then
		DOTFILES_INTERACTIVE_TTY=true
	fi
fi

# Derived from DOTFILES_DIR however it arrived, not only when this file had to
# resolve it. It used to be set inside that branch, so a caller that already
# knew its checkout -- the dotfiles CLI always does -- left PKG_FILE unbound,
# and the apt components then installed nothing while their probes still
# reported "installed".
export PKG_FILE="${PKG_FILE:-$DOTFILES_DIR/packages/packages.txt}"
