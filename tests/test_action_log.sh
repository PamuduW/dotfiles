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

expect_success 'overlapping action logs keep separate complete output' test_overlapping_action_logs_keep_separate_complete_output
expect_success 'prune does not delete a live peer raw capture' test_prune_does_not_delete_a_live_peer_raw_capture
expect_success 'killed writer raw is pruned without harming a peer' test_killed_writer_raw_is_pruned_without_harming_a_peer

test_harness_cleanup
finish_tests
