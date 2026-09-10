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
	[[ "$(sed -n '1p' "$output_file")" == '== Update report ==' ]] || return 1
	grep -Fq $'== Update report ==\n\ncomponent' "$output_file" || return 1
	! grep -Fq 'Upgrade report' "$output_file" || return 1
	grep -Fq $'0 verified upgrades — everything verified current.\n\n' "$output_file" || return 1
	awk 'NR == 4 { expected=$0; next } NR == 5 { exit(length($0) == length(expected) ? 0 : 1) }' "$output_file"
)

test_report_title_honours_no_color_even_with_a_palette_loaded() (
	# Every rt_* helper settles the palette before drawing, but the report title
	# printed before the first one ran, so it read $C_BOLD/$C_YELLOW directly.
	#
	# The other tests in this file cannot catch that: none of them loads a
	# palette, so the tokens are empty and NO_COLOR appears to work. Colour
	# leaked only when a caller had installed a palette -- and then just the
	# title was coloured while the table underneath came out plain.
	local output
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|current'; }
	colors_set_palette
	output="$(NO_COLOR=1 print_report_table)"
	[[ "$output" != *$'\033'* ]] || return 1
	[[ "$output" == *'== Update report =='* ]]
)

test_report_title_still_colours_when_colour_is_wanted() (
	# The guard must settle the palette, not disable colour outright.
	local output
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|current'; }
	output="$(
		unset NO_COLOR
		FORCE_COLOR=1 print_report_table
	)"
	[[ "$output" == *$'\033'* ]]
)

# The display width of every table row and rule, one per line.
_report_row_widths() {
	local line
	while IFS= read -r line; do
		[[ "$line" == *'|'* || "$line" == -* ]] || continue
		display_width "$line"
		printf '\n'
	done
}

test_update_and_upgrade_rows_keep_the_last_column_width() (
	local output line_lengths cols
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|current'; }
	# Measured in bash, not awk: these rows carry an em-dash, and mawk -- which
	# is `awk` on a stock Ubuntu, including the CI runner -- counts its three
	# bytes as three columns. bash counts characters in a UTF-8 locale, which
	# tests/lib/harness.sh settles.
	local -a widths=()
	for cols in 48 80 120; do
		mapfile -t widths < <(DOTFILES_REPORT_COLS="$cols" NO_COLOR=1 print_report_table |
			_report_row_widths)
		[[ "${widths[*]}" == "$cols $cols $cols" ]] || return 1
		mapfile -t widths < <(DOTFILES_REPORT_COLS="$cols" NO_COLOR=1 print_upgrade_summary |
			_report_row_widths)
		[[ "${widths[*]}" == "$cols $cols $cols" ]] || return 1
	done
)

test_mixed_preview_separates_verified_upgrades_from_remaining_checks() (
	_collect_check_rows() {
		printf '%s\n' \
			'apt packages|system packages|none (cached)|refresh-required' \
			'Graphify CLI|graphify 0.9.50|—|unknown' \
			'Boost CLI|boost v0.12.6|—|unknown' \
			'Cursor CLI|2026.08.11-e8db854|—|unknown' \
			'Claude CLI|2.1.233|—|unknown' \
			'Codex CLI|codex-cli 0.149.1|0.149.1|current'
	}
	local output
	output="$(NO_COLOR=1 print_report_table)"
	grep -Fq '0 verified upgrades; 5 checks or refreshes remain.' <<<"$output" || return 1
	! grep -Fq 'everything looks current' <<<"$output" || return 1
	grep -Fq 'refresh on apply' <<<"$output" || return 1
	grep -Fq 'latest unchecked' <<<"$output"
)

test_codex_preview_renders_external_and_unchecked_states() (
	_collect_check_rows() {
		printf '%s\n' \
			'Codex CLI|external installation|—|external' \
			'Codex CLI shadow fixture|standalone shadowed|—|external' \
			'Codex CLI metadata fixture|codex-cli 0.150.0|—|unknown'
	}
	local output
	output="$(NO_COLOR=1 print_report_table)"
	[[ "$(grep -c 'externally managed[[:space:]]*$' <<<"$output")" -eq 2 ]] || return 1
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
	local output line index pipes found=false
	_collect_check_rows() { printf '%s\n' 'Cursor CLI|2026.07.09-a3815c0|—|up to date'; }
	# The width is pinned, because the expectations below are absolute. Without
	# this the table takes its width from the environment's COLUMNS, which is
	# unset in a local shell and set on a CI runner -- the whole reason this
	# suite passed here and failed there for months.
	output="$(DOTFILES_REPORT_COLS=80 NO_COLOR=1 print_report_table)"
	# The em-dash occupies one column and three bytes, which is the whole point
	# of this case: measured in bash under a UTF-8 locale, never in awk.
	while IFS= read -r line; do
		[[ "$line" == 'Cursor CLI'* ]] || continue
		(($(display_width "$line") == 80)) || return 1
		line="${line//—/-}"
		pipes=''
		for ((index = 0; index < ${#line}; index++)); do
			[[ "${line:index:1}" == '|' ]] && pipes+="$((index + 1)),"
		done
		[[ "$pipes" == '15,40,61,' ]] || return 1
		found=true
	done <<<"$output"
	[[ "$found" == true ]]
)

test_repository_update_preview_uses_semantic_colors() (
	local output prompt
	unset NO_COLOR
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

	# The prompt is written to the terminal, not stdout: stdout is teed into the
	# action log, and under a piped bootstrap stdin is not the operator at all.
	local tty_in="$TEST_HARNESS_ROOT/confirm-in" tty_out="$TEST_HARNESS_ROOT/confirm-out"
	printf 'n\n' >"$tty_in"
	: >"$tty_out"
	if DOTFILES_TTY_INPUT="$tty_in" DOTFILES_TTY_OUTPUT="$tty_out" \
		_dotfiles_confirm 'Pull 2 commit(s) with --ff-only?' </dev/null; then
		return 1
	fi
	prompt="$(<"$tty_out")"
	grep -Fq $'\033[33mPull 2 commit(s) with --ff-only?' <<<"$prompt"
)

test_update_topics_use_submenu_yellow() (
	local output
	unset NO_COLOR
	C_BOLD=$'\033[1m' C_CYAN=$'\033[36m' C_ORANGE=$'\033[38;5;208m' C_YELLOW=$'\033[33m' C_RESET=$'\033[0m'
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|up to date'; }
	output="$(print_report_table)" 2>/dev/null || true
	grep -Fq $'\033[33m== Update report ==' <<<"$output" || return 1

	# A component step is the install screen's rule plus a cyan [STEP] line, not
	# a yellow heading of its own; a probe that says nothing still gets a
	# closing outcome line rather than a heading with nothing under it.
	_upgrade_topic_probe() { :; }
	output="$(DOTFILES_NO_PROGRESS_ANIMATION=1 _run_upgrade_step lazygit 'dotfiles update' _upgrade_topic_probe)"
	# -e, because the rule starts with a dash and grep would read it as options.
	grep -Fq -e '----------------------------------------' <<<"$output" || return 1
	grep -Fq $'\033[36m[STEP]\033[0m lazygit' <<<"$output" || return 1
	grep -Fq 'lazygit checked' <<<"$output" || return 1

	repo_update_run() {
		local -n result_ref="$4"
		result_ref=([outcome]=current)
	}
	print_report_table() { :; }
	_dotfiles_confirm() { return 0; }
	_run_update_downstream() { :; }
	print_upgrade_summary() { :; }
	sudo_prime() { :; }
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
	_run_update_downstream() { printf '%s\n' '[STEP] apt packages'; }
	print_upgrade_summary() { :; }
	sudo_prime() { :; }
	output="$(cmd_update)"
	grep -Fq '=== Upgrade ===' <<<"$output" || return 1
	grep -Fq '[STEP] apt packages' <<<"$output" || return 1
	! grep -Fq 'Opt-in plan:' <<<"$output"
)

test_upgrade_summary_marks_repo_gate_as_handled() (
	_collect_check_rows() { printf '%s\n' 'dotfiles repo|main@abc123|none|current'; }
	local output
	output="$(print_upgrade_summary)"
	grep -Fq 'dotfiles repo' <<<"$output" || return 1
	grep -Fq 'checked/no change' <<<"$output"
)

test_update_preview_and_summary_share_one_snapshot() (
	local calls="$TEST_HARNESS_ROOT/update-snapshot.calls"
	: >"$calls"
	repo_update_run() {
		local -n result_ref="$4"
		result_ref=([outcome]=current [state]=current)
	}
	_collect_check_rows() {
		printf 'collect\n' >>"$calls"
		printf '%s\n' 'apt packages|system packages|none (cached)|refresh-required' 'dotfiles repo|main@abc123|none|current'
	}
	_dotfiles_confirm() { return 0; }
	_run_update_downstream() {
		UPGRADE_STEP_RESULT=(['apt packages']=checked-no-change)
	}

	NO_COLOR=1 _dotfiles_run_update _dotfiles_confirm_repo_update false >/dev/null || return 1
	[[ "$(wc -l <"$calls")" -eq 1 ]]
)

test_update_step_registry_has_stable_complete_pairs() (
	local expected=(
		'apt packages' 'Graphify CLI' 'Boost CLI' 'Cursor CLI' 'Codex CLI'
		'Claude CLI' lazygit lazydocker 'Node.js (nvm)' npm
		'Go (asdf)' 'Monaspace fonts' 'dotfiles repo'
	)
	update_step_registry_validate || return 1
	[[ "${#UPDATE_STEP_KEYS[@]}" -eq "${#expected[@]}" ]] || return 1
	local i key
	for i in "${!expected[@]}"; do
		key="${UPDATE_STEP_KEYS[$i]}"
		[[ "${UPDATE_STEP_LABEL[$key]}" == "${expected[$i]}" ]] || return 1
		declare -F "${UPDATE_STEP_CHECK[$key]}" >/dev/null || return 1
		declare -F "${UPDATE_STEP_APPLY[$key]}" >/dev/null || return 1
	done
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
	# Status reports the repository's position now, and still qualifies it: the
	# counts are as fresh as the last fetch and it says so. What must not change
	# is the line below -- no fetch, no pull, no ls-remote, no network.
	grep -Eqi 'as of last fetch|unchecked' "$output" || return 1
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
expect_success 'Codex preview renders external ownership and unchecked metadata truthfully' test_codex_preview_renders_external_and_unchecked_states
expect_success 'upgrade summary counts semantic results' test_upgrade_summary_counts_semantic_results_and_not_run_steps
expect_success 'upgrade summary marks unattempted steps after early failure' test_upgrade_summary_marks_unattempted_steps_after_early_failure
expect_success 'upgrade summary preserves all-current and all-skipped states' test_upgrade_summary_reports_all_current_and_all_skipped_without_ok_collapse
expect_success 'parallel probes preserve nonempty output from nonzero checks' test_parallel_probe_preserves_nonempty_output_from_nonzero_probe
expect_success 'update report ignores empty probe rows' test_update_report_ignores_empty_probe_rows
expect_success 'upgrade summary ignores empty probe rows' test_upgrade_summary_ignores_empty_probe_rows
expect_success 'update rows align a Unicode em-dash available cell' test_update_rows_align_unicode_available_cells
expect_success 'repository update preview uses semantic colors' test_repository_update_preview_uses_semantic_colors
expect_success 'update headings and step lines use their own palettes' test_update_topics_use_submenu_yellow
expect_success 'repository fetch notices use cyan' test_repository_fetch_notice_uses_cyan
expect_success 'repository fetch notices color each line independently' test_repository_fetch_notice_colors_each_line
expect_success 'update apply uses a high-level Upgrade heading without opt-in plan noise' test_update_apply_uses_high_level_upgrade_heading_without_opt_in_plan
expect_success 'upgrade summary marks the repo gate as handled' test_upgrade_summary_marks_repo_gate_as_handled
expect_success 'update preview and summary share one captured snapshot' test_update_preview_and_summary_share_one_snapshot
expect_success 'update registry has stable complete check and apply pairs' test_update_step_registry_has_stable_complete_pairs
expect_success 'TUI runs shared update directly without a submenu' test_tui_runs_shared_update_without_submenu
expect_success 'TUI propagates the changed-repository exit from the update child' test_tui_propagates_changed_repository_from_update_child
expect_success 'stopped paths perform no apt tool network or stow work' test_stopped_paths_have_no_downstream
expect_success 'dotfiles status is strictly local and labels freshness unchecked' test_status_is_strictly_local
expect_success 'root TUI status omits unchecked apt and repository freshness locally' test_root_tui_status_omits_unchecked_freshness_without_network
test_bash_and_python_rollups_count_alike() (
	# A row drawn green and counted as needing attention is a report arguing
	# with itself. The Python counter was taught the whole result vocabulary
	# once; the Bash counters were not, and knew `installed` and `configured`
	# alone -- so `ok`, `linked`, `up to date`, `current`, `applied` and
	# `read-only` all counted as problems while being painted green beside it.
	#
	# Latent rather than live: only five states reach a counter today. This is
	# what makes a sixth safe to introduce.
	command -v python3 >/dev/null 2>&1 || return 0

	local rows="$TEST_HARNESS_ROOT/rollup-parity.rows" ok=0 miss=0 check=0 row result
	printf '%s\n' \
		'Alpha|x|ok' 'Bravo|x|installed' 'Charlie|x|configured' 'Delta|x|linked' \
		'Echo|x|up to date' 'Foxtrot|x|current' 'Golf|x|applied' 'Hotel|x|read-only' \
		'India|x|missing' 'Juliet|x|failed' 'Kilo|x|check' 'Lima|x|skipped' >"$rows"

	while IFS='|' read -r _ _ result; do
		case "$(status_result_class "$result")" in
		ok) ((++ok)) ;;
		miss) ((++miss)) ;;
		*) ((++check)) ;;
		esac
	done <"$rows"

	local from_bash from_python
	from_bash="$(NO_COLOR=1 rt_print_rollup "$ok" "$check" "$miss" | tail -1)"
	from_python="$(NO_COLOR=1 PYTHONDONTWRITEBYTECODE=1 python3 \
		"$REPO_DIR/scripts/lib/shared/python/render_report.py" --cols 80 --rollup <"$rows" | tail -1)"
	[[ "$from_bash" == "$from_python" ]] || {
		printf 'rollup counts differ:\n  bash:   %s\n  python: %s\n' \
			"$from_bash" "$from_python" >&2
		return 1
	}
)

expect_success 'root status rollup has exactly one blank line before the summary' test_root_status_rollup_has_one_blank_line
expect_success 'Bash and Python rollups count every state alike' test_bash_and_python_rollups_count_alike
expect_success 'CLI and TUI status use the same component-state collector' test_cli_and_tui_status_share_component_collector
expect_success 'status update and restow retain removed command capabilities' test_retained_capability_coverage
expect_success 'summary upgrade and self fail with migration guidance' test_removed_commands_have_guidance
expect_success 'metadata help Command Lib and dispatch share ten keys' test_exact_command_set_parity
expect_success 'report title honours NO_COLOR with a palette loaded' test_report_title_honours_no_color_even_with_a_palette_loaded
expect_success 'report title still colours when colour is wanted' test_report_title_still_colours_when_colour_is_wanted
expect_success 'harness fakes prevent real repo network apt home and stow mutation' test_harness_safety_and_no_real_mutation

finish_tests
