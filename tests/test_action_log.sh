#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
# DF-004: overlapping action logs must not share a raw capture.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

install_constant_date() {
	local fake_bin="$1"
	mkdir -p "$fake_bin"
	cat >"$fake_bin/date" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '+%N' ]]; then
	printf '000000001\n'
	exit 0
fi
printf '2026-01-01_00-00-00\n'
EOF
	chmod 700 "$fake_bin/date"
}

finished_logs() {
	find "$1/log" -maxdepth 1 -type f -name '*.log' -print | sort
}

raw_logs() {
	find "$1/log" -maxdepth 1 -type f -name '*.log.raw' -print
}

test_overlapping_action_logs_keep_separate_complete_output() (
	local probe_dir="$TEST_HARNESS_ROOT/action-log-overlap"
	local fake_bin="$TEST_HARNESS_ROOT/action-log-date"
	local go="$probe_dir/go"
	mkdir -p "$probe_dir"
	install_constant_date "$fake_bin"

	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		start_action_log
		printf 'A1\n'
		while [[ ! -f "$go" ]]; do sleep 0.02; done
		printf 'A2\n'
	) >/dev/null &
	local a_pid=$!

	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		start_action_log
		printf 'B1\n'
		printf 'B2\n'
	) >/dev/null

	: >"$go"
	wait "$a_pid"

	mapfile -t logs < <(finished_logs "$probe_dir")
	[[ "${#logs[@]}" -eq 2 ]] || return 1
	[[ -z "$(raw_logs "$probe_dir")" ]] || return 1
	local combined a_ok=0 b_ok=0
	combined="$(cat -- "${logs[@]}")"
	[[ "$combined" == *A1* && "$combined" == *A2* ]] || return 1
	[[ "$combined" == *B1* && "$combined" == *B2* ]] || return 1
	for log in "${logs[@]}"; do
		if grep -qx A1 "$log" && grep -qx A2 "$log" && ! grep -q B1 "$log"; then
			a_ok=1
		fi
		if grep -qx B1 "$log" && grep -qx B2 "$log" && ! grep -q A1 "$log"; then
			b_ok=1
		fi
	done
	[[ "$a_ok" -eq 1 && "$b_ok" -eq 1 ]]
)

test_prune_does_not_delete_a_live_peer_raw_capture() (
	local probe_dir="$TEST_HARNESS_ROOT/action-log-live-peer"
	local fake_bin="$TEST_HARNESS_ROOT/action-log-live-date"
	local ready="$probe_dir/ready"
	local go="$probe_dir/go"
	mkdir -p "$probe_dir"
	install_constant_date "$fake_bin"

	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		start_action_log
		printf 'LIVE\n'
		: >"$ready"
		while [[ ! -f "$go" ]]; do sleep 0.02; done
	) >/dev/null &
	local a_pid=$!
	while [[ ! -f "$ready" ]]; do sleep 0.02; done

	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		_prune_action_logs
	)
	mapfile -t raws < <(raw_logs "$probe_dir")
	[[ "${#raws[@]}" -ge 1 ]] || return 1

	: >"$go"
	wait "$a_pid"
	[[ -z "$(raw_logs "$probe_dir")" ]]
)

test_killed_writer_raw_is_pruned_without_harming_a_peer() (
	local probe_dir="$TEST_HARNESS_ROOT/action-log-killed"
	local fake_bin="$TEST_HARNESS_ROOT/action-log-killed-date"
	mkdir -p "$probe_dir"
	install_constant_date "$fake_bin"

	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		start_action_log
		printf 'A1\n'
		sleep 30
	) >/dev/null &
	local a_pid=$!
	sleep 0.15
	kill -9 "$a_pid" 2>/dev/null || true
	wait "$a_pid" 2>/dev/null || true

	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# No grace: the abandoned capture is seconds old, and this test is about
		# what prune does once a capture is old enough to judge.
		DOTFILES_ACTION_LOG_RAW_GRACE_SECONDS=0
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		start_action_log
		printf 'B1\n'
		printf 'B2\n'
	) >/dev/null

	mapfile -t logs < <(finished_logs "$probe_dir")
	[[ "${#logs[@]}" -eq 1 ]] || return 1
	grep -qx B1 "${logs[0]}" || return 1
	grep -qx B2 "${logs[0]}" || return 1
	[[ -z "$(raw_logs "$probe_dir")" ]]
)

test_a_starting_peers_raw_capture_is_not_pruned() (
	# Break caught: a raw capture is created before its lock holder can take the
	# lock. In that window it looks exactly like one abandoned by a dead run, so
	# a concurrent prune deleted it -- and the starting run then failed to open
	# its own capture and reported "could not lock action log". Intermittently,
	# which is how it hid in the suite for so long.
	local probe_dir="$TEST_HARNESS_ROOT/action-log-starting"
	local fake_bin="$TEST_HARNESS_ROOT/action-log-starting-date"
	mkdir -p "$probe_dir"
	install_constant_date "$fake_bin"

	# A peer mid-startup: its capture exists and nothing holds the lock yet.
	local peer="$probe_dir/log/2026-01-01_00-00-00_000000000_999.log.raw"
	mkdir -p "$probe_dir/log"
	: >"$peer"

	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		start_action_log
		printf 'B1\n'
	) >/dev/null || return 1

	[[ -f "$peer" ]] || return 1

	# Once it is old enough to judge, the same capture is prunable: the grace
	# defers the decision, it does not abandon it.
	touch -d '2 hours ago' -- "$peer"
	(
		DOTFILES_DIR="$probe_dir"
		PATH="$fake_bin:/usr/bin:/bin"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		start_action_log
		printf 'C1\n'
	) >/dev/null || return 1

	[[ ! -e "$peer" ]]
)

test_a_surviving_child_does_not_hang_the_finalizer() (
	# Break caught: a bootstrap run printed every line of its install and then
	# stopped dead. tee sees EOF only once every writer has closed the log pipe,
	# and a child that outlived the run -- a probe left blocked on the docker
	# socket the operator was not yet in the group for -- still held one. The
	# finalizer waited for it forever, after the run had nothing left to say.
	local probe_dir="$TEST_HARNESS_ROOT/action-log-orphan"
	local go="$probe_dir/go"
	mkdir -p "$probe_dir/log"
	cat >"$go" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
DOTFILES_DIR="$1"
source "$2/scripts/lib/action_log.sh"
start_action_log
printf 'the last line of the run\n'
# Holds the write end of the log pipe past the end of the run.
sleep 120 &
EOF
	chmod 700 "$go"

	local started elapsed status=0
	started="$SECONDS"
	DOTFILES_ACTION_LOG_TEE_CLOSE_SECONDS=1 timeout 30 "$go" "$probe_dir" "$REPO_DIR" \
		>/dev/null 2>&1 || status=$?
	elapsed=$((SECONDS - started))

	# 124 is timeout's: the finalizer never returned.
	[[ "$status" -ne 124 ]] || return 1
	((elapsed < 15)) || return 1
	# And the capture it was finalizing is still a readable log.
	local written
	written="$(finished_logs "$probe_dir")"
	[[ -n "$written" ]] || return 1
	grep -Fqx 'the last line of the run' $written
)

expect_success 'a starting peer raw capture is not pruned' test_a_starting_peers_raw_capture_is_not_pruned
expect_success 'overlapping action logs keep separate complete output' test_overlapping_action_logs_keep_separate_complete_output
expect_success 'prune does not delete a live peer raw capture' test_prune_does_not_delete_a_live_peer_raw_capture
expect_success 'killed writer raw is pruned without harming a peer' test_killed_writer_raw_is_pruned_without_harming_a_peer
expect_success 'a surviving child does not hang the log finalizer' test_a_surviving_child_does_not_hang_the_finalizer

test_harness_cleanup
finish_tests
