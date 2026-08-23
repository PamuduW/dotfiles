#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

DOTFILES_DIR="$REPO_DIR"
_msg() { printf '%s\n' "$*"; }
_err() { printf '%s\n' "$*" >&2; }
C_BOLD='' C_ORANGE='' C_GREEN='' C_RESET=''
[[ -f "$REPO_DIR/scripts/lib/full_update.sh" ]] && source "$REPO_DIR/scripts/lib/full_update.sh"

test_success_runs_all_stages_without_confirmation() (
	local events="$TEST_HARNESS_ROOT/full-update-success.events"
	: >"$events"
	_dotfiles_run_update() {
		printf 'dotfiles:%s:%s\n' "$1" "$2" >>"$events"
		[[ "$1" == _dotfiles_approve_repo_update && "$2" == true ]]
	}
	_dotfiles_approve_repo_update() {
		printf 'unexpected-confirm\n' >>"$events"
		return 0
	}
	agentbot() {
		printf 'agentbot:%s:confirm=%s\n' "$*" "${AGENTBOT_INSTALL_CONFIRM:-unset}" >>"$events"
	}

	cmd_full_update >/dev/null || return 1
	[[ "$(<"$events")" == $'dotfiles:_dotfiles_approve_repo_update:true\nagentbot:install:confirm=yes\nagentbot:update --yes:confirm=unset' ]]
)

test_dotfiles_change_restarts_once_and_second_change_stops() (
	local events="$TEST_HARNESS_ROOT/full-update-dotfiles-restart.events"
	: >"$events"
	_dotfiles_run_update() { return 2; }
	full_update_restart_dotfiles() {
		printf 'restart:%s\n' "$*" >>"$events"
		return 72
	}

	local rc=0
	cmd_full_update >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 72 && "$(<"$events")" == 'restart:--resume-after-dotfiles-repo' ]] || return 1
	rc=0
	cmd_full_update --resume-after-dotfiles-repo >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 1 && "$(wc -l <"$events")" -eq 1 ]]
)

test_agentbot_restarts_once_across_install_and_update() (
	local events="$TEST_HARNESS_ROOT/full-update-agentbot-restart.events" install_calls=0
	: >"$events"
	_dotfiles_run_update() { return 0; }
	agentbot() {
		printf '%s\n' "$*" >>"$events"
		if [[ "$1" == install ]]; then
			install_calls=$((install_calls + 1))
			((install_calls == 1)) && return 2
		fi
		return 0
	}

	cmd_full_update >/dev/null || return 1
	[[ "$(<"$events")" == $'install\ninstall\nupdate --yes' ]]
)

test_second_agentbot_repository_change_stops() (
	local events="$TEST_HARNESS_ROOT/full-update-agentbot-loop.events" install_calls=0
	: >"$events"
	_dotfiles_run_update() { return 0; }
	agentbot() {
		printf '%s\n' "$*" >>"$events"
		if [[ "$1" == install ]]; then
			install_calls=$((install_calls + 1))
			((install_calls == 1)) && return 2
			return 0
		fi
		return 2
	}

	local rc=0
	cmd_full_update >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 1 && "$(<"$events")" == $'install\ninstall\nupdate --yes' ]]
)

expect_success 'full-update runs Dotfiles, Agentbot install, and Agentbot update without confirmation' test_success_runs_all_stages_without_confirmation
expect_success 'Dotfiles repository change restarts once and a second change stops' test_dotfiles_change_restarts_once_and_second_change_stops
expect_success 'Agentbot repository change reruns install once before update' test_agentbot_restarts_once_across_install_and_update
expect_success 'a second Agentbot repository change stops the loop' test_second_agentbot_repository_change_stops

finish_tests
