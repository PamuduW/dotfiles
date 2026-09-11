# shellcheck shell=bash

# Every line the run prints starts at the same column as the headers and tables
# around it: two spaces, the indent ui_print_header and rt_print_table_row
# already use. Steps, rules and the legend sat hard against column 0 and the
# screen read as two documents laid on top of each other.

_run_quiet_command() {
	local label="$1"
	shift

	local tmp status=0
	tmp="$(mktemp)"

	# Captured on the failing command itself: `$?` after `fi` is the status of
	# the if statement, which is zero when no branch ran.
	"$@" >"$tmp" 2>&1 || status=$?
	if ((status == 0)); then
		rm -f "$tmp"
		return 0
	fi

	echo "  Error during ${label}:" >&2
	sed 's/^/    /' "$tmp" >&2
	rm -f "$tmp"
	# The command's own status, not a flat 1: hiding output is this helper's
	# job, and callers that propagate an exit code -- install_portainer returns
	# whatever docker said -- would otherwise lose it by being quieted.
	return "$status"
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
			# The cursor is parked back at column 0 after each frame. Anything
			# a tool prints mid-step then overwrites the animation from the
			# left instead of being appended to the end of it -- which is how
			# a stray container id arrived welded to the end of a step name.
			tty_printf '\r    %s %s\r' "${_STEP_SPINNER_FRAMES[index % 10]}" "$message"
			index=$((index + 1))
			sleep 0.12
		done
	) &
	_STEP_SPINNER_PID=$!
}

# A rule between one component's output and the next.
#
# Twenty components in one stream read as a wall; the boundary an operator cares
# about is the component, which is what the install loop iterates. Dim, because
# it separates rather than says anything.
log_component_rule() {
	if declare -F _rt_ensure_colors >/dev/null 2>&1; then
		_rt_ensure_colors
	fi
	# A boundary ends the step before it, so no animation is left running
	# underneath the next component's output.
	_step_spinner_stop
	printf '  %s%s%s\n' "${C_DIM:-}" '----------------------------------------' "${C_RESET:-}"
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

# How many prefixed lines the run has printed. The update step runner reads it
# across one step to tell a step that reported its own outcome from one that
# recorded a result silently, without every updater having to say which it is.
_LOG_LINE_COUNT=0

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
	printf '  %s[%s]%s %s\n' "$color" "$level" "$C_RESET" "$message"
	_LOG_LINE_COUNT=$((_LOG_LINE_COUNT + 1))
	[[ "$level" == STEP ]] && _step_spinner_start "$message"
	return 0
}

_log_legend_line() {
	if declare -F _rt_ensure_colors >/dev/null; then
		_rt_ensure_colors
	else
		C_RESET='' C_CYAN='' C_GREEN='' C_DIM='' C_YELLOW=''
	fi
	printf '  [Legend] %sSTEP=starting%s  %sOK=completed%s  %sSKIP=already satisfied%s  %sWARN=needs attention%s\n' \
		"$C_CYAN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
}

# Wall-clock reporting, shared by the install and the update.
#
# The install has closed on "Install took ... Slowest components:" for a while
# and the update closed on nothing, so the longer of the two runs was the one
# that never said where its time went. These live here, beside log_step, so
# both load sets reach them -- the update's does not load the component
# installer, which is where this used to live in full.

timing_now_seconds() {
	printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}"
}

# Minutes and seconds, the way the total above the list is written. A column of
# raw seconds made the reader convert every row to compare it with the heading.
timing_format() {
	printf '%dm %02ds' "$(($1 / 60))" "$(($1 % 60))"
}

# The slowest handful and the total. Enough to tell a network-bound step from a
# slow one without turning the summary into a profile.
#
#   print_timing_summary <label> <associative-array-name> <total-seconds>
print_timing_summary() {
	local label="$1" total="$3" key seconds
	local -n _timing_seconds="$2"
	((${#_timing_seconds[@]} > 0)) || return 0
	echo ""
	printf '  %s%s took %s. Slowest %s:%s\n' \
		"${C_ORANGE:-}" "$label" "$(timing_format "$total")" \
		"${TIMING_SUMMARY_NOUN:-components}" "${C_RESET:-}"
	while read -r seconds key; do
		((seconds > 0)) || continue
		printf '    %7s  %s\n' "$(timing_format "$seconds")" "$key"
	done < <(
		for key in "${!_timing_seconds[@]}"; do
			printf '%s %s\n' "${_timing_seconds[$key]}" "$key"
		done | sort -rn | head -6
	)
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
