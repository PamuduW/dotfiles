#!/usr/bin/env bash
# Password prompt for sudo.
#
# Echoes nothing, like sudo's own prompt: a `*` per keystroke publishes the
# length of the password to anyone looking at the screen, and this is the prompt
# the operator answers most often and in the least private places.
#
# Invoked by sudo through SUDO_ASKPASS, which is the supported mechanism for
# replacing that prompt -- the same one ssh-askpass and ksshaskpass use. The
# password goes from the terminal to this process and out on stdout to sudo:
# never a file, never a command line, never a log.
#
# Reads the terminal directly, because sudo gives an askpass helper no stdin.

set -uo pipefail

_ASKPASS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/shared/tui/tty.sh
source "$_ASKPASS_DIR/tui/tty.sh"

prompt="${1:-Password:}"

# Without a terminal there is nothing to mask and nothing to read; failing here
# lets sudo fall back to its own prompt rather than hanging on a closed handle.
tty_available || exit 1

password=''
read_tty_secret password "  $prompt " '' || exit 1

printf '%s\n' "$password"
