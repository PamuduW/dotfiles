# shellcheck shell=bash
# shellcheck disable=SC2034  # UPGRADE_STEP_RESULT is read by the update summary.
# Shared update result tracking, version comparison, and command-failure output.

declare -gA UPGRADE_STEP_RESULT=()
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
	printf '%s>> FAILED (exit %s) — retry manually: %s <<%s\n' \
		"$C_RED" "$exit_status" "$retry_command" "$C_RESET" >&2
}

_run_upgrade_step() {
	local label="$1" retry_command="$2"
	shift 2
	printf '\n%s%s== %s ==%s\n' "$C_BOLD" "$C_YELLOW" "$label" "$C_RESET"
	UPGRADE_STEP_ACTIVE_RESULT="$UPGRADE_RESULT_CHECKED_NO_CHANGE"
	set +e
	"$@"
	local rc=$?
	set -e
	if [[ $rc -ne 0 ]]; then
		_report_command_failure "$rc" "$retry_command"
		UPGRADE_STEP_RESULT["$label"]="$UPGRADE_RESULT_FAILED"
	else
		UPGRADE_STEP_RESULT["$label"]="$UPGRADE_STEP_ACTIVE_RESULT"
	fi
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
