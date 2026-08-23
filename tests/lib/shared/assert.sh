#!/usr/bin/env bash
# shellcheck shell=bash
# Test reporting and assertions, shared verbatim between this repository and
# its sibling. Edit the copy in dotfiles/, then run scripts/sync-shared.sh;
# the gate fails if the two copies diverge.

test_harness_report_init() {
	passed=0
	failed=0
}

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
	if "$@"; then pass "$name"; else fail "$name"; fi
}

expect_failure() {
	local name="$1"
	shift
	if "$@"; then fail "$name"; else pass "$name"; fi
}

# Some older suites use `check`; keep it as a reporting alias while assertions
# and counters live in this one harness.
check() {
	expect_success "$@"
}

assert_eq() {
	[[ "$1" == "$2" ]]
}

assert_contains() {
	[[ "$1" == *"$2"* ]]
}

assert_not_contains() {
	[[ "$1" != *"$2"* ]]
}

assert_status() {
	local expected="$1"
	shift
	set +e
	"$@"
	local actual=$?
	set -e
	[[ "$actual" -eq "$expected" ]]
}

assert_file_contains() {
	grep -Fq -- "$2" "$1"
}

finish_tests() {
	printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
	((failed == 0))
}
