#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
# DF-003: claude-rc is removed; migration unlinks only this checkout's leftover.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

test_claude_rc_executable_is_absent() (
	[[ ! -e "$REPO_DIR/bin/bin/claude-rc" ]]
)

test_claude_rc_is_not_a_managed_stow_target() (
	! _dotfiles_managed_targets | grep -Fq 'claude-rc'
)

test_claude_rc_is_not_a_dotfiles_probe_target() (
	! grep -Fq 'claude-rc' "$REPO_DIR/scripts/lib/components/probes.sh"
)

test_claude_rc_is_not_advertised_in_current_docs() (
	! grep -Eq 'claude-rc start|claude-rc stop' "$REPO_DIR/README.md" || return 1
	! grep -Fq 'claude-rc' "$REPO_DIR/docs/installation.md" || return 1
	! grep -Eq 'claude-rc start|claude-rc stop' "$REPO_DIR/docs/codex-and-remote-control.md"
)

test_backup_leaves_a_regular_claude_rc_file() (
	local fake_home="$TEST_HARNESS_ROOT/claude-rc-backup-home"
	local fake_repo="$TEST_HARNESS_ROOT/claude-rc-backup-repo"
	mkdir -p "$fake_home/bin" "$fake_repo"
	printf 'user helper\n' >"$fake_home/bin/claude-rc"
	printf 'old codex helper\n' >"$fake_home/bin/codex-rc"
	log_step() { :; }
	log_ok() { :; }
	HOME="$fake_home" DOTFILES_DIR="$fake_repo" backup_existing_dotfiles
	[[ -f "$fake_home/bin/claude-rc" ]] || return 1
	[[ "$(<"$fake_home/bin/claude-rc")" == 'user helper' ]] || return 1
	[[ ! -e "$fake_home/bin/codex-rc" ]] || return 1
	find "$fake_repo" -path '*/bin/codex-rc' -type f -print -quit | grep -q .
)

test_probe_does_not_require_claude_rc() (
	local fake_home="$TEST_HARNESS_ROOT/claude-rc-probe-home"
	local target
	mkdir -p "$fake_home/bin"
	ln -s "$REPO_DIR/bash/.bashrc" "$fake_home/.bashrc"
	ln -s "$REPO_DIR/bash/.bash_aliases" "$fake_home/.bash_aliases"
	ln -s "$REPO_DIR/readline/.inputrc" "$fake_home/.inputrc"
	for target in ex clip dotfiles; do
		ln -s "$REPO_DIR/bin/bin/$target" "$fake_home/bin/$target"
	done
	local output
	output="$(HOME="$fake_home" _comp_probe_dotfiles)"
	[[ "$output" == 'missing|2 managed stow target(s) missing or incorrect' ]]
)

setup_claude_rc_control_paths() {
	local home="$1"
	mkdir -p "$home/bin"
	ln -s "$REPO_DIR/bin/bin/codex-rc" "$home/bin/codex-rc"
	ln -s /usr/bin/true "$home/bin/ex"
	printf 'keep-me\n' >"$home/bin/custom-tool"
}

assert_claude_rc_controls_untouched() {
	local home="$1"
	[[ "$(readlink -- "$home/bin/codex-rc")" == "$REPO_DIR/bin/bin/codex-rc" ]] || return 1
	[[ "$(readlink -- "$home/bin/ex")" == /usr/bin/true ]] || return 1
	[[ "$(<"$home/bin/custom-tool")" == 'keep-me' ]]
}

test_migration_removes_only_an_owned_claude_rc_symlink() (
	local fake_home="$TEST_HARNESS_ROOT/claude-rc-owned-home"
	setup_claude_rc_control_paths "$fake_home"
	ln -s "$REPO_DIR/bin/bin/claude-rc" "$fake_home/bin/claude-rc"
	HOME="$fake_home" DOTFILES_DIR="$REPO_DIR" remove_obsolete_claude_rc_link
	[[ ! -e "$fake_home/bin/claude-rc" && ! -L "$fake_home/bin/claude-rc" ]] || return 1
	assert_claude_rc_controls_untouched "$fake_home"
)

test_migration_preserves_a_regular_claude_rc_file() (
	local fake_home="$TEST_HARNESS_ROOT/claude-rc-file-home"
	setup_claude_rc_control_paths "$fake_home"
	printf 'user helper\n' >"$fake_home/bin/claude-rc"
	HOME="$fake_home" DOTFILES_DIR="$REPO_DIR" remove_obsolete_claude_rc_link
	[[ -f "$fake_home/bin/claude-rc" ]] || return 1
	[[ "$(<"$fake_home/bin/claude-rc")" == 'user helper' ]] || return 1
	assert_claude_rc_controls_untouched "$fake_home"
)

test_migration_preserves_a_foreign_claude_rc_symlink() (
	local fake_home="$TEST_HARNESS_ROOT/claude-rc-foreign-home"
	local other="$TEST_HARNESS_ROOT/other-claude-rc"
	setup_claude_rc_control_paths "$fake_home"
	printf 'foreign\n' >"$other"
	ln -s "$other" "$fake_home/bin/claude-rc"
	HOME="$fake_home" DOTFILES_DIR="$REPO_DIR" remove_obsolete_claude_rc_link
	[[ -L "$fake_home/bin/claude-rc" ]] || return 1
	[[ "$(readlink -- "$fake_home/bin/claude-rc")" == "$other" ]] || return 1
	assert_claude_rc_controls_untouched "$fake_home"
)

test_migration_is_a_noop_when_claude_rc_is_absent() (
	local fake_home="$TEST_HARNESS_ROOT/claude-rc-missing-home"
	setup_claude_rc_control_paths "$fake_home"
	HOME="$fake_home" DOTFILES_DIR="$REPO_DIR" remove_obsolete_claude_rc_link
	[[ ! -e "$fake_home/bin/claude-rc" && ! -L "$fake_home/bin/claude-rc" ]] || return 1
	assert_claude_rc_controls_untouched "$fake_home"
)

test_stow_dotfiles_removes_an_owned_claude_rc_symlink() (
	local fake_home="$TEST_HARNESS_ROOT/claude-rc-stow-home"
	mkdir -p "$fake_home/bin"
	ln -s "$REPO_DIR/bin/bin/claude-rc" "$fake_home/bin/claude-rc"
	ln -sfn -- _test_fake_command "$TEST_FAKE_BIN/stow"
	test_harness_configure_fake stow 0
	log_step() { :; }
	log_ok() { :; }
	HOME="$fake_home" DOTFILES_DIR="$REPO_DIR" PATH="$TEST_FAKE_BIN:$PATH" stow_dotfiles >/dev/null
	[[ ! -e "$fake_home/bin/claude-rc" && ! -L "$fake_home/bin/claude-rc" ]]
)

test_restow_invokes_claude_rc_migration() (
	grep -Fq remove_obsolete_claude_rc_link "$REPO_DIR/bin/bin/dotfiles"
)

expect_success 'claude-rc executable is absent from the Stow package' test_claude_rc_executable_is_absent
expect_success 'claude-rc is not a managed Stow backup target' test_claude_rc_is_not_a_managed_stow_target
expect_success 'claude-rc is not a Dotfiles probe target' test_claude_rc_is_not_a_dotfiles_probe_target
expect_success 'current docs do not advertise claude-rc' test_claude_rc_is_not_advertised_in_current_docs
expect_success 'Stow backup leaves a regular claude-rc file and still backs up codex-rc' test_backup_leaves_a_regular_claude_rc_file
expect_success 'Dotfiles probe does not require a claude-rc link' test_probe_does_not_require_claude_rc
expect_success 'migration removes only an owned claude-rc symlink' test_migration_removes_only_an_owned_claude_rc_symlink
expect_success 'migration preserves a regular claude-rc file' test_migration_preserves_a_regular_claude_rc_file
expect_success 'migration preserves a foreign claude-rc symlink' test_migration_preserves_a_foreign_claude_rc_symlink
expect_success 'migration is a no-op when claude-rc is absent' test_migration_is_a_noop_when_claude_rc_is_absent
expect_success 'stow_dotfiles removes an owned claude-rc symlink' test_stow_dotfiles_removes_an_owned_claude_rc_symlink
expect_success 'dotfiles restow invokes the claude-rc migration' test_restow_invokes_claude_rc_migration

test_harness_cleanup
finish_tests
