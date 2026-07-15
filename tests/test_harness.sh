#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/test_harness.sh
source "$TEST_DIR/lib/test_harness.sh"

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

test_cleanup_runs_after_success() {
	local root
	root="$(bash -c '
		set -euo pipefail
		unset TEST_HARNESS_ROOT TEST_FAKE_BIN TEST_FAKE_CONFIG TEST_FAKE_SIBLINGS
		unset TEST_COMMAND_LOG TEST_URL_LOG
		source "$1"
		test_harness_init
		printf "%s" "$TEST_HARNESS_ROOT"
	' _ "$TEST_DIR/lib/test_harness.sh")"
	[[ -n "$root" && ! -e "$root" ]]
}

test_cleanup_runs_after_failure() {
	local root rc
	set +e
	root="$(bash -c '
		set -euo pipefail
		unset TEST_HARNESS_ROOT TEST_FAKE_BIN TEST_FAKE_CONFIG TEST_FAKE_SIBLINGS
		unset TEST_COMMAND_LOG TEST_URL_LOG
		source "$1"
		test_harness_init
		printf "%s" "$TEST_HARNESS_ROOT"
		exit 23
	' _ "$TEST_DIR/lib/test_harness.sh")"
	rc=$?
	set -e
	[[ "$rc" -eq 23 && -n "$root" && ! -e "$root" ]]
}

test_init_failure_after_root_cleans_up() {
	local parent="$TEST_HARNESS_ROOT/reviewer-fixtures/init-failure" rc
	mkdir -p -- "$parent"
	set +e
	TEST_HARNESS_FAIL_AFTER_ROOT=1 TMPDIR="$parent" bash -c '
		set -euo pipefail
		unset TEST_HARNESS_ROOT TEST_FAKE_BIN TEST_FAKE_CONFIG TEST_FAKE_SIBLINGS
		unset TEST_COMMAND_LOG TEST_URL_LOG
		source "$1"
		test_harness_init
	' _ "$TEST_DIR/lib/test_harness.sh" >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" -eq 93 ]] || return 1
	[[ -z "$(find "$parent" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}

test_protected_original_home_unchanged_passes() {
	local original_home="$TEST_HARNESS_ROOT/reviewer-fixtures/original-home-clean" rc
	mkdir -p -- "$original_home"
	printf 'unchanged\n' >"$original_home/sentinel"
	set +e
	HOME="$original_home" bash -c '
		set -euo pipefail
		unset TEST_HARNESS_ROOT TEST_FAKE_BIN TEST_FAKE_CONFIG TEST_FAKE_SIBLINGS
		unset TEST_COMMAND_LOG TEST_URL_LOG
		source "$1"
		test_harness_init
		test_harness_protect_original_path sentinel
	' _ "$TEST_DIR/lib/test_harness.sh" >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" -eq 0 ]]
}

test_protected_original_home_mutation_is_detected() {
	local original_home="$TEST_HARNESS_ROOT/reviewer-fixtures/original-home-mutated" rc
	mkdir -p -- "$original_home"
	printf 'before\n' >"$original_home/sentinel"
	set +e
	HOME="$original_home" bash -c '
		set -euo pipefail
		unset TEST_HARNESS_ROOT TEST_FAKE_BIN TEST_FAKE_CONFIG TEST_FAKE_SIBLINGS
		unset TEST_COMMAND_LOG TEST_URL_LOG
		source "$1"
		test_harness_init
		test_harness_protect_original_path sentinel
		printf "after\n" >"$ORIGINAL_HOME/sentinel"
	' _ "$TEST_DIR/lib/test_harness.sh" >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" -eq 94 ]] || return 1
	[[ "$(<"$original_home/sentinel")" == 'after' ]]
}

test_environment_is_isolated() {
	[[ "$HOME" == "$TEST_HARNESS_ROOT/home" ]] || return 1
	[[ "$XDG_CONFIG_HOME" == "$TEST_HARNESS_ROOT/xdg" ]] || return 1
	[[ "$TMPDIR" == "$TEST_HARNESS_ROOT/tmp" ]] || return 1
	[[ "$TEST_COMMAND_LOG" == "$TEST_HARNESS_ROOT/log/commands.log" ]] || return 1
	[[ "$TEST_URL_LOG" == "$TEST_HARNESS_ROOT/log/urls.log" ]] || return 1
	[[ "$(command -v git)" == "$TEST_FAKE_BIN/git" ]] || return 1
	[[ "$(command -v curl)" == "$TEST_FAKE_BIN/curl" ]] || return 1
	[[ "$(command -v npx)" == "$TEST_FAKE_BIN/npx" ]]
}

test_fakes_record_sanitized_argv() {
	test_harness_reset_logs
	test_harness_configure_fake git 0 'git-output'
	local output
	output="$(git status --short)"
	[[ "$output" == 'git-output' ]] || return 1
	grep -Fqx $'git\tstatus\t--short' "$TEST_COMMAND_LOG"
}

test_fake_exit_and_stderr_propagate() {
	test_harness_reset_logs
	test_harness_configure_fake npx 37 '' 'configured npx failure'
	local output rc
	set +e
	output="$(npx skills check 2>&1)"
	rc=$?
	set -e
	[[ "$rc" -eq 37 ]] || return 1
	[[ "$output" == 'configured npx failure' ]] || return 1
	grep -Fqx $'npx\tskills\tcheck' "$TEST_COMMAND_LOG"
}

test_unconfigured_network_fake_fails_closed() {
	test_harness_reset_logs
	test_harness_clear_fake curl
	local rc
	set +e
	curl https://example.invalid/should-not-run >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" -eq 97 ]] || return 1
	grep -Fqx $'curl\thttps://example.invalid/should-not-run' "$TEST_COMMAND_LOG"
}

test_fake_sibling_installer_is_intercepted() {
	test_harness_reset_logs
	test_harness_configure_fake sibling-install 0 'sibling-returned'
	local sibling output
	sibling="$(test_harness_create_fake_sibling agent_bootstrap)"
	output="$(SETUP_CALLER=dotfiles "$sibling/install.sh" menu)"
	[[ "$output" == 'sibling-returned' ]] || return 1
	grep -Fqx $'sibling-install\tmenu' "$TEST_COMMAND_LOG"
}

test_relaunch_wrapper_is_injectable() {
	test_harness_reset_logs
	local TEST_RELAUNCH_WRAPPER=test_record_relaunch
	# shellcheck disable=SC2317  # Invoked indirectly by test_harness_invoke_relaunch.
	test_record_relaunch() {
		test_harness_log_call relaunch "$@"
	}
	test_harness_invoke_relaunch update-menu ./install.sh --update
	grep -Fqx $'relaunch\tupdate-menu\t./install.sh\t--update' "$TEST_COMMAND_LOG"
}

test_path_guard_rejects_outside_writes() {
	test_harness_assert_isolated_path "$HOME/example" || return 1
	test_harness_assert_isolated_path "$XDG_CONFIG_HOME/example" || return 1
	! test_harness_assert_isolated_path "/tmp/outside-harness" 2>/dev/null || return 1
	! test_harness_assert_isolated_path "${ORIGINAL_HOME}/outside-harness" 2>/dev/null
}

test_canary_is_redacted_everywhere() {
	test_harness_reset_logs
	local TEST_CANARY_SECRET='canary-do-not-leak-827364'
	export TEST_CANARY_SECRET
	test_harness_configure_fake curl 0 \
		"response ${TEST_CANARY_SECRET}" \
		"diagnostic ${TEST_CANARY_SECRET}"
	local output error_log="$TEST_HARNESS_ROOT/log/stderr.log"
	output="$(curl -H "Authorization: Bearer ${TEST_CANARY_SECRET}" \
		"https://${TEST_CANARY_SECRET}@example.invalid/data" 2>"$error_log")"
	[[ "$output" == 'response [redacted]' ]] || return 1
	if grep -FR -- "$TEST_CANARY_SECRET" \
		"$TEST_COMMAND_LOG" "$TEST_URL_LOG" "$error_log"; then
		return 1
	fi
	grep -Fq 'diagnostic [redacted]' "$error_log" || return 1
	grep -Fq '[redacted]' "$TEST_COMMAND_LOG"
	grep -Fq '[redacted]' "$TEST_URL_LOG"
	unset TEST_CANARY_SECRET
}

test_harness_init
expect_success 'cleanup runs after successful test process' test_cleanup_runs_after_success
expect_success 'cleanup runs after failing test process' test_cleanup_runs_after_failure
expect_success 'init failure after root creation removes the root' test_init_failure_after_root_cleans_up
expect_success 'unchanged protected original-home path passes teardown' test_protected_original_home_unchanged_passes
expect_success 'protected original-home mutation fails teardown' test_protected_original_home_mutation_is_detected
expect_success 'HOME, XDG, logs, and commands are isolated' test_environment_is_isolated
expect_success 'fake commands record sanitized argv' test_fakes_record_sanitized_argv
expect_success 'fake commands propagate configured exit and stderr' test_fake_exit_and_stderr_propagate
expect_success 'unconfigured network fake fails closed' test_unconfigured_network_fake_fails_closed
expect_success 'fake sibling install.sh records calls' test_fake_sibling_installer_is_intercepted
expect_success 'relaunch uses an injectable shell wrapper' test_relaunch_wrapper_is_injectable
expect_success 'path guard rejects writes outside isolated homes' test_path_guard_rejects_outside_writes
expect_success 'canary secret is absent from output and logs' test_canary_is_redacted_everywhere

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
