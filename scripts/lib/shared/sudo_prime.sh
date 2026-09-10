# shellcheck shell=bash
# One masked password prompt per run, instead of sudo's silent one.
#
# sudo caches a successful authentication for the rest of the run, so priming it
# once up front means the 47 later `sudo` calls never prompt at all -- and the
# single prompt the operator does see masks with `*` like every other prompt
# these tools own, and the run places it rather than sudo surfacing it from
# inside whichever step needs root first.
#
# SUDO_ASKPASS is the supported way to replace that prompt; ssh-askpass and
# ksshaskpass use the same mechanism. Falls back to sudo's own prompt whenever
# the helper cannot run, so a machine without a terminal is never worse off than
# before.

if [[ "${_DOTFILES_SUDO_PRIME_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_SUDO_PRIME_LOADED=1

_SUDO_PRIME_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sudo_prime() {
	local helper="$_SUDO_PRIME_DIR/askpass.sh"

	command -v sudo >/dev/null 2>&1 || return 0
	# Already authenticated, or this machine does not ask: nothing to prompt for.
	sudo -n true 2>/dev/null && return 0

	if [[ -x "$helper" ]] && declare -F tty_available >/dev/null 2>&1 && tty_available; then
		if SUDO_ASKPASS="$helper" sudo -A -v; then
			# The masked prompt ends its own line; this is the gap between it
			# and the install output, printed only when a prompt was shown --
			# an already-authenticated run returned above and adds nothing.
			tty_printf '\n'
			return 0
		fi
		# A wrong password or a declined prompt is the operator's answer, not a
		# reason to ask again through a different mechanism.
		return 1
	fi

	sudo -v
}
