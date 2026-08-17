#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2178,SC2313
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/update_test_fixture.sh"

test_state_table_outcomes() {
	local pair state expected
	for pair in current:current dirty:stopped detached:stopped no-upstream:stopped other-remote:stopped wrong-origin:stopped diverged:stopped fetch-failure:stopped; do
		state="${pair%%:*}" expected="${pair#*:}"
		test_harness_reset_logs
		run_gate "$state" no
		if [[ "${TEST_REPO_RESULT[outcome]}" != "$expected" ]]; then
			printf 'state %s: expected %s, got %s (%s)\n' "$state" "$expected" "${TEST_REPO_RESULT[outcome]}" "${TEST_REPO_RESULT[reason]:-none}" >&2
			return 1
		fi
	done
}

test_dirty_history_matrix_fetches_classifies_and_stops() {
	local pair state expected
	for pair in dirty-current:current dirty-ahead:ahead dirty-behind:behind dirty-diverged:diverged; do
		state="${pair%%:*}" expected="${pair#*:}"
		test_harness_reset_logs
		run_gate "$state" yes
		[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "${TEST_REPO_RESULT[state]}" == "$expected" ]] || return 1
		[[ "${TEST_REPO_RESULT[reason]}" == dirty && "${TEST_REPO_RESULT[dirty]}" == 1 ]] || return 1
		[[ "${TEST_REPO_RESULT[changes]}" == *' M scripts/example.sh'* && "${TEST_REPO_RESULT[upstream]}" == origin/main ]] || return 1
		grep -Eq $'git\t-C\t.*\tfetch\t--prune$' "$TEST_COMMAND_LOG" || return 1
		grep -Eq $'git\t-C\t.*\trev-list\t--left-right\t--count\tHEAD\.\.\.@\{upstream\}$' "$TEST_COMMAND_LOG" || return 1
		[[ "$(pull_count)" -eq 0 ]] || return 1
	done
}

test_dirty_fetch_failure_preserves_changes_and_unknown_freshness() {
	test_harness_reset_logs
	TEST_REPO_STATE=dirty-current TEST_CONFIRM=yes TEST_FETCH_FAILURE=1
	export TEST_REPO_STATE TEST_CONFIRM TEST_FETCH_FAILURE
	TEST_REPO_RESULT=()
	repo_update_run "$TEST_HARNESS_ROOT/repo" 'dotfiles repo' confirm_state TEST_REPO_RESULT 'PamuduW/dotfiles' >/dev/null 2>&1 || true
	unset TEST_FETCH_FAILURE
	[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "${TEST_REPO_RESULT[reason]}" == fetch-failed ]] || return 1
	[[ "${TEST_REPO_RESULT[dirty]}" == 1 && "${TEST_REPO_RESULT[changes]}" == *'?? local-change'* ]] || return 1
	! grep -Eq $'git\t-C\t.*\trev-list\t' "$TEST_COMMAND_LOG"
}

test_status_failure_stops_before_fetch() {
	test_harness_reset_logs
	run_gate status-failure yes
	[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "${TEST_REPO_RESULT[reason]}" == status-failed ]] || return 1
	! grep -Eq $'git\t-C\t.*\t(fetch|rev-list|pull)(\t|$)' "$TEST_COMMAND_LOG"
}

test_git_sequence_captures_changes_before_fetch_and_classification() {
	test_harness_reset_logs
	run_gate dirty-behind yes
	local status_line fetch_line classify_line
	status_line="$(grep -n $'git\t-C\t.*\tstatus\t--short\t--untracked-files=all$' "$TEST_COMMAND_LOG" | cut -d: -f1)"
	fetch_line="$(grep -n $'git\t-C\t.*\tfetch\t--prune$' "$TEST_COMMAND_LOG" | cut -d: -f1)"
	classify_line="$(grep -n $'git\t-C\t.*\trev-list\t--left-right\t--count' "$TEST_COMMAND_LOG" | cut -d: -f1)"
	[[ -n "$status_line" && -n "$fetch_line" && -n "$classify_line" ]] || return 1
	((status_line < fetch_line && fetch_line < classify_line))
}

test_only_confirmed_behind_pulls() {
	test_harness_reset_logs
	run_gate behind no
	[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	test_harness_reset_logs
	run_gate behind yes
	[[ "${TEST_REPO_RESULT[outcome]}" == repository_changed && "$TEST_REPO_RC" -eq 2 && "$(pull_count)" -eq 1 ]]
}

test_blocked_states_never_pull() {
	local state
	for state in dirty detached no-upstream other-remote diverged fetch-failure; do
		test_harness_reset_logs
		run_gate "$state" yes
		[[ "$(pull_count)" -eq 0 ]] || return 1
	done
	test_harness_reset_logs
	run_gate pull-failure yes
	[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "$(pull_count)" -eq 1 ]]
}

test_non_origin_upstream_stops_before_fetch() {
	test_harness_reset_logs
	run_gate other-remote yes
	[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	! grep -Eq $'git\t-C\t.*\t(fetch|pull)(\t|$)' "$TEST_COMMAND_LOG"
}

test_untrusted_origin_stops_before_fetch() {
	test_harness_reset_logs
	run_gate wrong-origin yes
	[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "${TEST_REPO_RESULT[reason]}" == wrong-origin ]] || return 1
	! grep -Eq $'git\t-C\t.*\t(fetch|pull)(\t|$)' "$TEST_COMMAND_LOG"
}

test_ahead_requires_continue() {
	test_harness_reset_logs
	run_gate ahead no
	[[ "${TEST_REPO_RESULT[outcome]}" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	test_harness_reset_logs
	run_gate ahead yes
	[[ "${TEST_REPO_RESULT[outcome]}" == ahead_continue && "$(pull_count)" -eq 0 ]]
}

test_success_returns_changed_repository_without_old_work() {
	test_harness_reset_logs
	run_gate behind yes
	[[ "${TEST_REPO_RESULT[outcome]}" == repository_changed && "$TEST_REPO_RC" -eq 2 ]] || return 1
	! grep -Eq $'^(apt-get|sudo|stow|curl|npx)\t' "$TEST_COMMAND_LOG"
}

test_cmd_update_executes_outcome_contract() (
	local events="$TEST_HARNESS_ROOT/cmd-update.events" replies=''
	: >"$events"
	repo_update_run() {
		local -n result_ref="$4"
		printf 'gate\n' >>"$events"
		result_ref=([outcome]="${TEST_GATE_OUTCOME:?}")
		case "$TEST_GATE_OUTCOME" in
		stopped) return 1 ;;
		repository_changed) return 2 ;;
		esac
		return 0
	}
	_dotfiles_confirm() {
		local answer="${replies%% *}"
		[[ "$replies" == *' '* ]] && replies="${replies#* }" || replies=''
		printf 'confirm:%s\n' "$1" >>"$events"
		[[ "$answer" == yes ]]
	}
	print_report_table() { printf 'report\n' >>"$events"; }
	print_upgrade_summary() { printf 'summary:%s\n' "$1" >>"$events"; }
	_run_update_downstream() { printf 'downstream:%s\n' "$1" >>"$events"; }

	TEST_GATE_OUTCOME=stopped
	if cmd_update >/dev/null 2>&1; then return 1; fi
	[[ "$(<"$events")" == gate ]] || return 1

	: >"$events"
	TEST_GATE_OUTCOME=current
	replies=no
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == gate && "$(sed -n '2p' "$events")" == report && "$(sed -n '3p' "$events")" == confirm:* ]] || return 1

	: >"$events"
	TEST_GATE_OUTCOME=current
	replies='yes no'
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == gate && "$(sed -n '2p' "$events")" == report && "$(sed -n '3p' "$events")" == confirm:* && "$(sed -n '4p' "$events")" == confirm:* && "$(sed -n '5p' "$events")" == downstream:false && "$(sed -n '6p' "$events")" == summary:false ]] || return 1
	grep -Fqx 'confirm:Include Node.js, npm, Go, and Monaspace fonts (--all)?' "$events" || return 1

	: >"$events"
	TEST_GATE_OUTCOME=current
	replies='yes yes'
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '5p' "$events")" == downstream:true && "$(sed -n '6p' "$events")" == summary:true ]] || return 1

	: >"$events"
	TEST_GATE_OUTCOME=ahead_continue
	replies=yes
	cmd_update --all >/dev/null || return 1
	[[ "$(sed -n '3p' "$events")" == confirm:* && "$(sed -n '4p' "$events")" == downstream:true && "$(sed -n '5p' "$events")" == summary:true ]] || return 1

	: >"$events"
	TEST_GATE_OUTCOME=repository_changed
	replies=yes
	set +e
	local changed_output
	changed_output="$(cmd_update --all 2>&1)"
	local changed_rc=$?
	set -e
	[[ "$changed_rc" -eq 2 ]] || return 1
	[[ "$changed_output" == *'Repository fast-forward succeeded'* ]] || return 1
	[[ "$changed_output" == *'Run setup again when ready.'* ]] || return 1
	! grep -Fq "wait" "$events" || return 1
	! grep -Fq "relaunch" "$events" || return 1
	! grep -Fq downstream "$events"
)

test_cmd_update_declined_pull_is_handled_without_failure() (
	local events="$TEST_HARNESS_ROOT/cmd-update-declined.events"
	: >"$events"
	repo_update_run() {
		local -n result_ref="$4"
		result_ref=([outcome]=stopped [reason]=behind-declined)
		printf 'gate\n' >>"$events"
		return 1
	}
	set +e
	cmd_update --all >/dev/null 2>&1
	local declined_rc=$?
	set -e
	[[ "$declined_rc" -eq 0 && "$(<"$events")" == gate ]]
)

test_cmd_update_reports_dirty_paths_and_remote_state_before_stopping() (
	repo_update_run() {
		local -n result_ref="$4"
		result_ref=(
			[dir]="$DOTFILES_DIR" [label]='dotfiles repo' [outcome]=stopped
			[reason]=dirty [state]=behind [ahead]=0 [behind]=3 [dirty]=1
			[upstream]=origin/main [changes]=$' M scripts/example.sh\n?? local-change'
		)
		repo_update_print_stopped "$4"
		return 1
	}
	local output rc
	set +e
	output="$(cmd_update 2>&1)"
	rc=$?
	set -e
	[[ "$rc" -ne 0 && "$output" == *'Repository update'* ]] || return 1
	[[ "$output" == *'2 local change(s)'* && "$output" == *'blocked'* ]] || return 1
	[[ "$output" == *'origin/main'* && "$output" == *'3 commit(s) behind'* ]] || return 1
	[[ "$output" == *' M scripts/example.sh'* && "$output" == *'?? local-change'* ]] || return 1
	[[ "$output" == *'Repository pull and downstream updates stopped.'* ]]
)

test_declined_repository_pull_prints_one_report_and_one_pause_boundary() (
	local output clean_output rc
	TEST_REPO_STATE=behind
	C_RED=$'\033[31m' C_RESET=$'\033[0m'
	export C_RED C_RESET
	export TEST_REPO_STATE
	set +e
	output="$(printf 'n\n' | cmd_update 2>&1)"
	rc=$?
	set -e
	clean_output="$(sed -E $'s/\033\\[[0-9;]*m//g' <<<"$output")"
	[[ "$rc" -eq 0 ]] || return 1
	[[ "$(grep -c '^Repository update$' <<<"$clean_output")" -eq 1 ]] || return 1
	[[ "$clean_output" == *'Pull 3 commit(s) with --ff-only? [y/N]: '*$'\n\n''Pull declined; update stopped.'* ]] || return 1
	[[ "$output" == *$'\033[31mPull declined; update stopped.\033[0m'* ]] || return 1
	[[ "$clean_output" != *'Repository pull and downstream updates stopped: behind.'* ]]
)

test_declined_install_repository_pull_uses_shared_failure_output() (
	local output clean_output rc output_file="$TEST_HARNESS_ROOT/declined-install.output"
	TEST_REPO_STATE=behind
	export TEST_REPO_STATE
	ui_confirm_yes_no() {
		printf '%s [y/N]: ' "$1"
		return 1
	}
	set +e
	_dotfiles_install_repo_gate >"$output_file" 2>&1
	rc=$?
	set -e
	output="$(<"$output_file")"
	clean_output="$(sed -E $'s/\033\\[[0-9;]*m//g' <<<"$output")"
	[[ "$rc" -eq 0 ]] || return 1
	[[ "$DOTFILES_REPOSITORY_UPDATE_DECLINED" == true ]] || return 1
	[[ "$(grep -c '^Repository update$' <<<"$clean_output")" -eq 1 ]] || return 1
	[[ "$clean_output" == *'Pull 3 commit(s) with --ff-only? [y/N]: '*$'\n\n''Pull declined; update stopped.'* ]] || return 1
	[[ "$clean_output" != *'Install stopped; the Dotfiles repository is not ready for setup.'* ]] || return 1
	[[ "$clean_output" != *'Repository pull and downstream updates stopped: behind.'* ]]
)

test_dirty_change_report_is_bounded_and_copyable() (
	local i output status_lines='' printed
	local -A result=([dir]="$DOTFILES_DIR")
	for i in $(seq 1 22); do status_lines+="?? path-${i}"$'\n'; done
	result[changes]="${status_lines%$'\n'}"
	output="$(repo_update_print_changes result)"
	printed="$(grep -c '^  ?? path-' <<<"$output")"
	[[ "$printed" -eq 20 && "$output" == *'... 2 more local change(s)'* ]] || return 1
	[[ "$output" == *'git -C '* && "$output" == *' status --short --untracked-files=all'* ]]
)

expect_success 'repository state table returns stable outcomes' test_state_table_outcomes
expect_success 'dirty current ahead behind and diverged states fetch classify and stop' test_dirty_history_matrix_fetches_classifies_and_stops
expect_success 'dirty fetch failure preserves paths and marks freshness unknown' test_dirty_fetch_failure_preserves_changes_and_unknown_freshness
expect_success 'failed local status probe stops before fetch' test_status_failure_stops_before_fetch
expect_success 'repository checks run status before fetch before classification' test_git_sequence_captures_changes_before_fetch_and_classification
expect_success 'only clean strictly-behind confirmed state pulls ff-only once' test_only_confirmed_behind_pulls
expect_success 'blocked declined and failed states never reach downstream' test_blocked_states_never_pull
expect_success 'non-origin upstream stops before fetch or pull' test_non_origin_upstream_stops_before_fetch
expect_success 'untrusted repository origin stops before fetch or pull' test_untrusted_origin_stops_before_fetch
expect_success 'ahead never pulls and requires explicit continue confirmation' test_ahead_requires_continue
expect_success 'successful pull reports a changed repository and stops old-process work' test_success_returns_changed_repository_without_old_work
expect_success 'cmd_update executes one repository update exit contract' test_cmd_update_executes_outcome_contract
expect_success 'cmd_update handles declined pulls without a failure status' test_cmd_update_declined_pull_is_handled_without_failure
expect_success 'cmd_update reports dirty paths and verified remote state before stopping' test_cmd_update_reports_dirty_paths_and_remote_state_before_stopping
expect_success 'declined repository pulls print one report before the pause boundary' test_declined_repository_pull_prints_one_report_and_one_pause_boundary
expect_success 'declined install pulls use shared failure output' test_declined_install_repository_pull_uses_shared_failure_output
expect_success 'dirty path report is bounded and includes a copyable full-list command' test_dirty_change_report_is_bounded_and_copyable

finish_tests
