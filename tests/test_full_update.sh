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

test_success_runs_dotfiles_then_agentbot_full() (
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
		[[ "$*" == 'help full' || "$*" == 'full' || "$*" == doctor ]]
	}

	cmd_full_update >/dev/null || return 1
	[[ "$(<"$events")" == $'dotfiles:_dotfiles_approve_repo_update:true\nagentbot:help full:confirm=unset\nagentbot:full:confirm=yes\nagentbot:doctor:confirm=unset' ]]
)

test_legacy_agentbot_bootstraps_once_before_full() (
	local events="$TEST_HARNESS_ROOT/full-update-legacy-agentbot.events"
	local supports_full=false
	: >"$events"
	_dotfiles_run_update() { return 0; }
	agentbot() {
		printf 'agentbot:%s:confirm=%s\n' "$*" "${AGENTBOT_INSTALL_CONFIRM:-unset}" >>"$events"
		case "$*" in
		'help full')
			[[ "$supports_full" == true ]] && return 0
			return 2
			;;
		install)
			supports_full=true
			return 2
			;;
		full | doctor) return 0 ;;
		esac
		return 64
	}

	cmd_full_update >/dev/null || return 1
	[[ "$(<"$events")" == $'agentbot:help full:confirm=unset\nagentbot:install:confirm=yes\nagentbot:help full:confirm=unset\nagentbot:full:confirm=yes\nagentbot:doctor:confirm=unset' ]]
)

test_agentbot_bootstrap_stops_if_full_is_still_unavailable() (
	local events="$TEST_HARNESS_ROOT/full-update-incompatible-agentbot.events"
	local output rc=0
	: >"$events"
	_dotfiles_run_update() { return 0; }
	agentbot() {
		printf 'agentbot:%s\n' "$*" >>"$events"
		case "$*" in
		'help full') return 2 ;;
		install) return 0 ;;
		esac
		return 64
	}

	output="$(cmd_full_update 2>&1)" || rc=$?
	[[ "$rc" -eq 1 ]] || return 1
	[[ "$output" == *'still does not support agentbot full'* ]] || return 1
	[[ "$(<"$events")" == $'agentbot:help full\nagentbot:install\nagentbot:help full' ]]
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

# Agentbot owns its own install-then-update sequencing and restart budget now,
# so Dotfiles only reads its exit contract. Exit 2 means the Agentbot checkout
# moved forward mid-run and the user should rerun.
test_agentbot_repository_change_stops_with_guidance() (
	local output rc=0
	_dotfiles_run_update() { return 0; }
	agentbot() {
		[[ "$*" == 'help full' ]] && return 0
		return 2
	}

	output="$(cmd_full_update 2>&1)" || rc=$?
	[[ "$rc" -eq 1 ]] || return 1
	[[ "$output" == *'rerun dotfiles full-update'* ]]
)

test_agentbot_failure_propagates_its_status() (
	local rc=0
	_dotfiles_run_update() { return 0; }
	agentbot() {
		[[ "$*" == 'help full' ]] && return 0
		return 23
	}

	cmd_full_update >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 23 ]]
)

test_agentbot_capability_failure_propagates_its_status() (
	local rc=0
	_dotfiles_run_update() { return 0; }
	agentbot() { return 42; }

	cmd_full_update >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 42 ]]
)

test_missing_agentbot_is_reported_not_ignored() (
	local rc=0
	_dotfiles_run_update() { return 0; }
	command() {
		[[ "$*" == '-v agentbot' ]] && return 1
		builtin command "$@"
	}

	cmd_full_update >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 127 ]]
)

test_full_update_reports_resolved_launcher_identity() (
	local fake_root="$TEST_HARNESS_ROOT/agentbot" output
	mkdir -p "$fake_root/bin"
	printf '#!/bin/sh\nexit 0\n' >"$fake_root/bin/agentbot"
	chmod 700 "$fake_root/bin/agentbot"
	command() {
		[[ "$*" == '-v agentbot' ]] && {
			printf '%s\n' "$fake_root/bin/agentbot"
			return 0
		}
		builtin command "$@"
	}
	output="$(FULL_UPDATE_EXPECTED_AGENTBOT_HOME="$fake_root" full_update_print_identity)" || return 1
	grep -Fq "Dotfiles checkout: $DOTFILES_DIR" <<<"$output" || return 1
	grep -Fq "Agentbot checkout: $fake_root" <<<"$output"
)

test_full_update_refuses_unexpected_agentbot_checkout() (
	local fake_root="$TEST_HARNESS_ROOT/unexpected-agentbot" rc=0 output
	mkdir -p "$fake_root/bin"
	printf '#!/bin/sh\nexit 0\n' >"$fake_root/bin/agentbot"
	chmod 700 "$fake_root/bin/agentbot"
	command() {
		[[ "$*" == '-v agentbot' ]] && {
			printf '%s\n' "$fake_root/bin/agentbot"
			return 0
		}
		builtin command "$@"
	}
	output="$(FULL_UPDATE_EXPECTED_AGENTBOT_HOME="$TEST_HARNESS_ROOT/expected-agentbot" full_update_print_identity 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	grep -Fq 'Refusing unexpected Agentbot checkout' <<<"$output"
)

test_postflight_distinguishes_warnings_errors_and_health() (
	local output rc=0
	cmd_doctor() { return 0; }
	agentbot() {
		[[ "$*" == doctor ]] && return 0
		return 64
	}
	output="$(full_update_postflight)" || rc=$?
	[[ "$rc" -eq 0 && "$output" == *'Full system update completed.'* ]] || return 1

	full_update_agentbot_doctor() { return 10; }
	rc=0
	output="$(full_update_postflight)" || rc=$?
	[[ "$rc" -eq 0 && "$output" == *'completed with warnings'* ]] || return 1

	full_update_agentbot_doctor() { return 0; }
	cmd_doctor() { return 1; }
	rc=0
	output="$(full_update_postflight)" || rc=$?
	[[ "$rc" -ne 0 && "$output" == *'Updates succeeded; system needs attention'* ]]
)

test_agentbot_doctor_warning_output_maps_to_warning_state() (
	agentbot() {
		[[ "$*" == doctor ]] || return 64
		printf '0 error(s), 5 warning(s).\n'
	}
	local output rc=0
	output="$(full_update_agentbot_doctor)" || rc=$?
	[[ "$rc" -eq 10 && "$output" == *'5 warning(s)'* ]]
)

expect_success 'full-update runs Dotfiles, then one Agentbot full run' test_success_runs_dotfiles_then_agentbot_full
expect_success 'a legacy Agentbot bootstraps once before full' test_legacy_agentbot_bootstraps_once_before_full
expect_success 'an incompatible Agentbot stops after one bootstrap attempt' test_agentbot_bootstrap_stops_if_full_is_still_unavailable
expect_success 'Dotfiles repository change restarts once and a second change stops' test_dotfiles_change_restarts_once_and_second_change_stops
expect_success 'Agentbot repository change stops with rerun guidance' test_agentbot_repository_change_stops_with_guidance
expect_success 'Agentbot failure status propagates unchanged' test_agentbot_failure_propagates_its_status
expect_success 'Agentbot capability failure status propagates unchanged' test_agentbot_capability_failure_propagates_its_status
expect_success 'a missing agentbot is reported, not silently skipped' test_missing_agentbot_is_reported_not_ignored
expect_success 'full-update reports resolved launcher and checkout identity' test_full_update_reports_resolved_launcher_identity
expect_success 'full-update refuses an unexpected Agentbot checkout' test_full_update_refuses_unexpected_agentbot_checkout
expect_success 'postflight distinguishes healthy warning and error outcomes' test_postflight_distinguishes_warnings_errors_and_health
expect_success 'Agentbot warning output maps to the postflight warning state' test_agentbot_doctor_warning_output_maps_to_warning_state

finish_tests
