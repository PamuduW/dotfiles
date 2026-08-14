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
	printf '[%s] %s\n' "$level" "$message"
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
log_warn() { _log_prefix WARN "$1"; }
