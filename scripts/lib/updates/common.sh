# shellcheck shell=bash
# shellcheck disable=SC2034  # UPGRADE_STEP_RESULT is read by the update summary.
# Shared update result tracking, version comparison, and command-failure output.

declare -gA UPGRADE_STEP_RESULT=()
# Declared here beside UPGRADE_STEP_RESULT, not where the run resets it. An
# associative array that is only declared inside the run is an *indexed* one
# everywhere else, and bash evaluates an indexed subscript as arithmetic -- so
# `UPGRADE_STEP_SECONDS["probe"]=5` died on "probe: unbound variable" in every
# test that drives a step directly.
declare -gA UPGRADE_STEP_SECONDS=()
UPGRADE_STEP_ACTIVE_RESULT=checked-no-change

UPDATE_CHECK_UPGRADE=upgrade
UPDATE_CHECK_CURRENT=current
UPDATE_CHECK_UNKNOWN=unknown
UPDATE_CHECK_REFRESH_REQUIRED=refresh-required
UPDATE_CHECK_EXTERNAL=external
UPDATE_CHECK_SKIP=skip

UPGRADE_RESULT_UPDATED=updated
UPGRADE_RESULT_ALREADY_CURRENT=already-current
UPGRADE_RESULT_CHECKED_NO_CHANGE=checked-no-change
UPGRADE_RESULT_RECOVERED=recovered
UPGRADE_RESULT_SKIPPED=skipped
UPGRADE_RESULT_FAILED=failed
UPGRADE_RESULT_NOT_RUN=not-run

upgrade_result_set() {
	case "${1:-}" in
	updated | already-current | checked-no-change | recovered | skipped)
		UPGRADE_STEP_ACTIVE_RESULT="$1"
		;;
	*)
		printf 'invalid upgrade result: %s\n' "${1:-}" >&2
		return 2
		;;
	esac
}

_report_command_failure() {
	local exit_status="$1" retry_command="$2"
	# Any line ends the running step, and a failure notice most of all: the
	# animation would otherwise still be claiming the step was in progress.
	declare -F _step_spinner_stop >/dev/null 2>&1 && _step_spinner_stop
	printf '  %s>> FAILED (exit %s) — retry manually: %s <<%s\n' \
		"$C_RED" "$exit_status" "$retry_command" "$C_RESET" >&2
}

# Every step ends on one outcome line, in the install screen's vocabulary.
# A step that recorded a result without printing anything used to leave a
# heading with nothing under it, which reads as a step that died; and a step
# that returns while its animation is still running leaves the animation to be
# overwritten by the next component's rule.
_upgrade_step_close() {
	local label="$1" result="$2"
	case "$result" in
	updated) log_ok "$label updated" ;;
	already-current) log_skip "$label already current" ;;
	recovered) log_ok "$label recovered" ;;
	skipped) log_skip "$label skipped" ;;
	*) log_ok "$label checked" ;;
	esac
}

# The rule separates one component from the next, so the first thing a section
# prints must not be one: the install screen opens on its first step, not on a
# rule with nothing above it.
_UPGRADE_SECTION_START=0

upgrade_section_begin() { _UPGRADE_SECTION_START="$_LOG_LINE_COUNT"; }

_upgrade_rule_between() {
	((_LOG_LINE_COUNT > _UPGRADE_SECTION_START)) || return 0
	log_component_rule
}

_run_upgrade_step() {
	local label="$1" retry_command="$2"
	shift 2
	local lines_before="$_LOG_LINE_COUNT"
	_upgrade_rule_between
	log_step "$label"
	UPGRADE_STEP_ACTIVE_RESULT="$UPGRADE_RESULT_CHECKED_NO_CHANGE"
	# Per-step wall clock, so the update can close on where its time went the
	# way the install already does. Started after the heading and stopped
	# before the outcome is reported, which is the step's own work.
	local step_started
	step_started="$(timing_now_seconds)"
	set +e
	"$@"
	local rc=$?
	set -e
	UPGRADE_STEP_SECONDS["$label"]=$(($(timing_now_seconds) - step_started))
	if [[ $rc -ne 0 ]]; then
		_report_command_failure "$rc" "$retry_command"
		UPGRADE_STEP_RESULT["$label"]="$UPGRADE_RESULT_FAILED"
		return 0
	fi
	UPGRADE_STEP_RESULT["$label"]="$UPGRADE_STEP_ACTIVE_RESULT"
	# One line printed since entry is the [STEP] line and nothing else: the step
	# recorded a result without saying anything, so give it a closing line
	# rather than leaving a heading with nothing under it.
	((_LOG_LINE_COUNT > lines_before + 1)) ||
		_upgrade_step_close "$label" "$UPGRADE_STEP_ACTIVE_RESULT"
}

_github_latest_version() {
	github_latest_release_version "$1"
}

_version_gt() {
	# Returns 0 if $1 > $2 (sort -V)
	[[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" && "$1" != "$2" ]]
}

_load_nvm() {
	local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
	# shellcheck source=/dev/null
	[[ -s "${nvm_dir}/nvm.sh" ]] && . "${nvm_dir}/nvm.sh"
}
