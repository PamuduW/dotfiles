# shellcheck shell=bash
# shellcheck disable=SC2034  # The palette is published to every sourced module.
# One ANSI palette and one set of semantic column colorizers.
#
# The palette literals used to be written out four times (bin/bin/dotfiles,
# ui.sh, report_table.sh, and Agentbot's install.sh) and the column colorizers
# five times, with case lists that had already drifted. Callers keep their own
# "should colour be on here?" predicate — those differ on purpose — and use
# these for the values and the mappings.

if [[ "${_DOTFILES_COLORS_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_COLORS_LOADED=1

colors_set_palette() {
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_DIM=$'\033[2m'
	C_MAGENTA=$'\033[35m'
	C_WHITE=$'\033[37m'
	C_CYAN=$'\033[36m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_ORANGE=$'\033[38;5;208m'
	C_RED=$'\033[31m'
	C_BLUE=$'\033[34m'
	C_INVERT=$'\033[7m'
}

# Fill in any palette token a caller left unset, so modules can reference the
# whole palette under `set -u` when only part of it was installed.
colors_complete_palette() {
	C_RESET="${C_RESET:-}" C_BOLD="${C_BOLD:-}" C_DIM="${C_DIM:-}"
	C_MAGENTA="${C_MAGENTA:-}" C_WHITE="${C_WHITE:-}" C_CYAN="${C_CYAN:-}" C_GREEN="${C_GREEN:-}"
	C_YELLOW="${C_YELLOW:-}" C_ORANGE="${C_ORANGE:-}" C_RED="${C_RED:-}"
	C_BLUE="${C_BLUE:-}" C_INVERT="${C_INVERT:-}"
}

colors_clear_palette() {
	C_RESET='' C_BOLD='' C_DIM='' C_MAGENTA='' C_WHITE='' C_CYAN=''
	C_GREEN='' C_YELLOW='' C_ORANGE='' C_RED='' C_BLUE='' C_INVERT=''
}

_colors_wrap() {
	printf '%s%s%s' "$1" "$2" "${1:+${C_RESET:-}}"
}

# The "result" column: what state is this component in?
status_color_result() {
	local result="$1"
	case "$result" in
	ok | installed | configured | linked | up\ to\ date | current)
		_colors_wrap "${C_GREEN:-}" "$result"
		;;
	missing | failed | error)
		_colors_wrap "${C_RED:-}" "$result"
		;;
	check | drift | extra | warn | warning | partial)
		_colors_wrap "${C_YELLOW:-}" "$result"
		;;
	skipped*)
		_colors_wrap "${C_DIM:-}" "$result"
		;;
	info | dry-run)
		_colors_wrap "${C_CYAN:-}" "$result"
		;;
	*)
		printf '%s' "$result"
		;;
	esac
}

# The "action" column: what will this run do?
status_color_action() {
	local action="$1"
	case "$action" in
	up\ to\ date | skip | current | verified\ current)
		_colors_wrap "${C_GREEN:-}" "$action"
		;;
	latest\ unchecked)
		_colors_wrap "${C_DIM:-}" "$action"
		;;
	upgrade* | refresh | continue | check | replace*)
		_colors_wrap "${C_YELLOW:-}" "$action"
		;;
	pull* | verified)
		_colors_wrap "${C_CYAN:-}" "$action"
		;;
	unchecked)
		_colors_wrap "${C_YELLOW:-}" "$action"
		;;
	blocked)
		_colors_wrap "${C_RED:-}" "$action"
		;;
	*)
		printf '%s' "$action"
		;;
	esac
}

# The "available" column: is there anything upstream? Note this deliberately
# dims "up to date", where the action column greens it.
status_color_available() {
	local available="$1"
	case "$available" in
	none | — | up\ to\ date)
		_colors_wrap "${C_DIM:-}" "$available"
		;;
	*behind | *ahead | update* | *review*)
		_colors_wrap "${C_YELLOW:-}" "$available"
		;;
	*)
		_colors_wrap "${C_CYAN:-}" "$available"
		;;
	esac
}
