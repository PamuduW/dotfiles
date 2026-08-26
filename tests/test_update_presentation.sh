#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2178,SC2313
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/update_test_fixture.sh"

test_update_report_uses_clear_title_spacing_and_aligned_action_rule() (
	local output_file="$TEST_HARNESS_ROOT/update-report.output"
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|current'; }
	NO_COLOR=1 print_report_table >"$output_file"
	[[ "$(sed -n '1p' "$output_file")" == '==Update report==' ]] || return 1
	grep -Fq $'==Update report==\n\ncomponent' "$output_file" || return 1
	! grep -Fq 'Upgrade report' "$output_file" || return 1
	grep -Fq $'0 verified upgrades — everything verified current.\n\n' "$output_file" || return 1
	grep -Eq '^-------------------\+------------------------------\+------------------------\+-----------------' "$output_file"
)

test_update_and_upgrade_rows_keep_the_last_column_width() (
	local output line_lengths
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|current'; }

	line_lengths="$(NO_COLOR=1 print_report_table | awk '/^(component|apt packages|---)/ { print length($0) }')"
	[[ "$line_lengths" == $'93\n93\n93' ]] || return 1

	line_lengths="$(NO_COLOR=1 print_upgrade_summary | awk '/^(component|apt packages|---)/ { print length($0) }')"
	[[ "$line_lengths" == $'93\n93\n93' ]]
)

test_mixed_preview_separates_verified_upgrades_from_remaining_checks() (
	_collect_check_rows() {
		printf '%s\n' \
			'apt packages|system packages|none (cached)|refresh-required' \
			'Graphify CLI|graphify 0.9.50|—|unknown' \
			'Boost CLI|boost v0.12.6|—|unknown' \
			'Cursor CLI|2026.08.11-e8db854|—|unknown' \
			'Claude CLI|2.1.233|—|unknown' \
			'Copilot CLI|1.0.80|—|unknown' \
			'Codex CLI|0.149.1|0.149.1|current'
	}
	local output
	output="$(NO_COLOR=1 print_report_table)"
	grep -Fq '0 verified upgrades; 6 checks or refreshes remain.' <<<"$output" || return 1
	! grep -Fq 'everything looks current' <<<"$output" || return 1
	grep -Fq 'refresh on apply' <<<"$output" || return 1
	grep -Fq 'latest unchecked' <<<"$output"
)

test_upgrade_summary_counts_semantic_results_and_not_run_steps() (
	_collect_check_rows() {
		printf '%s\n' \
			'apt packages|system packages|none|current' \
			'Cursor CLI|installed|—|unknown' \
			'Codex CLI|installed|1.0.0|upgrade' \
			'Claude CLI|not installed|—|skip' \
			'npm|12.0.2|12.0.2|current' \
			'Go (asdf)|1.27.0|1.27.0|current' \
			'dotfiles repo|main@abc123|none|current'
	}
	UPGRADE_STEP_RESULT=(
		['apt packages']=checked-no-change
		['Cursor CLI']=recovered
		['Codex CLI']=updated
		['Claude CLI']=skipped
		['npm']=already-current
		['Go (asdf)']=failed
	)
	local output
	output="$(NO_COLOR=1 print_upgrade_summary)"
	grep -Fq 'checked/no change' <<<"$output" || return 1
	grep -Fq 'already current' <<<"$output" || return 1
	grep -Fq 'not run' <<<"$output" || return 1
	grep -Fq '1 updated; 1 already current; 2 checked/no change; 1 recovered; 1 skipped; 1 failed; 0 not run.' <<<"$output"
)

test_upgrade_summary_marks_unattempted_steps_after_early_failure() (
	_collect_check_rows() {
		printf '%s\n' \
			'apt packages|system packages|none|refresh-required' \
			'Cursor CLI|installed|—|unknown' \
			'dotfiles repo|main@abc123|none|current'
	}
	UPGRADE_STEP_RESULT=(['apt packages']=failed)
	local output
	output="$(NO_COLOR=1 print_upgrade_summary)"
	grep -Eq '^Cursor CLI[[:space:]]+\|.*\|[[:space:]]+not run[[:space:]]*$' <<<"$output" || return 1
	grep -Fq '0 updated; 0 already current; 1 checked/no change; 0 recovered; 0 skipped; 1 failed; 1 not run.' <<<"$output"
)

test_upgrade_summary_reports_all_current_and_all_skipped_without_ok_collapse() (
	_collect_check_rows() {
		printf '%s\n' \
			'apt packages|system packages|none|current' \
			'Cursor CLI|installed|—|unknown' \
			'dotfiles repo|main@abc123|none|current'
	}
	local output
	UPGRADE_STEP_RESULT=(['apt packages']=already-current ['Cursor CLI']=already-current)
	output="$(NO_COLOR=1 print_upgrade_summary)"
	grep -Fq '0 updated; 2 already current; 1 checked/no change; 0 recovered; 0 skipped; 0 failed; 0 not run.' <<<"$output" || return 1
	! grep -Fq 'step(s) ok' <<<"$output" || return 1

	UPGRADE_STEP_RESULT=(['apt packages']=skipped ['Cursor CLI']=skipped)
	output="$(NO_COLOR=1 print_upgrade_summary)"
	grep -Fq '0 updated; 0 already current; 1 checked/no change; 0 recovered; 2 skipped; 0 failed; 0 not run.' <<<"$output"
)

test_parallel_probe_preserves_nonempty_output_from_nonzero_probe() (
	_nonzero_probe() {
		printf '%s\n' 'apt packages|system packages|none|up to date'
		return 1
	}
	local output
	output="$(run_probes_parallel 'fallback' _nonzero_probe)"
	[[ "$output" == 'apt packages|system packages|none|up to date' ]]
)

test_update_report_ignores_empty_probe_rows() (
	_collect_check_rows() {
		printf '\n%s\n' 'apt packages|system packages|none|up to date'
	}
	local output
	output="$(NO_COLOR=1 print_report_table)"
	[[ "$(grep -c '^apt packages' <<<"$output")" -eq 1 ]] || return 1
	! grep -Eq '^[[:space:]]+\|[[:space:]]+\|[[:space:]]+\|' <<<"$output"
)

test_upgrade_summary_ignores_empty_probe_rows() (
	_collect_check_rows() {
		printf '\n%s\n' 'apt packages|system packages|none|up to date'
	}
	local output
	output="$(NO_COLOR=1 print_upgrade_summary)" || return 1
	[[ "$(grep -c '^apt packages' <<<"$output")" -eq 1 ]] || return 1
	! grep -Eq '^[[:space:]]+\|[[:space:]]+\|[[:space:]]+\|' <<<"$output"
)

test_update_rows_align_unicode_available_cells() (
	local output
	_collect_check_rows() { printf '%s\n' 'Cursor CLI|2026.07.09-a3815c0|—|up to date'; }
	output="$(NO_COLOR=1 print_report_table)"
	awk '
	/^Cursor CLI/ {
		pipes=""
		for (i = 1; i <= length($0); i++) if (substr($0, i, 1) == "|") pipes = pipes i ","
		if (length($0) != 93 || pipes != "20,51,76,") exit 1
		found=1
	}
	END { exit(found ? 0 : 1) }
	' <<<"$output"
)

test_repository_update_preview_uses_semantic_colors() (
	local output prompt
	local -A result=(
		[dir]="$DOTFILES_DIR" [label]='dotfiles repo' [state]=behind
		[ahead]=0 [behind]=2 [dirty]=0 [changes]='' [upstream]=origin/main
		[reason]='' [safe]=1 [approved]=0 [outcome]=stopped
	)
	C_BOLD=$'\033[1m' C_CYAN=$'\033[36m' C_ORANGE=$'\033[38;5;208m' C_DIM=$'\033[2m' C_YELLOW=$'\033[33m' C_RESET=$'\033[0m'
	output="$(repo_update_print_result result)"
	grep -Fq $'\033[1m\033[33mRepository update\033[0m' <<<"$output" || return 1
	! grep -Fq '==Repository update==' <<<"$output" || return 1
	grep -Fq $'\033[1mcomponent' <<<"$output" || return 1
	grep -Fq $'\033[2m-------------------+' <<<"$output" || return 1
	grep -Fq $'\033[33m2 commit(s) behind' <<<"$output" || return 1
	grep -Fq $'\033[36mpull --ff-only' <<<"$output" || return 1

	if prompt="$(printf 'n\n' | _dotfiles_confirm 'Pull 2 commit(s) with --ff-only?')"; then
		return 1
	fi
	grep -Fq $'\033[33mPull 2 commit(s) with --ff-only?' <<<"$prompt"
)

test_update_topics_use_submenu_yellow() (
	local output
	C_BOLD=$'\033[1m' C_CYAN=$'\033[36m' C_ORANGE=$'\033[38;5;208m' C_YELLOW=$'\033[33m' C_RESET=$'\033[0m'
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|up to date'; }
	output="$(print_report_table)" 2>/dev/null || true
	grep -Fq $'\033[33m==Update report==' <<<"$output" || return 1

	_upgrade_topic_probe() { :; }
	output="$(_run_upgrade_step lazygit 'dotfiles update' _upgrade_topic_probe)"
	grep -Fq $'\033[33m== lazygit ==' <<<"$output" || return 1

	repo_update_run() {
		local -n result_ref="$4"
		result_ref=([outcome]=current)
	}
	print_report_table() { :; }
	_dotfiles_confirm() { return 0; }
	_run_update_downstream() { :; }
	print_upgrade_summary() { :; }
	output="$(cmd_update)"
	grep -Fq $'\033[38;5;208m=== Upgrade ===' <<<"$output"
)

test_repository_fetch_notice_uses_cyan() (
	local output
	local -A result=()
	C_CYAN=$'\033[36m' C_RESET=$'\033[0m'
	TEST_REPO_STATE=fetch-output
	export TEST_REPO_STATE
	output="$(repo_update_run "$TEST_HARNESS_ROOT/repo" 'dotfiles repo' confirm_state result 2>&1)" || return 1
	grep -Fq $'\033[36mFrom github.com:PamuduW/dotfiles' <<<"$output"
)

test_repository_fetch_notice_colors_each_line() (
	local output
	C_CYAN=$'\033[36m' C_RESET=$'\033[0m'
	output="$(_repo_update_print_fetch_output $'From github.com:PamuduW/dotfiles\n   42abceb..9a0f501  main -> origin/main')"
	[[ "$output" == *$'\033[36mFrom github.com:PamuduW/dotfiles\033[0m'* ]] || return 1
	[[ "$output" == *$'\033[36m   42abceb..9a0f501  main -> origin/main\033[0m'* ]]
)

test_update_apply_uses_high_level_upgrade_heading_without_opt_in_plan() (
	local output
	repo_update_run() {
		local -n result_ref="$4"
		result_ref=([outcome]=current)
	}
	print_report_table() { :; }
	_dotfiles_confirm() { return 0; }
	_run_update_downstream() { printf '%s\n' '== apt packages =='; }
	print_upgrade_summary() { :; }
	output="$(cmd_update)"
	grep -Fq '=== Upgrade ===' <<<"$output" || return 1
	grep -Fq '== apt packages ==' <<<"$output" || return 1
	! grep -Fq 'Opt-in plan:' <<<"$output"
)

test_upgrade_summary_marks_repo_gate_as_handled() (
	_collect_check_rows() { printf '%s\n' 'dotfiles repo|main@abc123|none|current'; }
	local output
	output="$(print_upgrade_summary)"
	grep -Fq 'dotfiles repo' <<<"$output" || return 1
	grep -Fq 'checked/no change' <<<"$output"
)

test_tui_runs_shared_update_without_submenu() (
	local fake_dotfiles="$TEST_HARNESS_ROOT/fake-dotfiles"
	local events="$TEST_HARNESS_ROOT/tui-update.events"
	cat >"$fake_dotfiles" <<'FAKE'
#!/usr/bin/env bash
printf 'dotfiles:%s\n' "$*" >>"${TEST_TUI_EVENTS:?}"
exit "${TEST_DOTFILES_RC:-0}"
FAKE
	chmod 700 "$fake_dotfiles"
	export TEST_TUI_EVENTS="$events"
	: >"$events"
	resolve_dotfiles_cmd() { printf '%s\n' "$fake_dotfiles"; }
	ui_print_header() { printf 'header:%s|%s\n' "$1" "$2" >>"$events"; }

	run_update_flow || return 1
	[[ "$(sed -n '1p' "$events")" == 'dotfiles:update' && "$(wc -l <"$events")" -eq 1 ]] || return 1
	! grep -Fq 'header:Update|Dotfiles › Update' "$events" || return 1
	! declare -F update_menu >/dev/null 2>&1
)

test_tui_propagates_changed_repository_from_update_child() (
	local fake_dotfiles="$TEST_HARNESS_ROOT/fake-changed-dotfiles"
	local tty_output="$TEST_HARNESS_ROOT/changed-update.tty"
	cat >"$fake_dotfiles" <<'FAKE'
#!/usr/bin/env bash
exit 2
FAKE
	chmod 700 "$fake_dotfiles"
	export DOTFILES_TTY_PATH="$tty_output"
	resolve_dotfiles_cmd() { printf '%s\n' "$fake_dotfiles"; }
	ui_print_header() { :; }
	set +e
	run_update_flow
	local rc=$?
	set -e
	[[ "$rc" -eq 2 ]]
)

test_stopped_paths_have_no_downstream() {
	test_harness_reset_logs
	run_gate dirty yes
	! grep -Eq $'^(apt-get|sudo|stow|curl|npx)\t' "$TEST_COMMAND_LOG"
}

test_status_is_strictly_local() {
	local output="$TEST_HARNESS_ROOT/status.out"
	test_harness_reset_logs
	TEST_REPO_STATE=current "$REPO_DIR/bin/bin/dotfiles" status >"$output"
	grep -Fqi unchecked "$output" || return 1
	! grep -Eq $'git\t.*\t(fetch|pull|ls-remote)(\t|$)|^(curl|npx|sudo|stow|apt-get)\t' "$TEST_COMMAND_LOG"
}

test_root_tui_status_omits_unchecked_freshness_without_network() (
	local output="$TEST_HARNESS_ROOT/root-status.output"
	export DOTFILES_STATUS_OUTPUT="$output"
	COMP_KEYS=(sample)
	COMP_LABELS=('Sample')
	menu_tty_cols() { printf '80\n'; }
	ui_clear() { :; }
	ui_print_header() { printf 'header:%s|%s\n' "$1" "$2"; }
	rt_print_table_columns() { printf 'columns\n'; }
	comp_probe() { printf 'installed|present\n'; }
	_install_short_label() { printf '%s\n' "$1"; }
	rt_print_table_row() { printf 'row:%s|%s|%s\n' "$1" "$2" "$3"; }
	rt_print_rollup() { printf 'rollup:%s|%s|%s\n' "$1" "$2" "$3"; }
	test_harness_reset_logs
	run_status_action || return 1
	! grep -Fqi 'apt/package freshness: unchecked' "$output" || return 1
	! grep -Fqi 'repository freshness: unchecked' "$output" || return 1
	[[ ! -s "$TEST_COMMAND_LOG" && ! -s "$TEST_URL_LOG" ]]
)

test_root_status_rollup_has_one_blank_line() (
	local output="$TEST_HARNESS_ROOT/root-status-rollup.output"
	export DOTFILES_STATUS_OUTPUT="$output"
	COMP_KEYS=(sample)
	COMP_LABELS=('Sample')
	menu_tty_cols() { printf '80\n'; }
	ui_clear() { :; }
	ui_print_header() { printf 'header:%s|%s\n' "$1" "$2"; }
	comp_probe() { printf 'installed|present\n'; }
	_install_short_label() { printf '%s\n' "$1"; }
	NO_COLOR=1 run_status_action || return 1

	awk '
	/All 1 component\(s\) look good\./ {
		if (previous != "" || before_previous == "") exit 1
		found=1
	}
	{ before_previous=previous; previous=$0 }
	END { exit(found ? 0 : 1) }
	' "$output"
)

test_cli_and_tui_status_share_component_collector() (
	local calls="$TEST_HARNESS_ROOT/status-collector.calls"
	local cli_output="$TEST_HARNESS_ROOT/cli-status.output"
	local tui_output="$TEST_HARNESS_ROOT/tui-status.output"
	: >"$calls"
	collect_component_status_rows() {
		local -n output_rows="$1"
		output_rows=('Shared component|same collected detail|installed')
		printf 'collect\n' >>"$calls"
	}
	menu_tty_cols() { printf '80\n'; }
	ui_clear() { :; }
	ui_print_header() { rt_print_header "$1" "$2"; }
	DOTFILES_STATUS_OUTPUT="$tui_output" run_status_action
	NO_COLOR=1 cmd_status >"$cli_output"
	[[ "$(wc -l <"$calls")" -eq 2 ]] || return 1
	grep -Fq 'Shared component' "$tui_output" || return 1
	grep -Fq 'same collected detail' "$cli_output"
)

test_retained_capability_coverage() {
	declare -F cmd_status >/dev/null 2>&1 || return 1
	declare -F cmd_update >/dev/null 2>&1 || return 1
	declare -F cmd_restow >/dev/null 2>&1
}

test_removed_commands_have_guidance() {
	local cmd output rc
	for cmd in summary upgrade self; do
		set +e
		output="$("$REPO_DIR/bin/bin/dotfiles" "$cmd" 2>&1)"
		rc=$?
		set -e
		[[ "$rc" -ne 0 ]] || return 1
		case "$cmd" in summary) [[ "$output" == *'use dotfiles status'* ]] ;; upgrade) [[ "$output" == *'use dotfiles update [--all]'* ]] ;; self) [[ "$output" == *'use dotfiles update'* && "$output" == *restow* ]] ;; esac || return 1
	done
}

test_exact_command_set_parity() {
	source "$REPO_DIR/scripts/lib/command_metadata.sh"
	local expected=(menu update full-update doctor status commands packages logs restow help) i
	[[ "${#DOTFILES_COMMAND_KEYS[@]}" -eq 10 ]] || return 1
	for i in "${!expected[@]}"; do [[ "${DOTFILES_COMMAND_KEYS[$i]}" == "${expected[$i]}" ]] || return 1; done
	dotfiles_command_metadata_validate
}

test_harness_safety_and_no_real_mutation() {
	[[ "$(command -v git)" == "$TEST_FAKE_BIN/git" && ! -e "$TEST_FAKE_BIN/exec" ]] || return 1
	[[ "$HOME" == "$TEST_HARNESS_ROOT/home" && ! -s "$TEST_URL_LOG" ]]
}

expect_success 'update report title spacing and action separator are stable' test_update_report_uses_clear_title_spacing_and_aligned_action_rule
expect_success 'update and upgrade rows preserve the fixed final column width' test_update_and_upgrade_rows_keep_the_last_column_width
expect_success 'mixed preview separates verified upgrades from remaining checks' test_mixed_preview_separates_verified_upgrades_from_remaining_checks
expect_success 'upgrade summary counts semantic results' test_upgrade_summary_counts_semantic_results_and_not_run_steps
expect_success 'upgrade summary marks unattempted steps after early failure' test_upgrade_summary_marks_unattempted_steps_after_early_failure
expect_success 'upgrade summary preserves all-current and all-skipped states' test_upgrade_summary_reports_all_current_and_all_skipped_without_ok_collapse
expect_success 'parallel probes preserve nonempty output from nonzero checks' test_parallel_probe_preserves_nonempty_output_from_nonzero_probe
expect_success 'update report ignores empty probe rows' test_update_report_ignores_empty_probe_rows
expect_success 'upgrade summary ignores empty probe rows' test_upgrade_summary_ignores_empty_probe_rows
expect_success 'update rows align a Unicode em-dash available cell' test_update_rows_align_unicode_available_cells
expect_success 'repository update preview uses semantic colors' test_repository_update_preview_uses_semantic_colors
expect_success 'update subtopics use the report yellow palette' test_update_topics_use_submenu_yellow
expect_success 'repository fetch notices use cyan' test_repository_fetch_notice_uses_cyan
expect_success 'repository fetch notices color each line independently' test_repository_fetch_notice_colors_each_line
expect_success 'update apply uses a high-level Upgrade heading without opt-in plan noise' test_update_apply_uses_high_level_upgrade_heading_without_opt_in_plan
expect_success 'upgrade summary marks the repo gate as handled' test_upgrade_summary_marks_repo_gate_as_handled
expect_success 'TUI runs shared update directly without a submenu' test_tui_runs_shared_update_without_submenu
expect_success 'TUI propagates the changed-repository exit from the update child' test_tui_propagates_changed_repository_from_update_child
expect_success 'stopped paths perform no apt tool network or stow work' test_stopped_paths_have_no_downstream
expect_success 'dotfiles status is strictly local and labels freshness unchecked' test_status_is_strictly_local
expect_success 'root TUI status omits unchecked apt and repository freshness locally' test_root_tui_status_omits_unchecked_freshness_without_network
expect_success 'root status rollup has exactly one blank line before the summary' test_root_status_rollup_has_one_blank_line
expect_success 'CLI and TUI status use the same component-state collector' test_cli_and_tui_status_share_component_collector
expect_success 'status update and restow retain removed command capabilities' test_retained_capability_coverage
expect_success 'summary upgrade and self fail with migration guidance' test_removed_commands_have_guidance
expect_success 'metadata help Command Lib and dispatch share ten keys' test_exact_command_set_parity
expect_success 'harness fakes prevent real repo network apt home and stow mutation' test_harness_safety_and_no_real_mutation

finish_tests
