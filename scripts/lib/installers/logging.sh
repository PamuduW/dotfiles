# shellcheck shell=bash

_run_quiet_command() {
	local label="$1"
	shift

	local tmp
	tmp="$(mktemp)"

	if "$@" >"$tmp" 2>&1; then
		rm -f "$tmp"
		return 0
	fi

	echo "  Error during ${label}:" >&2
	cat "$tmp" >&2
	rm -f "$tmp"
	return 1
}

_log_prefix() {
	local level="$1"
	local message="$2"
	local color=''
	if declare -F _rt_ensure_colors >/dev/null 2>&1; then
		_rt_ensure_colors
	else
		C_RESET='' C_CYAN='' C_GREEN='' C_DIM='' C_YELLOW=''
	fi
	case "$level" in
	STEP) color="$C_CYAN" ;;
	OK) color="$C_GREEN" ;;
	SKIP) color="$C_DIM" ;;
	WARN) color="$C_YELLOW" ;;
	esac
	printf '%s[%s]%s %s\n' "$color" "$level" "$C_RESET" "$message"
}

_log_legend_line() {
	if declare -F _rt_ensure_colors >/dev/null; then
		_rt_ensure_colors
	else
		C_RESET='' C_CYAN='' C_GREEN='' C_DIM='' C_YELLOW=''
	fi
	printf '[Legend] %sSTEP=starting%s  %sOK=completed%s  %sSKIP=already satisfied%s  %sWARN=needs attention%s\n' \
		"$C_CYAN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
}

log_step() { _log_prefix STEP "$1"; }
log_ok() { _log_prefix OK "$1"; }
log_skip() { _log_prefix SKIP "$1"; }

# A forced reinstall (the plan screen's `x`) bypasses "this is already here"
# checks, so a corrupted install can be repaired without deleting things by
# hand. It deliberately does not bypass content checks: writers that compare
# what is on disk already rewrite when it differs, so they repair drift on
# their own, and forcing them only adds churn and backup files.
force_reinstall_requested() {
	[[ "${DOTFILES_FORCE_REINSTALL:-0}" == 1 ]]
}

# Report "already present, nothing to do" -- unless a forced reinstall is in
# progress, in which case the caller falls through and does the work again.
skip_unless_forced() {
	if force_reinstall_requested; then
		return 1
	fi
	log_skip "$1"
	return 0
}
log_warn() { _log_prefix WARN "$1"; }
