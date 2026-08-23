# shellcheck shell=bash
# shellcheck disable=SC2034  # UPGRADE_STEP_RESULT is read by the update summary.
# Shared update result tracking, version comparison, and command-failure output.

declare -A UPGRADE_STEP_RESULT=()

_report_command_failure() {
	local exit_status="$1" retry_command="$2"
	printf '%s>> FAILED (exit %s) — retry manually: %s <<%s\n' \
		"$C_RED" "$exit_status" "$retry_command" "$C_RESET" >&2
}

_run_upgrade_step() {
	local label="$1" retry_command="$2"
	shift 2
	printf '\n%s%s== %s ==%s\n' "$C_BOLD" "$C_YELLOW" "$label" "$C_RESET"
	set +e
	"$@"
	local rc=$?
	set -e
	if [[ $rc -ne 0 ]]; then
		_report_command_failure "$rc" "$retry_command"
		UPGRADE_STEP_RESULT["$label"]="failed"
	else
		UPGRADE_STEP_RESULT["$label"]="ok"
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
