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
	printf '%s\n' '[Legend] STEP=starting  OK=completed  SKIP=already satisfied  WARN=needs attention'
}

log_step() { _log_prefix STEP "$1"; }
log_ok() { _log_prefix OK "$1"; }
log_skip() { _log_prefix SKIP "$1"; }
log_warn() { _log_prefix WARN "$1"; }
