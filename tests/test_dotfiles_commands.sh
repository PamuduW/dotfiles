#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# The read-only Dotfiles commands added alongside status: doctor and logs,
# plus update's dry-run stop.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/bin/bin/dotfiles" >/dev/null
dotfiles_load_command full-update

test_doctor_reports_only_what_needs_attention() (
	collect_component_status_rows() {
		local -n out="$1"
		out=(
			'Git identity|configured|configured'
			'Node.js|node v24|installed'
			'Apply dotfiles|3 targets missing|missing'
			'WSL config|not as expected|check'
		)
	}
	local output rc=0
	output="$(NO_COLOR=1 cmd_doctor 2>&1)" || rc=$?
	[[ "$rc" -eq 1 ]] || return 1
	[[ "$output" == *'Apply dotfiles'* && "$output" == *'WSL config'* ]] || return 1
	# healthy components are not listed
	[[ "$output" != *'Git identity'* && "$output" != *'Node.js'* ]] || return 1
	[[ "$output" == *'Suggested'* ]]
)

test_doctor_succeeds_when_everything_is_healthy() (
	collect_component_status_rows() {
		local -n out="$1"
		out=('Git identity|configured|configured' 'Node.js|node v24|installed')
	}
	local output rc=0
	output="$(NO_COLOR=1 cmd_doctor 2>&1)" || rc=$?
	[[ "$rc" -eq 0 ]] || return 1
	[[ "$output" == *'Nothing needs attention.'* ]]
)

test_update_dry_run_reports_then_stops() (
	local events="$TEST_HARNESS_ROOT/dry-run.events"
	: >"$events"
	repo_update_run() {
		local -n result_ref="$4"
		result_ref=([outcome]=current [reason]=current [state]=current)
		return 0
	}
	repo_update_is_declined() { return 1; }
	print_report_table() { printf 'report\n' >>"$events"; }
	_dotfiles_confirm() { printf 'confirm\n' >>"$events"; }
	_run_update_downstream() { printf 'downstream\n' >>"$events"; }
	print_upgrade_summary() { printf 'summary\n' >>"$events"; }

	cmd_update --dry-run >/dev/null 2>&1 || return 1
	# the report is produced, nothing downstream runs, and it never prompts
	[[ "$(<"$events")" == 'report' ]]
)

test_update_without_dry_run_still_prompts_and_runs() (
	local events="$TEST_HARNESS_ROOT/wet-run.events"
	: >"$events"
	repo_update_run() {
		local -n result_ref="$4"
		result_ref=([outcome]=current [reason]=current [state]=current)
		return 0
	}
	repo_update_is_declined() { return 1; }
	print_report_table() { printf 'report\n' >>"$events"; }
	_dotfiles_confirm() {
		printf 'confirm\n' >>"$events"
		return 0
	}
	_run_update_downstream() { printf 'downstream\n' >>"$events"; }
	print_upgrade_summary() { printf 'summary\n' >>"$events"; }

	cmd_update >/dev/null 2>&1 || return 1
	[[ "$(<"$events")" == $'report\nconfirm\ndownstream\nsummary' ]]
)

test_logs_lists_newest_first_and_prints_the_last() (
	local log_dir="$TEST_HARNESS_ROOT/logs-repo/log"
	mkdir -p "$log_dir"
	printf 'older\n' >"$log_dir/2026-01-01_00-00-00.log"
	printf 'newest content\n' >"$log_dir/2026-06-01_00-00-00.log"
	DOTFILES_DIR="$TEST_HARNESS_ROOT/logs-repo"

	local listed
	listed="$(NO_COLOR=1 cmd_logs 2>&1)"
	[[ "$listed" == *'2026-06-01_00-00-00.log'* && "$listed" == *'2 log(s)'* ]] || return 1
	# newest first
	[[ "$(grep -n '2026-06-01' <<<"$listed" | cut -d: -f1)" -lt "$(grep -n '2026-01-01' <<<"$listed" | cut -d: -f1)" ]] || return 1

	local last
	last="$(NO_COLOR=1 cmd_logs --last 2>&1)"
	[[ "$last" == *'newest content'* && "$last" != *'older'* ]]
)

test_logs_is_quiet_with_no_logs_and_rejects_bad_options() (
	DOTFILES_DIR="$TEST_HARNESS_ROOT/empty-repo"
	mkdir -p "$DOTFILES_DIR"
	[[ "$(NO_COLOR=1 cmd_logs 2>&1)" == *'No logs yet.'* ]] || return 1
	local rc=0
	cmd_logs --nonsense >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 64 ]]
)

expect_success 'doctor lists only components needing attention and exits nonzero' test_doctor_reports_only_what_needs_attention
expect_success 'doctor exits zero when everything is healthy' test_doctor_succeeds_when_everything_is_healthy
expect_success 'update --dry-run reports then stops before any downstream work' test_update_dry_run_reports_then_stops
expect_success 'update without --dry-run still confirms and runs downstream' test_update_without_dry_run_still_prompts_and_runs
expect_success 'logs lists newest first and --last prints the newest' test_logs_lists_newest_first_and_prints_the_last
expect_success 'logs is quiet when empty and rejects unknown options' test_logs_is_quiet_with_no_logs_and_rejects_bad_options

test_harness_cleanup
finish_tests
