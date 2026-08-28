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

write_persistent_fake_claude() {
	cat >"$TEST_FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TEST_CLAUDE_LOG:?}"
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF
	chmod 700 "$TEST_FAKE_BIN/claude"
}

wait_for_process_exit() {
	local pid="$1" attempt
	for attempt in {1..50}; do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.02
	done
	return 1
}

test_claude_rc_manages_one_background_server() (
	local project="$TEST_HARNESS_ROOT/project"
	local state_dir="$TEST_HARNESS_ROOT/state/claude-rc"
	local pid output
	mkdir -p "$project"
	TEST_CLAUDE_LOG="$TEST_HARNESS_ROOT/claude.calls"
	XDG_STATE_HOME="$TEST_HARNESS_ROOT/state"
	export TEST_CLAUDE_LOG XDG_STATE_HOME
	write_persistent_fake_claude
	trap 'if [[ -f "$state_dir/server.pid" ]]; then kill "$(<"$state_dir/server.pid")" 2>/dev/null || true; fi' EXIT

	output="$(cd -- "$project" && "$REPO_DIR/bin/bin/claude-rc" start)" || return 1
	[[ "$output" == *'Claude Remote Control started'* ]] || return 1
	[[ -f "$state_dir/server.pid" && -f "$state_dir/server.start" && -f "$state_dir/server.cwd" ]] || return 1
	pid="$(<"$state_dir/server.pid")"
	kill -0 "$pid" 2>/dev/null || return 1
	[[ "$(<"$state_dir/server.cwd")" == "$project" ]] || return 1
	[[ "$(<"$TEST_CLAUDE_LOG")" == 'remote-control' ]] || return 1

	output="$(cd -- "$TEST_HARNESS_ROOT" && "$REPO_DIR/bin/bin/claude-rc" start)" || return 1
	[[ "$output" == *'already running'* ]] || return 1
	[[ "$(wc -l <"$TEST_CLAUDE_LOG")" -eq 1 ]] || return 1

	output="$(cd -- "$TEST_HARNESS_ROOT" && "$REPO_DIR/bin/bin/claude-rc" stop)" || return 1
	[[ "$output" == *'Claude Remote Control stopped'* ]] || return 1
	wait_for_process_exit "$pid" || return 1
	[[ ! -e "$state_dir/server.pid" && ! -e "$state_dir/server.start" && ! -e "$state_dir/server.cwd" ]]
)

test_claude_rc_does_not_stop_an_unrelated_process() (
	local state_dir="$TEST_HARNESS_ROOT/state/claude-rc"
	local sleeper output rc=0
	XDG_STATE_HOME="$TEST_HARNESS_ROOT/state"
	export XDG_STATE_HOME
	mkdir -p "$state_dir"
	sleep 30 &
	sleeper=$!
	trap 'kill "$sleeper" 2>/dev/null || true' EXIT
	printf '%s\n' "$sleeper" >"$state_dir/server.pid"
	printf '%s\n' '0' >"$state_dir/server.start"
	printf '%s\n' '/unrelated' >"$state_dir/server.cwd"

	output="$("$REPO_DIR/bin/bin/claude-rc" stop 2>&1)" || rc=$?

	[[ "$rc" -eq 1 ]] || return 1
	[[ "$output" == *'does not match the recorded process'* ]] || return 1
	kill -0 "$sleeper" 2>/dev/null
)

expect_success 'codex-rc delegates native start and stop actions' test_codex_rc_delegates_start_and_stop
expect_success 'codex-rc rejects unknown actions without invoking Codex' test_codex_rc_rejects_unknown_actions
expect_success 'claude-rc manages one background server from any directory' test_claude_rc_manages_one_background_server
expect_success 'claude-rc refuses to stop a different process after PID reuse' test_claude_rc_does_not_stop_an_unrelated_process

test_harness_cleanup
finish_tests
