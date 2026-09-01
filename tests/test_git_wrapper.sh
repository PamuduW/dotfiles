#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
PATH="$ORIGINAL_PATH"
export PATH
test_harness_report_init

REAL_GIT="$(command -v git)"
WRAPPER="$ROOT/bin/bin/git"
export GIT_ALLOW_PROTOCOL=file GIT_CONFIG_NOSYSTEM=1

init_repo() {
	local repo="$1"
	mkdir -p -- "$repo"
	"$REAL_GIT" -C "$repo" init -q -b main
	"$REAL_GIT" -C "$repo" config user.name 'Dotfiles Test'
	"$REAL_GIT" -C "$repo" config user.email 'dotfiles-test@example.invalid'
}

commit_file() {
	local repo="$1" path="$2" content="$3" message="$4"
	printf '%s\n' "$content" >"$repo/$path"
	"$REAL_GIT" -C "$repo" add -- "$path"
	"$REAL_GIT" -C "$repo" commit -q -m "$message"
}

configure_identity() {
	local repo="$1"
	"$REAL_GIT" -C "$repo" config user.name 'Dotfiles Test'
	"$REAL_GIT" -C "$repo" config user.email 'dotfiles-test@example.invalid'
}

test_sub_add_registers_an_existing_nested_repository() (
	local parent="$TEST_HARNESS_ROOT/sub-add-parent"
	local source="$TEST_HARNESS_ROOT/sub-add-source"
	local remote="$TEST_HARNESS_ROOT/sub-add-remote.git"
	local mode

	init_repo "$parent"
	commit_file "$parent" README.md parent base
	init_repo "$source"
	commit_file "$source" README.md child base
	"$REAL_GIT" clone -q --bare "$source" "$remote"
	"$REAL_GIT" -C "$parent" clone -q "$remote" repoB

	DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$parent" sub add repoB >/dev/null || return 1

	[[ "$("$REAL_GIT" -C "$parent" config -f .gitmodules --get submodule.repoB.path)" == repoB ]] || return 1
	[[ "$("$REAL_GIT" -C "$parent" config -f .gitmodules --get submodule.repoB.url)" == "$remote" ]] || return 1
	mode="$("$REAL_GIT" -C "$parent" ls-files --stage -- repoB | awk '{print $1}')"
	[[ "$mode" == 160000 ]]
)

test_clone_initializes_declared_submodules_by_default() (
	local child_source="$TEST_HARNESS_ROOT/clone-child-source"
	local child_remote="$TEST_HARNESS_ROOT/clone-child.git"
	local parent_source="$TEST_HARNESS_ROOT/clone-parent-source"
	local parent_remote="$TEST_HARNESS_ROOT/clone-parent.git"
	local checkout="$TEST_HARNESS_ROOT/clone-checkout"

	init_repo "$child_source"
	commit_file "$child_source" child.txt child base
	"$REAL_GIT" clone -q --bare "$child_source" "$child_remote"
	init_repo "$parent_source"
	commit_file "$parent_source" parent.txt parent base
	"$REAL_GIT" -C "$parent_source" -c protocol.file.allow=always submodule add -q "$child_remote" repoB
	"$REAL_GIT" -C "$parent_source" commit -q -am 'add child submodule'
	"$REAL_GIT" clone -q --bare "$parent_source" "$parent_remote"

	DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" clone -q "$parent_remote" "$checkout" || return 1

	[[ "$(<"$checkout/repoB/child.txt")" == child ]]
)

test_commit_rejects_an_undeclared_gitlink() (
	local parent="$TEST_HARNESS_ROOT/undeclared-parent"
	local nested="$parent/repoB"
	local output rc=0

	init_repo "$parent"
	commit_file "$parent" README.md parent base
	init_repo "$nested"
	commit_file "$nested" README.md child base
	"$REAL_GIT" -C "$parent" add repoB 2>/dev/null

	output="$(DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$parent" commit -m 'accidental gitlink' 2>&1)" || rc=$?

	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'repoB is a staged nested repository but is not declared in .gitmodules'* ]] || return 1
	[[ "$("$REAL_GIT" -C "$parent" rev-list --count HEAD)" == 1 ]]
)

test_add_all_leaves_an_undeclared_nested_repository_untracked() (
	local parent="$TEST_HARNESS_ROOT/add-all-parent"
	local nested="$parent/repoB"
	local output

	init_repo "$parent"
	commit_file "$parent" README.md parent base
	init_repo "$nested"
	commit_file "$nested" README.md child base
	printf '%s\n' ordinary >"$parent/ordinary.txt"

	output="$(DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$parent" add --all 2>&1)" || return 1

	[[ "$output" == *'Left nested repository untracked: repoB'* ]] || return 1
	[[ "$("$REAL_GIT" -C "$parent" diff --cached --name-only)" == ordinary.txt ]] || return 1
	[[ "$("$REAL_GIT" -C "$parent" status --short -- repoB)" == '?? repoB/' ]]
)

test_add_all_stages_an_updated_declared_submodule() (
	local parent="$TEST_HARNESS_ROOT/declared-parent"
	local source="$TEST_HARNESS_ROOT/declared-source"
	local remote="$TEST_HARNESS_ROOT/declared-remote.git"

	init_repo "$parent"
	commit_file "$parent" README.md parent base
	init_repo "$source"
	commit_file "$source" README.md child base
	"$REAL_GIT" clone -q --bare "$source" "$remote"
	"$REAL_GIT" -C "$parent" clone -q "$remote" repoB
	DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$parent" sub add repoB >/dev/null
	"$REAL_GIT" -C "$parent" commit -q -m 'add submodule'
	configure_identity "$parent/repoB"
	commit_file "$parent/repoB" change.txt changed changed

	DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$parent" add --all >/dev/null || return 1

	[[ "$("$REAL_GIT" -C "$parent" diff --cached --name-only)" == repoB ]]
)

test_commit_fast_forwards_from_upstream_before_committing() (
	local source="$TEST_HARNESS_ROOT/pull-source"
	local remote="$TEST_HARNESS_ROOT/pull-remote.git"
	local local_repo="$TEST_HARNESS_ROOT/pull-local"
	local peer="$TEST_HARNESS_ROOT/pull-peer"
	local remote_commit output

	init_repo "$source"
	commit_file "$source" README.md base base
	"$REAL_GIT" clone -q --bare "$source" "$remote"
	"$REAL_GIT" clone -q "$remote" "$local_repo"
	"$REAL_GIT" clone -q "$remote" "$peer"
	configure_identity "$local_repo"
	configure_identity "$peer"
	commit_file "$peer" remote.txt remote remote
	"$REAL_GIT" -C "$peer" push -q origin main
	remote_commit="$("$REAL_GIT" -C "$peer" rev-parse HEAD)"
	printf '%s\n' local >"$local_repo/local.txt"
	"$REAL_GIT" -C "$local_repo" add local.txt

	output="$(DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$local_repo" commit -q -m local 2>&1)" || return 1

	[[ "$output" == *'On branch main'* ]] || return 1
	"$REAL_GIT" -C "$local_repo" merge-base --is-ancestor "$remote_commit" HEAD || return 1
	[[ "$("$REAL_GIT" -C "$local_repo" rev-list --count HEAD)" == 3 ]]
)

test_commit_stops_when_fast_forward_would_overwrite_local_changes() (
	local source="$TEST_HARNESS_ROOT/conflict-source"
	local remote="$TEST_HARNESS_ROOT/conflict-remote.git"
	local local_repo="$TEST_HARNESS_ROOT/conflict-local"
	local peer="$TEST_HARNESS_ROOT/conflict-peer"
	local output rc=0 base_commit

	init_repo "$source"
	commit_file "$source" shared.txt base base
	"$REAL_GIT" clone -q --bare "$source" "$remote"
	"$REAL_GIT" clone -q "$remote" "$local_repo"
	"$REAL_GIT" clone -q "$remote" "$peer"
	configure_identity "$local_repo"
	configure_identity "$peer"
	base_commit="$("$REAL_GIT" -C "$local_repo" rev-parse HEAD)"
	commit_file "$peer" shared.txt remote remote
	"$REAL_GIT" -C "$peer" push -q origin main
	printf '%s\n' local >"$local_repo/shared.txt"
	"$REAL_GIT" -C "$local_repo" add shared.txt

	output="$(DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$local_repo" commit -m local 2>&1)" || rc=$?

	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'could not be fast-forwarded without conflicts'* ]] || return 1
	[[ "$("$REAL_GIT" -C "$local_repo" rev-parse HEAD)" == "$base_commit" ]]
)

test_commit_stops_when_fetch_fails() (
	local source="$TEST_HARNESS_ROOT/fetch-source"
	local remote="$TEST_HARNESS_ROOT/fetch-remote.git"
	local local_repo="$TEST_HARNESS_ROOT/fetch-local"
	local output rc=0 base_commit

	init_repo "$source"
	commit_file "$source" README.md base base
	"$REAL_GIT" clone -q --bare "$source" "$remote"
	"$REAL_GIT" clone -q "$remote" "$local_repo"
	configure_identity "$local_repo"
	base_commit="$("$REAL_GIT" -C "$local_repo" rev-parse HEAD)"
	"$REAL_GIT" -C "$local_repo" remote set-url origin "$TEST_HARNESS_ROOT/missing-remote.git"
	printf '%s\n' local >"$local_repo/local.txt"
	"$REAL_GIT" -C "$local_repo" add local.txt

	output="$(DOTFILES_REAL_GIT="$REAL_GIT" "$WRAPPER" -C "$local_repo" commit -m local 2>&1)" || rc=$?

	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'git commit stopped: fetch failed for origin/main'* ]] || return 1
	[[ "$("$REAL_GIT" -C "$local_repo" rev-parse HEAD)" == "$base_commit" ]]
)

expect_success 'git sub add registers an existing nested repository' test_sub_add_registers_an_existing_nested_repository
expect_success 'git clone initializes declared submodules by default' test_clone_initializes_declared_submodules_by_default
expect_success 'git commit rejects an undeclared nested-repository gitlink' test_commit_rejects_an_undeclared_gitlink
expect_success 'git add --all leaves undeclared nested repositories untracked' test_add_all_leaves_an_undeclared_nested_repository_untracked
expect_success 'git add --all stages an updated declared submodule' test_add_all_stages_an_updated_declared_submodule
expect_success 'git commit fast-forwards from upstream before committing' test_commit_fast_forwards_from_upstream_before_committing
expect_success 'git commit stops when fast-forward would overwrite local changes' test_commit_stops_when_fast_forward_would_overwrite_local_changes
expect_success 'git commit stops when fetch fails' test_commit_stops_when_fetch_fails

test_harness_cleanup
finish_tests
