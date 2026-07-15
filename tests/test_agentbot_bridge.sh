#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

ROOT="$(cd "$TEST_DIR/.." && pwd)"
DOTFILES_DIR="$ROOT"
source "$ROOT/scripts/menus/agentbot.sh"

passed=0 failed=0
pass() { printf 'ok - %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; failed=$((failed + 1)); }
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

prepare_existing() {
	AGENTBOT_HOME="$(test_harness_create_fake_sibling agent_bootstrap)"
	DOTFILES_AGENTBOT_URL='git@github.com:PamuduW/agent_bootstrap.git'
	test_harness_configure_fake git 0 "${1:-git@github.com:PamuduW/agent_bootstrap.git}"
	test_harness_configure_fake sibling-install 0 ''
	export AGENTBOT_HOME DOTFILES_AGENTBOT_URL
	test_harness_reset_logs
}

test_existing_launches_with_caller() {
	prepare_existing
	dotfiles_launch_agentbot >/dev/null
	grep -Fqx 'sibling-install' "$TEST_COMMAND_LOG"
}

test_wrong_origin_stops() {
	prepare_existing 'https://credential@github.com/PamuduW/agent_bootstrap.git'
	set +e
	dotfiles_launch_agentbot >/dev/null 2>&1
	local rc=$?
	set -e
	[[ "$rc" -ne 0 ]] && ! grep -Fq 'sibling-install' "$TEST_COMMAND_LOG"
}

test_declined_clone_does_not_run() {
	AGENTBOT_HOME="$TEST_HARNESS_ROOT/missing-agentbot"
	DOTFILES_AGENTBOT_CONFIRM=no
	export AGENTBOT_HOME DOTFILES_AGENTBOT_CONFIRM
	test_harness_clear_fake git
	test_harness_reset_logs
	dotfiles_launch_agentbot >"$TEST_HARNESS_ROOT/decline.out"
	! grep -Fq $'git\tclone' "$TEST_COMMAND_LOG" && grep -Fq 'launch cancelled' "$TEST_HARNESS_ROOT/decline.out"
}

test_clone_failure_stops() {
	AGENTBOT_HOME="$TEST_HARNESS_ROOT/clone-fails"
	DOTFILES_AGENTBOT_CONFIRM=yes
	export AGENTBOT_HOME DOTFILES_AGENTBOT_CONFIRM
	test_harness_configure_fake git 24 ''
	set +e
	dotfiles_launch_agentbot >/dev/null 2>&1
	local rc=$?
	set -e
	[[ "$rc" -ne 0 && ! -e "$AGENTBOT_HOME/install.sh" ]]
}

check 'existing allowlisted Agentbot launches with SETUP_CALLER=dotfiles' test_existing_launches_with_caller
check 'wrong or token-bearing Agentbot origin is rejected' test_wrong_origin_stops
check 'declining a missing Agentbot clone is non-mutating' test_declined_clone_does_not_run
check 'Agentbot clone failure stops before launch' test_clone_failure_stops

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
test_harness_cleanup
((failed == 0))
