#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

passed=0 failed=0
pass() { printf 'ok - %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; failed=$((failed + 1)); }
expect_success() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

install_state_git_fake() {
	rm -f "$TEST_FAKE_BIN/git"
	cat >"$TEST_FAKE_BIN/git" <<'FAKE'
#!/usr/bin/env bash
set -u
printf 'git' >>"${TEST_COMMAND_LOG:?}"
for arg in "$@"; do printf '\t%s' "$arg" >>"$TEST_COMMAND_LOG"; done
printf '\n' >>"$TEST_COMMAND_LOG"
args=("$@")
if [[ "${args[0]:-}" == -C ]]; then args=("${args[@]:2}"); fi
cmd="${args[*]}"
state="${TEST_REPO_STATE:-current}"
case "$cmd" in
  'rev-parse --is-inside-work-tree') printf 'true\n' ;;
  'rev-parse --is-bare-repository') printf 'false\n' ;;
  'remote get-url origin') [[ "$state" == no-origin ]] && exit 2; printf 'https://github.com/example/dotfiles.git\n' ;;
  'symbolic-ref -q --short HEAD') [[ "$state" == detached ]] && exit 1; printf 'main\n' ;;
  'rev-parse --abbrev-ref --symbolic-full-name @{upstream}')
    [[ "$state" == no-upstream ]] && exit 1
    [[ "$state" == other-remote ]] && { printf 'fork/main\n'; exit 0; }
    printf 'origin/main\n' ;;
  'status --porcelain --untracked-files=all') [[ "$state" == dirty ]] && printf '?? local-change\n' ;;
  'fetch --prune')
    if [[ "$state" == fetch-failure ]]; then printf 'fetch diagnostic\n' >&2; exit 23; fi
    exit 0 ;;
  'rev-list --left-right --count HEAD...@{upstream}')
    case "$state" in ahead) printf '2\t0\n' ;; behind|pull-failure) printf '0\t3\n' ;; diverged) printf '2\t3\n' ;; *) printf '0\t0\n' ;; esac ;;
  'pull --ff-only')
    if [[ "$state" == pull-failure ]]; then printf 'pull diagnostic\n' >&2; exit 24; fi
    exit 0 ;;
  'status -sb') printf '## main\n' ;;
  *) printf 'unexpected fake git call: %s\n' "$cmd" >&2; exit 97 ;;
esac
FAKE
	chmod 700 "$TEST_FAKE_BIN/git"
}

confirm_state() { [[ "${TEST_CONFIRM:-no}" == yes ]]; }
run_gate() { TEST_REPO_STATE="$1" TEST_CONFIRM="${2:-no}"; export TEST_REPO_STATE TEST_CONFIRM; repo_update_gate "$TEST_HARNESS_ROOT/repo" confirm_state >/dev/null 2>&1; }
pull_count() { grep -c $'git\t-C\t.*\tpull\t--ff-only$' "$TEST_COMMAND_LOG" || true; }

test_state_table_outcomes() {
	local pair state expected
	for pair in current:current dirty:stopped detached:stopped no-upstream:stopped other-remote:stopped diverged:stopped fetch-failure:stopped; do
		state="${pair%%:*}" expected="${pair#*:}"; test_harness_reset_logs; run_gate "$state" no
		[[ "$REPO_UPDATE_OUTCOME" == "$expected" ]] || return 1
	done
}

test_only_confirmed_behind_pulls() {
	test_harness_reset_logs; run_gate behind no; [[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	test_harness_reset_logs; run_gate behind yes; [[ "$REPO_UPDATE_OUTCOME" == relaunch_required && "$(pull_count)" -eq 1 ]]
}

test_blocked_states_never_pull() {
	local state
	for state in dirty detached no-upstream other-remote diverged fetch-failure; do test_harness_reset_logs; run_gate "$state" yes; [[ "$(pull_count)" -eq 0 ]] || return 1; done
	test_harness_reset_logs; run_gate pull-failure yes; [[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 1 ]]
}

test_non_origin_upstream_stops_before_fetch() {
	test_harness_reset_logs
	run_gate other-remote yes
	[[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	! grep -Eq $'git\t-C\t.*\t(fetch|pull)(\t|$)' "$TEST_COMMAND_LOG"
}

test_ahead_requires_continue() {
	test_harness_reset_logs; run_gate ahead no; [[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	test_harness_reset_logs; run_gate ahead yes; [[ "$REPO_UPDATE_OUTCOME" == ahead_continue && "$(pull_count)" -eq 0 ]]
}

test_success_requires_relaunch_without_old_work() {
	test_harness_reset_logs; run_gate behind yes
	[[ "$REPO_UPDATE_OUTCOME" == relaunch_required ]] || return 1
	! grep -Eq $'^(apt-get|sudo|stow|curl|npx)\t' "$TEST_COMMAND_LOG"
}

test_relaunch_is_injectable() (
	local called="$TEST_HARNESS_ROOT/relaunch.called"
	repo_update_relaunch() { printf '%s\n' "$*|${SETUP_CALLER:-}" >"$called"; }
	SETUP_CALLER=dotfiles repo_update_relaunch dotfiles update --all
	grep -Fqx 'dotfiles update --all|dotfiles' "$called" && [[ ! -e "$TEST_FAKE_BIN/exec" ]]
)

test_cmd_update_executes_outcome_contract() (
	local events="$TEST_HARNESS_ROOT/cmd-update.events" replies=''
	: >"$events"
	repo_update_gate() { printf 'gate\n' >>"$events"; REPO_UPDATE_OUTCOME="${TEST_GATE_OUTCOME:?}"; }
	_dotfiles_confirm() {
		local answer="${replies%% *}"
		[[ "$replies" == *' '* ]] && replies="${replies#* }" || replies=''
		printf 'confirm:%s\n' "$1" >>"$events"
		[[ "$answer" == yes ]]
	}
	print_report_table() { printf 'report\n' >>"$events"; }
	print_upgrade_summary() { printf 'summary:%s\n' "$1" >>"$events"; }
	_run_update_downstream() { printf 'downstream:%s\n' "$1" >>"$events"; }
	repo_update_relaunch() { printf 'relaunch:%s|%s\n' "$*" "${SETUP_CALLER:-}" >>"$events"; }
	_dotfiles_wait_for_reload() { printf 'wait\n' >>"$events"; }

	TEST_GATE_OUTCOME=stopped
	if cmd_update >/dev/null 2>&1; then return 1; fi
	[[ "$(<"$events")" == gate ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=current; replies=no
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == gate && "$(sed -n '2p' "$events")" == report && "$(sed -n '3p' "$events")" == confirm:* ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=current; replies='yes no'
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == gate && "$(sed -n '2p' "$events")" == report && "$(sed -n '3p' "$events")" == confirm:* && "$(sed -n '4p' "$events")" == confirm:* && "$(sed -n '5p' "$events")" == downstream:false && "$(sed -n '6p' "$events")" == summary:false ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=current; replies='yes yes'
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '5p' "$events")" == downstream:true && "$(sed -n '6p' "$events")" == summary:true ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=ahead_continue; replies=yes
	cmd_update --all >/dev/null || return 1
	[[ "$(sed -n '3p' "$events")" == confirm:* && "$(sed -n '4p' "$events")" == downstream:true && "$(sed -n '5p' "$events")" == summary:true ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=relaunch_required; replies=yes; SETUP_CALLER=dotfiles
	cmd_update --all >/dev/null || return 1
	grep -Fq "wait" "$events" || return 1
	grep -Fq "relaunch:${DOTFILES_DIR}/install.sh|dotfiles" "$events" || return 1
	! grep -Fq downstream "$events"
)

test_downstream_executes_apt_first_and_all_matrix() (
	local events="$TEST_HARNESS_ROOT/downstream.events"
	: >"$events"
	sudo() { printf 'sudo:%s\n' "$*" >>"$events"; }
	_run_upgrade_step() { printf 'step:%s\n' "$1" >>"$events"; UPGRADE_STEP_RESULT["$1"]=ok; }

	_run_update_downstream false >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == 'sudo:apt-get update -qq' ]] || return 1
	grep -Fq 'step:apt packages' "$events" || return 1
	! grep -Eq 'step:(Node.js \(nvm\)|Go \(asdf\)|Monaspace fonts)' "$events" || return 1

	: >"$events"
	_run_update_downstream true >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == 'sudo:apt-get update -qq' ]] || return 1
	grep -Fq 'step:Node.js (nvm)' "$events" || return 1
	grep -Fq 'step:Go (asdf)' "$events" || return 1
	grep -Fq 'step:Monaspace fonts' "$events"
)

test_apt_report_probe_uses_cached_indices_without_sudo() (
	local count sudo_calls=0
	apt-get() { printf '%s\n' 'Inst cached-package'; }
	sudo() { sudo_calls=$((sudo_calls + 1)); return 99; }
	count="$(apt_upgradable_count)"
	[[ "$count" -eq 1 ]] || return 1
	[[ "$sudo_calls" -eq 0 ]]
)

test_update_report_uses_clear_title_spacing_and_aligned_action_rule() (
	local output_file="$TEST_HARNESS_ROOT/update-report.output"
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|up to date'; }
	NO_COLOR=1 print_report_table >"$output_file"
	grep -Fq $'Update report\n\ncomponent' "$output_file" || return 1
	! grep -Fq 'Upgrade report' "$output_file" || return 1
	grep -Fq $'everything looks current.\n\n' "$output_file" || return 1
	grep -Eq '^-------------------\+------------------------------\+------------------------\+-----------------' "$output_file"
)

test_update_and_upgrade_rows_keep_the_last_column_width() (
	local output line_lengths
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|up to date'; }

	line_lengths="$(NO_COLOR=1 print_report_table | awk '/^(component|apt packages|---)/ { print length($0) }')"
	[[ "$line_lengths" == $'93\n93\n93' ]] || return 1

	line_lengths="$(NO_COLOR=1 print_upgrade_summary false | awk '/^(component|apt packages|---)/ { print length($0) }')"
	[[ "$line_lengths" == $'93\n93\n93' ]]
)

test_update_apply_uses_high_level_upgrade_heading_without_opt_in_plan() (
	local output
	repo_update_gate() { REPO_UPDATE_OUTCOME=current; }
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
	_collect_check_rows() { printf '%s\n' 'dotfiles repo|main@abc123|none|up to date'; }
	local output
	output="$(print_upgrade_summary false)"
	grep -Fq 'dotfiles repo' <<<"$output" || return 1
	grep -Fq '| ok' <<<"$output"
)

test_tui_runs_shared_update_without_submenu() (
	local fake_dotfiles="$TEST_HARNESS_ROOT/fake-dotfiles"
	local events="$TEST_HARNESS_ROOT/tui-update.events" tty_output="$TEST_HARNESS_ROOT/tui-update.tty"
	cat >"$fake_dotfiles" <<'FAKE'
#!/usr/bin/env bash
printf 'dotfiles:%s\n' "$*" >>"${TEST_TUI_EVENTS:?}"
exit "${TEST_DOTFILES_RC:-0}"
FAKE
	chmod 700 "$fake_dotfiles"
	export TEST_TUI_EVENTS="$events" DOTFILES_TTY_PATH="$tty_output"
	: >"$events"
	resolve_dotfiles_cmd() { printf '%s\n' "$fake_dotfiles"; }
	ui_print_header() { printf 'header:%s|%s\n' "$1" "$2"; }

	run_update_flow || return 1
	[[ "$(sed -n '1p' "$events")" == 'dotfiles:update' && "$(wc -l <"$events")" -eq 1 ]] || return 1
	grep -Fq 'header:Update|Dotfiles › Update' "$tty_output" || return 1
	! declare -F update_menu >/dev/null 2>&1
)

test_stopped_paths_have_no_downstream() {
	test_harness_reset_logs; run_gate dirty yes
	! grep -Eq $'^(apt-get|sudo|stow|curl|npx)\t' "$TEST_COMMAND_LOG"
}

test_status_is_strictly_local() {
	local output="$TEST_HARNESS_ROOT/status.out"
	test_harness_reset_logs; TEST_REPO_STATE=current "$REPO_DIR/bin/bin/dotfiles" status >"$output"
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
	ui_print_report_table_columns() { printf 'columns\n'; }
	_install_summary_probe() { printf 'installed|present\n'; }
	_install_short_label() { printf '%s\n' "$1"; }
	ui_print_report_table_row() { printf 'row:%s|%s|%s\n' "$1" "$2" "$3"; }
	ui_print_report_rollup() { printf 'rollup:%s|%s|%s\n' "$1" "$2" "$3"; }
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
	ui_print_report_table_columns() { rt_print_table_columns; }
	_install_summary_probe() { printf 'installed|present\n'; }
	_install_short_label() { printf '%s\n' "$1"; }
	ui_print_report_table_row() { rt_print_table_row "$@"; }
	ui_print_report_rollup() { rt_print_rollup "$@"; }
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

test_retained_capability_coverage() {
	declare -F cmd_status >/dev/null 2>&1 || return 1
	declare -F cmd_update >/dev/null 2>&1 || return 1
	declare -F cmd_restow >/dev/null 2>&1
}

test_removed_commands_have_guidance() {
	local cmd output rc
	for cmd in summary upgrade self; do
		set +e; output="$("$REPO_DIR/bin/bin/dotfiles" "$cmd" 2>&1)"; rc=$?; set -e
		[[ "$rc" -ne 0 ]] || return 1
		case "$cmd" in summary) [[ "$output" == *'use dotfiles status'* ]] ;; upgrade) [[ "$output" == *'use dotfiles update [--all]'* ]] ;; self) [[ "$output" == *'use dotfiles update'* && "$output" == *restow* ]] ;; esac || return 1
	done
}

test_exact_command_set_parity() {
	source "$REPO_DIR/scripts/lib/command_metadata.sh"
	local expected=(menu update status commands packages restow help) i
	[[ "${#DOTFILES_COMMAND_KEYS[@]}" -eq 7 ]] || return 1
	for i in "${!expected[@]}"; do [[ "${DOTFILES_COMMAND_KEYS[$i]}" == "${expected[$i]}" ]] || return 1; done
	dotfiles_command_metadata_validate_dispatch "$REPO_DIR/bin/bin/dotfiles"
}

test_harness_safety_and_no_real_mutation() {
	[[ "$(command -v git)" == "$TEST_FAKE_BIN/git" && ! -e "$TEST_FAKE_BIN/exec" ]] || return 1
	[[ "$HOME" == "$TEST_HARNESS_ROOT/home" && ! -s "$TEST_URL_LOG" ]]
}

install_state_git_fake
[[ -f "$REPO_DIR/scripts/lib/repo_update.sh" ]] && source "$REPO_DIR/scripts/lib/repo_update.sh"
DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/bin/bin/dotfiles" >/dev/null
source "$REPO_DIR/scripts/lib/menu_runner.sh"
source "$REPO_DIR/scripts/menus/initial_setup.sh"
source "$REPO_DIR/scripts/menus/update.sh"
REPO_UPDATE_OUTCOME="${REPO_UPDATE_OUTCOME:-missing}"
declare -F repo_update_gate >/dev/null || repo_update_gate() { REPO_UPDATE_OUTCOME=missing; return 1; }
declare -F repo_update_relaunch >/dev/null || repo_update_relaunch() { return 1; }
expect_success 'repository state table returns stable outcomes' test_state_table_outcomes
expect_success 'only clean strictly-behind confirmed state pulls ff-only once' test_only_confirmed_behind_pulls
expect_success 'blocked declined and failed states never reach downstream' test_blocked_states_never_pull
expect_success 'non-origin upstream stops before fetch or pull' test_non_origin_upstream_stops_before_fetch
expect_success 'ahead never pulls and requires explicit continue confirmation' test_ahead_requires_continue
expect_success 'successful pull requires relaunch and stops old-process work' test_success_requires_relaunch_without_old_work
expect_success 'relaunch wrapper is injectable without a fake exec command' test_relaunch_is_injectable
expect_success 'cmd_update executes stopped current ahead and relaunch outcomes' test_cmd_update_executes_outcome_contract
expect_success 'downstream execution runs apt refresh first and honors --all' test_downstream_executes_apt_first_and_all_matrix
expect_success 'pre-confirmation apt report probing never invokes sudo' test_apt_report_probe_uses_cached_indices_without_sudo
expect_success 'update report title spacing and action separator are stable' test_update_report_uses_clear_title_spacing_and_aligned_action_rule
expect_success 'update and upgrade rows preserve the fixed final column width' test_update_and_upgrade_rows_keep_the_last_column_width
expect_success 'update apply uses a high-level Upgrade heading without opt-in plan noise' test_update_apply_uses_high_level_upgrade_heading_without_opt_in_plan
expect_success 'upgrade summary marks the repo gate as handled' test_upgrade_summary_marks_repo_gate_as_handled
expect_success 'TUI runs shared update directly without a submenu' test_tui_runs_shared_update_without_submenu
expect_success 'stopped paths perform no apt tool network or stow work' test_stopped_paths_have_no_downstream
expect_success 'dotfiles status is strictly local and labels freshness unchecked' test_status_is_strictly_local
expect_success 'root TUI status omits unchecked apt and repository freshness locally' test_root_tui_status_omits_unchecked_freshness_without_network
expect_success 'root status rollup has exactly one blank line before the summary' test_root_status_rollup_has_one_blank_line
expect_success 'status update and restow retain removed command capabilities' test_retained_capability_coverage
expect_success 'summary upgrade and self fail with migration guidance' test_removed_commands_have_guidance
expect_success 'metadata help Command Lib and dispatch share seven keys' test_exact_command_set_parity
expect_success 'harness fakes prevent real repo network apt home and stow mutation' test_harness_safety_and_no_real_mutation

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
