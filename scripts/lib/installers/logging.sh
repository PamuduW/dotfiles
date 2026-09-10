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

# A step that is working, said in a way a log file will not inherit.
#
# Install output goes through tee, so anything written to stdout lands in the
# log as well as on screen -- and a log full of spinner frames is worse than no
# spinner. The animation is written straight to the terminal instead, on its own
# line below the step, and erased before the next line prints. A run with no
# terminal, or with DOTFILES_NO_PROGRESS_ANIMATION set, simply has none.
_STEP_SPINNER_PID=''
_STEP_SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

_step_spinner_start() {
	local message="$1"

	_step_spinner_stop
	[[ -z "${DOTFILES_NO_PROGRESS_ANIMATION:-}" ]] || return 0
	declare -F tty_output_available >/dev/null 2>&1 || return 0
	tty_output_available || return 0

	(
		local index=0
		while true; do
			tty_printf '\r  %s %s' "${_STEP_SPINNER_FRAMES[index % 10]}" "$message"
			index=$((index + 1))
			sleep 0.12
		done
	) &
	_STEP_SPINNER_PID=$!
}

_step_spinner_stop() {
	[[ -n "$_STEP_SPINNER_PID" ]] || return 0
	kill "$_STEP_SPINNER_PID" 2>/dev/null
	wait "$_STEP_SPINNER_PID" 2>/dev/null
	_STEP_SPINNER_PID=''
	# Erase the line the animation owned, so the next log line starts clean.
	declare -F tty_printf >/dev/null 2>&1 && tty_printf '\r\033[K'
	return 0
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
	# Any line ends the step that was running: the run has moved on, and the
	# animation must not still be claiming otherwise underneath it.
	_step_spinner_stop
	printf '%s[%s]%s %s\n' "$color" "$level" "$C_RESET" "$message"
	[[ "$level" == STEP ]] && _step_spinner_start "$message"
	return 0
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
