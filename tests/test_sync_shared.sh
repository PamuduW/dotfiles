#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
# DF-006: the shared-library sync must identify checkouts by content, never by
# directory name. Naming decided the roles, so a checkout not called "dotfiles"
# was mistaken for the sibling: --check passed without comparing anything, and
# sync could delete a repository's own shared tree and refill it from an
# unrelated directory that merely had the right name.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

SYNC_REL='scripts/sync-shared.sh'

# A checkout skeleton carrying only what repo_role() inspects, plus a shared
# tree whose contents the test controls.
make_canonical() {
	local dir="$1" marker="${2:-canonical}"
	mkdir -p -- "$dir/scripts/lib/shared" "$dir/tests/lib/shared" "$dir/bin/bin"
	: >"$dir/scripts/install.sh"
	: >"$dir/bin/bin/dotfiles"
	printf '%s\n' "$marker" >"$dir/scripts/lib/shared/colors.sh"
	printf '%s\n' "$marker" >"$dir/tests/lib/shared/assert.sh"
	mkdir -p -- "$dir/scripts"
	cp -- "$REPO_DIR/$SYNC_REL" "$dir/$SYNC_REL"
	chmod +x -- "$dir/$SYNC_REL"
}

make_sibling() {
	local dir="$1" marker="${2:-sibling}"
	mkdir -p -- "$dir/scripts/lib/shared" "$dir/tests/lib/shared" "$dir/src"
	: >"$dir/src/cli.py"
	: >"$dir/agentos.yaml"
	printf '%s\n' "$marker" >"$dir/scripts/lib/shared/colors.sh"
	printf '%s\n' "$marker" >"$dir/tests/lib/shared/assert.sh"
	cp -- "$REPO_DIR/$SYNC_REL" "$dir/$SYNC_REL"
	chmod +x -- "$dir/$SYNC_REL"
}

workspace() {
	local dir="$TEST_HARNESS_ROOT/$1"
	rm -rf -- "$dir"
	mkdir -p -- "$dir"
	printf '%s\n' "$dir"
}

test_check_detects_drift_when_both_checkouts_are_renamed() (
	local work canonical sibling rc=0
	work="$(workspace renamed-both)"
	canonical="$work/my-dotfiles"
	sibling="$work/my-agentbot"
	make_canonical "$canonical"
	make_sibling "$sibling" canonical
	printf 'drifted\n' >>"$sibling/scripts/lib/shared/colors.sh"

	bash "$canonical/$SYNC_REL" --check >/dev/null 2>&1 || rc=$?
	[[ "$rc" -ne 0 ]]
)

test_check_passes_when_renamed_checkouts_agree() (
	local work canonical sibling
	work="$(workspace renamed-agree)"
	canonical="$work/my-dotfiles"
	sibling="$work/my-agentbot"
	make_canonical "$canonical"
	make_sibling "$sibling" canonical

	bash "$canonical/$SYNC_REL" --check >/dev/null 2>&1
)

test_sync_from_a_renamed_canonical_updates_the_renamed_sibling() (
	local work canonical sibling
	work="$(workspace renamed-sync)"
	canonical="$work/my-dotfiles"
	sibling="$work/my-agentbot"
	make_canonical "$canonical"
	make_sibling "$sibling"

	bash "$canonical/$SYNC_REL" >/dev/null 2>&1 || return 1

	grep -qx canonical "$sibling/scripts/lib/shared/colors.sh" || return 1
	grep -qx canonical "$canonical/scripts/lib/shared/colors.sh"
)

test_an_impostor_directory_never_overwrites_this_repository() (
	local work fork impostor before after
	work="$(workspace impostor)"
	fork="$work/dotfiles-fork"
	impostor="$work/dotfiles"
	make_canonical "$fork"
	mkdir -p -- "$impostor/scripts/lib/shared"
	printf 'impostor\n' >"$impostor/scripts/lib/shared/colors.sh"

	before="$(find "$fork/scripts/lib/shared" -type f | sort)"
	bash "$fork/$SYNC_REL" >/dev/null 2>&1 || true
	after="$(find "$fork/scripts/lib/shared" -type f | sort)"

	[[ "$before" == "$after" ]] || return 1
	grep -qx canonical "$fork/scripts/lib/shared/colors.sh"
)

test_a_wrongly_named_counterpart_fails_loudly() (
	local work fork impostor rc=0 output
	work="$(workspace named-impostor)"
	fork="$work/dotfiles-fork"
	impostor="$work/agent_bootstrap"
	make_canonical "$fork"
	mkdir -p -- "$impostor/scripts/lib/shared"

	output="$(bash "$fork/$SYNC_REL" --check 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'is not a agent_bootstrap checkout'* ]]
)

test_an_unidentifiable_checkout_fails_loudly() (
	local work stranger rc=0 output
	work="$(workspace stranger)"
	stranger="$work/something-else"
	mkdir -p -- "$stranger/scripts/lib/shared"
	cp -- "$REPO_DIR/$SYNC_REL" "$stranger/$SYNC_REL"

	output="$(bash "$stranger/$SYNC_REL" --check 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'is neither the dotfiles nor the agent_bootstrap checkout'* ]]
)

test_an_absent_counterpart_stays_a_no_op() (
	local work canonical output
	work="$(workspace absent)"
	canonical="$work/my-dotfiles"
	make_canonical "$canonical"

	output="$(bash "$canonical/$SYNC_REL" --check 2>&1)" || return 1
	[[ "$output" == *'nothing to sync'* ]]
)

test_two_counterparts_are_reported_as_ambiguous() (
	local work canonical rc=0 output
	work="$(workspace ambiguous)"
	canonical="$work/my-dotfiles"
	make_canonical "$canonical"
	make_sibling "$work/agentbot-one"
	make_sibling "$work/agentbot-two"

	output="$(bash "$canonical/$SYNC_REL" --check 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'more than one agent_bootstrap checkout'* ]]
)

expect_success 'check detects drift when both checkouts are renamed' test_check_detects_drift_when_both_checkouts_are_renamed
expect_success 'check passes when renamed checkouts agree' test_check_passes_when_renamed_checkouts_agree
expect_success 'sync from a renamed canonical updates the renamed sibling' test_sync_from_a_renamed_canonical_updates_the_renamed_sibling
expect_success 'an impostor directory never overwrites this repository' test_an_impostor_directory_never_overwrites_this_repository
expect_success 'a wrongly named counterpart fails loudly' test_a_wrongly_named_counterpart_fails_loudly
expect_success 'an unidentifiable checkout fails loudly' test_an_unidentifiable_checkout_fails_loudly
expect_success 'an absent counterpart stays a no-op' test_an_absent_counterpart_stays_a_no_op
expect_success 'two counterparts are reported as ambiguous' test_two_counterparts_are_reported_as_ambiguous

test_harness_cleanup
finish_tests
