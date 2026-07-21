#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=tests/lib/test_harness.sh
# shellcheck disable=SC1091  # Dynamic repository path; validated above.
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

# Source only the owned menu units; dependencies are stubbed per test.
# shellcheck source=scripts/menus/main.sh
source "$REPO_DIR/scripts/menus/main.sh"
# shellcheck source=scripts/menus/initial_setup.sh
source "$REPO_DIR/scripts/menus/initial_setup.sh"
# shellcheck source=scripts/lib/components/menu.sh
_COMP_DESC_LINES=2
source "$REPO_DIR/scripts/lib/components/menu.sh"
# shellcheck source=scripts/lib/components/plan.sh
source "$REPO_DIR/scripts/lib/components/plan.sh"

passed=0
failed=0

pass() {
	printf 'ok - %s\n' "$1"
	passed=$((passed + 1))
}

fail() {
	printf 'not ok - %s\n' "$1" >&2
	failed=$((failed + 1))
}

expect_success() {
	local name="$1"
	shift
	if "$@"; then
		pass "$name"
	else
		fail "$name"
	fi
}

assert_array_equals() {
	local actual_name="$1" expected_name="$2"
	local -n actual="$actual_name" expected="$expected_name"
	[[ "${#actual[@]}" -eq "${#expected[@]}" ]] || return 1
	local i
	for i in "${!expected[@]}"; do
		[[ "${actual[$i]}" == "${expected[$i]}" ]] || return 1
	done
}

test_exact_root_contract() {
	local expected_labels=(
		"Check Status"
		"Install Dotfiles"
		"Update"
		"GitHub Token Config"
		"Command Lib"
		"Package Lib"
		"Agentbot"
		"Quit"
	)
	# shellcheck disable=SC2034  # Read through a nameref in assert_array_equals.
	local expected_keys=(status install update github_token command_lib package_lib agentbot quit)
	assert_array_equals _main_menu_labels expected_labels || return 1
	assert_array_equals _main_menu_keys expected_keys || return 1
	local i description
	for i in "${!expected_labels[@]}"; do
		description="$(_main_menu_desc_fn "$i")"
		[[ -n "$description" ]] || return 1
	done
}

test_root_breadcrumb_is_dotfiles() {
	local queue="$TEST_HARNESS_ROOT/root-breadcrumb.queue"
	local captured="$TEST_HARNESS_ROOT/root-breadcrumb.captured"
	printf 'quit\n' >"$queue"
	menu_simple_run() {
		local choice rest="$queue.rest"
		printf '%s\n%s\n%s\n' \
			"$MENU_SIMPLE_TITLE" "$MENU_SIMPLE_BREADCRUMB" "$MENU_SIMPLE_HINT" >"$captured"
		IFS= read -r choice <"$queue"
		tail -n +2 "$queue" >"$rest"
		mv -f -- "$rest" "$queue"
		printf '%s\n' "$choice"
	}
	( main_menu_loop )
	[[ "$(sed -n '1p' "$captured")" == 'Dotfiles' ]] || return 1
	[[ "$(sed -n '2p' "$captured")" == 'Dotfiles' ]] || return 1
	[[ "$(sed -n '3p' "$captured")" == 'Up/Down navigate   Enter confirm' ]]
}

test_direct_status_install_update_dispatch() (
	local calls="$TEST_HARNESS_ROOT/direct.calls" pauses=0 clears=0
	: >"$calls"
	# shellcheck disable=SC2317  # Test doubles invoked indirectly by menu dispatch.
	print_status_summary_all() { printf '%s\n' status >>"$calls"; }
	# shellcheck disable=SC2317
	run_initial_setup_flow() { printf '%s\n' install >>"$calls"; }
	# shellcheck disable=SC2317
	run_update_flow() { printf '%s\n' update >>"$calls"; }
	ui_pause() { pauses=$((pauses + 1)); }
	# shellcheck disable=SC2317
	ui_clear() { clears=$((clears + 1)); }
	_main_menu_dispatch status || return 1
	_main_menu_dispatch install || return 1
	_main_menu_dispatch update || return 1
	[[ "$(printf '%s ' "$(<"$calls")")" == *status* ]] || return 1
	[[ "$(<"$calls")" == $'status\ninstall\nupdate' ]] || return 1
	[[ "$pauses" -eq 3 ]] || return 1
	[[ "$clears" -eq 4 ]]
)

test_required_breadcrumb_literals() {
	local status_fn component_fn plan_fn
	status_fn="$(declare -f print_status_summary_all)"
	component_fn="$(declare -f _draw_component_menu)"
	plan_fn="$(declare -f show_plan)"
	[[ "$status_fn" == *'ui_print_header "Check Status" "Dotfiles › Check Status"'* ]] || return 1
	[[ "$component_fn" == *'ui_print_header "Install Dotfiles" "Dotfiles › Install Dotfiles"'* ]] || return 1
	[[ "$plan_fn" == *'ui_print_header "Execution Plan" "Dotfiles › Install Dotfiles › Execution Plan"'* ]]
}

test_cancel_redraws_and_quit_returns() {
	local queue="$TEST_HARNESS_ROOT/cancel-quit.queue" output
	printf 'CANCEL\nquit\n' >"$queue"
	menu_simple_run() {
		local choice rest="$queue.rest"
		IFS= read -r choice <"$queue"
		tail -n +2 "$queue" >"$rest"
		mv -f -- "$rest" "$queue"
		if [[ "$choice" == 'CANCEL' ]]; then
			return 1
		fi
		printf '%s\n' "$choice"
	}
	output="$({ main_menu_loop; printf '%s\n' LOOP_RETURNED; })"
	[[ "$output" == *LOOP_RETURNED* ]] || return 1
	[[ ! -s "$queue" ]]
}

test_failed_action_pauses_once() {
	local pauses=0 rc
	# shellcheck disable=SC2317  # Test double invoked indirectly by menu dispatch.
	print_status_summary_all() { printf '%s\n' 'status failed' >&2; return 42; }
	ui_pause() { pauses=$((pauses + 1)); }
	set +e
	_main_menu_dispatch status >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" -eq 42 ]] || return 1
	[[ "$pauses" -eq 1 ]]
}

test_relaunched_update_skips_stale_parent_pause() (
	local pauses=0
	run_update_flow() { DOTFILES_UPDATE_RELAUNCHED=true; return 0; }
	ui_clear() { :; }
	ui_pause() { pauses=$((pauses + 1)); }
	_main_menu_run_direct_action run_update_flow || return 1
	[[ "$pauses" -eq 0 ]]
)

test_deferred_actions_are_safe_when_undefined() {
	local pauses=0 action output output_file="$TEST_HARNESS_ROOT/deferred.output"
	unset -f github_token_menu command_lib_menu package_lib_menu 2>/dev/null || true
	ui_pause() { pauses=$((pauses + 1)); }
	test_harness_reset_logs
	for action in github_token command_lib package_lib; do
		_main_menu_dispatch "$action" >"$output_file" || return 1
		output="$(<"$output_file")"
		[[ "$output" == *'not available'* ]] || return 1
	done
	[[ "$pauses" -eq 3 ]] || return 1
	[[ ! -s "$TEST_COMMAND_LOG" && ! -s "$TEST_URL_LOG" ]]
}

test_deferred_actions_call_defined_hooks() {
	local calls="$TEST_HARNESS_ROOT/deferred.calls"
	: >"$calls"
	# shellcheck disable=SC2317  # Test doubles invoked indirectly by menu dispatch.
	github_token_menu() { printf '%s\n' github_token >>"$calls"; }
	# shellcheck disable=SC2317
	command_lib_menu() { printf '%s\n' command_lib >>"$calls"; }
	# shellcheck disable=SC2317
	package_lib_menu() { printf '%s\n' package_lib >>"$calls"; }
	_main_menu_dispatch github_token || return 1
	_main_menu_dispatch command_lib || return 1
	_main_menu_dispatch package_lib || return 1
	[[ "$(<"$calls")" == $'github_token\ncommand_lib\npackage_lib' ]]
}

test_agentbot_is_deterministic_unavailable_and_non_mutating() {
	local pauses=0 legacy_calls=0 relaunch_calls=0 output
	local protected_relative=".dotfiles-task04-agentbot-${BASHPID}"
	local protected="$ORIGINAL_HOME/$protected_relative"
	[[ ! -e "$protected" ]] || return 1
	test_harness_protect_original_path "$protected_relative"
	test_harness_reset_logs
	test_harness_configure_fake sibling-install 88 '' 'must not run'
	test_harness_create_fake_sibling agent_bootstrap >/dev/null
	# shellcheck disable=SC2317  # Must remain unreachable in this safety test.
	agents_menu() { legacy_calls=$((legacy_calls + 1)); }
	# shellcheck disable=SC2317
	test_agentbot_relaunch() { relaunch_calls=$((relaunch_calls + 1)); }
	# shellcheck disable=SC2034  # Consumed indirectly by the harness relaunch seam.
	local TEST_RELAUNCH_WRAPPER=test_agentbot_relaunch
	ui_pause() { pauses=$((pauses + 1)); }
	_main_menu_dispatch agentbot >"$TEST_HARNESS_ROOT/agentbot.output" || return 1
	output="$(<"$TEST_HARNESS_ROOT/agentbot.output")"
	[[ "$output" == *'Agentbot is unavailable until the sibling bridge is installed.'* ]] || return 1
	[[ "$pauses" -eq 1 ]] || return 1
	[[ "$legacy_calls" -eq 0 && "$relaunch_calls" -eq 0 ]] || return 1
	[[ ! -s "$TEST_COMMAND_LOG" && ! -s "$TEST_URL_LOG" ]] || return 1
	[[ ! -e "$protected" ]]
}

test_agentbot_failure_pauses_before_redraw() (
	local pauses=0 rc
	dotfiles_launch_agentbot() { return 23; }
	ui_pause() { pauses=$((pauses + 1)); }

	set +e
	_main_menu_dispatch agentbot >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" -eq 23 && "$pauses" -eq 1 ]]
)

test_caller_guard_hides_agentbot_entry() {
	local captured="$TEST_HARNESS_ROOT/caller-guard.captured"
	SETUP_CALLER=agentbot
	export SETUP_CALLER
	menu_simple_run() {
		printf '%s\n' "${MENU_SIMPLE_LABELS[*]}" >"$captured"
		MENU_SIMPLE_RESULT=quit
		printf 'quit\n'
		return 0
	}
	main_menu_loop
	unset SETUP_CALLER
	! grep -Fq 'Agentbot' "$captured"
}

expect_success 'root labels and keys match the exact eight-action contract' test_exact_root_contract
expect_success 'root title, breadcrumb, and hint are normalized' test_root_breadcrumb_is_dotfiles
expect_success 'status, install, and update dispatch directly' test_direct_status_install_update_dispatch
expect_success 'status, picker, and plan breadcrumbs are exact' test_required_breadcrumb_literals
expect_success 'root cancel redraws and explicit Quit returns cleanly' test_cancel_redraws_and_quit_returns
expect_success 'failed direct action pauses exactly once and returns failure' test_failed_action_pauses_once
expect_success 're-launched updates skip the stale parent pause' test_relaunched_update_skips_stale_parent_pause
expect_success 'undefined deferred actions are unavailable and non-mutating' test_deferred_actions_are_safe_when_undefined
expect_success 'defined deferred hooks are dispatched without root rewiring' test_deferred_actions_call_defined_hooks
expect_success 'Agentbot is deterministic unavailable and non-mutating' test_agentbot_is_deterministic_unavailable_and_non_mutating
expect_success 'failed Agentbot launch pauses before the Dotfiles menu redraws' test_agentbot_failure_pauses_before_redraw
expect_success 'SETUP_CALLER=agentbot hides the reciprocal menu entry' test_caller_guard_hides_agentbot_entry

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
