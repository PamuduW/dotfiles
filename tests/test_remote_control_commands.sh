#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

test_codex_rc_delegates_start_and_stop() (
	test_harness_reset_logs
	ln -sfn -- _test_fake_command "$TEST_FAKE_BIN/codex"
	test_harness_configure_fake codex 0

	"$REPO_DIR/bin/bin/codex-rc" start >/dev/null
	"$REPO_DIR/bin/bin/codex-rc" stop >/dev/null

	[[ "$(<"$TEST_COMMAND_LOG")" == $'codex\tremote-control\tstart\ncodex\tremote-control\tstop' ]]
)

test_codex_rc_rejects_unknown_actions() (
	test_harness_reset_logs
	ln -sfn -- _test_fake_command "$TEST_FAKE_BIN/codex"
	test_harness_configure_fake codex 0
	local output rc=0

	output="$("$REPO_DIR/bin/bin/codex-rc" restart 2>&1)" || rc=$?

	[[ "$rc" -eq 64 ]] || return 1
	[[ "$output" == *'Usage: codex-rc {start|stop}'* ]] || return 1
	[[ ! -s "$TEST_COMMAND_LOG" ]]
)

expect_success 'codex-rc delegates native start and stop actions' test_codex_rc_delegates_start_and_stop
expect_success 'codex-rc rejects unknown actions without invoking Codex' test_codex_rc_rejects_unknown_actions

test_harness_cleanup
finish_tests
