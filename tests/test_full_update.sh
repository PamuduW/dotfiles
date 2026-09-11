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
# full_update.sh prints its three section headings through rt_print_header. The
# real command has it -- `dotfiles_load_command full-update` pulls in the shared
# report table -- but this file sources full_update.sh on its own, so every run
# wrote "rt_print_header: command not found" to stderr three times per test.
# Harmless, and it buried the one real failure here under a hundred lines of it.
# shellcheck source=scripts/lib/shared/tui/report_table.sh
source "$REPO_DIR/scripts/lib/shared/tui/report_table.sh"
# full_update.sh times each section through the helpers beside log_step. The
# real command has them -- `dotfiles_load_command full-update` pulls in the
# installer logging -- and this file sources full_update.sh on its own.
# shellcheck source=scripts/lib/installers/logging.sh
source "$REPO_DIR/scripts/lib/installers/logging.sh"
[[ -f "$REPO_DIR/scripts/lib/full_update.sh" ]] && source "$REPO_DIR/scripts/lib/full_update.sh"

test_force_flag_reaches_the_installers_and_survives_a_restart() (
	# The unattended equivalent of the plan screen's `x`. A repository change
	# restarts full-update through exec, so the flag has to be carried across
	# that restart or the run quietly drops back to skipping everything already
	# present -- the opposite of what was asked for.
	local events="$TEST_HARNESS_ROOT/full-update-force.events"
	: >"$events"
	_dotfiles_run_update() {
		printf 'force=%s\n' "${DOTFILES_FORCE_REINSTALL:-unset}" >>"$events"
		printf 'exported=%s\n' "$(bash -c 'printf "%s" "${DOTFILES_FORCE_REINSTALL:-unset}"')" >>"$events"
	}
	full_update_print_identity() { :; }
	full_update_run_agentbot() { :; }
	full_update_postflight() { :; }

	cmd_full_update --force >/dev/null || return 1
	grep -Fqx 'force=1' "$events" || return 1
	# Exported, so the installers in any child see it too.
	grep -Fqx 'exported=1' "$events" || return 1

	# Restarting after a repository change re-passes the flag rather than
	# leaning on the inherited environment.
	full_update_restart_dotfiles() { printf '%s\n' "$*" >"$TEST_HARNESS_ROOT/full-update-force.restart"; }
	_dotfiles_run_update() { return 2; }
	repo_update_print_changed() { :; }
	cmd_full_update --force >/dev/null || true
	local restart_line
	restart_line="$(<"$TEST_HARNESS_ROOT/full-update-force.restart")"
	[[ "$restart_line" == '--resume-after-dotfiles-repo --force' ]] || return 1

	# And an ambient value does not force a run that did not ask for it.
	: >"$events"
	_dotfiles_run_update() {
		printf 'force=%s\n' "${DOTFILES_FORCE_REINSTALL:-unset}" >>"$events"
	}
	DOTFILES_FORCE_REINSTALL=1 cmd_full_update >/dev/null || return 1
	grep -Fqx 'force=0' "$events"
)

test_full_update_loads_everything_its_install_phase_needs() (
	# Break caught: full-update installs as well as updates, and its module list
	# was written by hand. It missed run_docker, menu_tty_cols and PKG_FILE, so
	# Portainer failed outright and both apt components installed nothing while
	# their probes still reported "installed" in the summary.
	#
	# Driven through the real loader, not a restated list, so it cannot drift
	# again the same way.
	local probe
	probe="$(
		export DOTFILES_DIR="$REPO_DIR" DOTFILES_SOURCE_ONLY=1
		source "$REPO_DIR/bin/bin/dotfiles" >/dev/null 2>&1
		dotfiles_load_command full-update >/dev/null 2>&1 || exit 1
		for fn in run_install comp_install run_docker menu_tty_cols \
			read_packages_by_tags install_portainer apply_git_config \
			full_update_select_applied_components; do
			declare -F "$fn" >/dev/null || printf 'missing-fn:%s\n' "$fn"
		done
		[[ -n "${PKG_FILE:-}" ]] || printf 'missing-var:PKG_FILE\n'
		# The packages file has to exist, not merely be named: an unbound or
		# wrong PKG_FILE reads as "no packages for tags" rather than an error.
		[[ -f "${PKG_FILE:-/nonexistent}" ]] || printf 'unreadable:PKG_FILE\n'
	)" || return 1
	[[ -z "$probe" ]] || {
		printf 'full-update cannot install: %s\n' "$probe" >&2
		return 1
	}
)

test_operator_input_components_are_never_installed_by_full_update() (
	# Break caught: full-update selected git_identity, whose installer needs a
	# name and email that only the menu collects, and the run died on an unbound
	# SETUP_GIT_NAME before installing anything. A full update has nobody to
	# ask, so that is initial-setup work.
	local installed="$TEST_HARNESS_ROOT/full-update-input.installed"
	: >"$installed"
	COMP_KEYS=(git_identity docker)
	declare -A COMP_ON=()
	collect_component_probe_results() {
		local -n out="$1"
		# Both read as present; only the one needing input is excluded.
		out=([git_identity]=configured [docker]=installed)
	}
	run_install() {
		local key
		for key in "${COMP_KEYS[@]}"; do
			[[ "${COMP_ON[$key]}" -eq 1 ]] && printf '%s\n' "$key" >>"$installed"
		done
		return 0
	}

	full_update_install_applied_components >/dev/null || return 1
	[[ "$(<"$installed")" == docker ]]
)

test_full_update_installs_only_components_that_probe_as_present() (
	# Roadmap item 2: full-update is install + update, so install-time work
	# stops drifting. The selection is derived from probes and must never add a
	# component the operator did not choose.
	local installed="$TEST_HARNESS_ROOT/full-update-selection.installed"
	: >"$installed"
	COMP_KEYS=(present_one configured_one absent_one skipped_one)
	declare -A COMP_ON=()
	collect_component_probe_results() {
		local -n out="$1"
		out=(
			[present_one]=installed
			[configured_one]=configured
			[absent_one]=missing
			[skipped_one]=skipped
		)
	}
	run_install() {
		local key
		for key in "${COMP_KEYS[@]}"; do
			[[ "${COMP_ON[$key]}" -eq 1 ]] && printf '%s\n' "$key" >>"$installed"
		done
		return 0
	}

	full_update_install_applied_components >/dev/null || return 1
	[[ "$(<"$installed")" == $'present_one\nconfigured_one' ]]
)

test_an_unverifiable_component_is_reinstalled_and_said_so() (
	# `check` means the probe reached no verdict, not that the component is
	# absent -- Portainer reads that way in any session predating the docker
	# group. Skipping it would be the silent drift this item exists to fix, so
	# it is reinstalled and the run names what it guessed about.
	local installed="$TEST_HARNESS_ROOT/full-update-unverified.installed"
	: >"$installed"
	COMP_KEYS=(solid unverified gone)
	declare -A COMP_ON=()
	collect_component_probe_results() {
		local -n out="$1"
		out=([solid]=installed [unverified]=check [gone]=missing)
	}
	run_install() {
		local key
		for key in "${COMP_KEYS[@]}"; do
			[[ "${COMP_ON[$key]}" -eq 1 ]] && printf '%s\n' "$key" >>"$installed"
		done
		return 0
	}

	local output
	output="$(full_update_install_applied_components)" || return 1
	[[ "$(<"$installed")" == $'solid\nunverified' ]] || return 1
	[[ "$output" == *'could not verify, reinstalling anyway: unverified'* ]] || return 1
	# Only the guess is named, not everything that was installed.
	[[ "$output" != *solid* ]]
)

test_components_needing_attention_do_not_stop_the_update() (
	# The installer returns a distinct status for "finished, but N components
	# need attention". The update phases after it are independent.
	COMP_KEYS=(one)
	declare -A COMP_ON=()
	collect_component_probe_results() {
		local -n out="$1"
		out=([one]=installed)
	}
	run_install() { return "${DOTFILES_INSTALL_PARTIAL_RC:-4}"; }

	full_update_install_applied_components >/dev/null
)

test_install_runs_between_the_repository_gate_and_downstream_updates() (
	# Bootstrap and full-update must apply things in the same order or they
	# converge on different machine state.
	local events="$TEST_HARNESS_ROOT/full-update-order.events"
	: >"$events"
	_dotfiles_run_update() {
		printf 'repo-gate\n' >>"$events"
		[[ -n "${4:-}" ]] || return 1
		"$4" || return $?
		printf 'downstream\n' >>"$events"
	}
	full_update_install_applied_components() { printf 'install\n' >>"$events"; }
	agentbot() { [[ "$*" == 'help full' || "$*" == 'full' || "$*" == doctor ]]; }

	cmd_full_update >/dev/null || return 1
	[[ "$(<"$events")" == $'repo-gate\ninstall\ndownstream' ]]
)

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
	# An Agentbot checkout that exists whose launcher is not on PATH: broken,
	# and still a failure. Since absent and unreachable became different
	# things, which of the two this is depends on whether a checkout is found
	# at the expected home -- and this test did not say. It passed on a
	# developer's machine, where the workspace keeps agentbot and dotfiles side
	# by side so one was always there, and failed on CI, which checks out this
	# repository alone. Its two newer siblings pin the home; so does it now.
	local rc=0 present="$TEST_HARNESS_ROOT/unreachable-agentbot"
	mkdir -p -- "$present"
	export FULL_UPDATE_EXPECTED_AGENTBOT_HOME="$present"
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

expect_success 'the force flag reaches the installers and survives a restart' test_force_flag_reaches_the_installers_and_survives_a_restart
expect_success 'full-update loads everything its install phase needs' test_full_update_loads_everything_its_install_phase_needs
expect_success 'operator-input components are never installed by full-update' test_operator_input_components_are_never_installed_by_full_update
expect_success 'full-update installs only components that probe as present' test_full_update_installs_only_components_that_probe_as_present
expect_success 'an unverifiable component is reinstalled and said so' test_an_unverifiable_component_is_reinstalled_and_said_so
expect_success 'components needing attention do not stop the update' test_components_needing_attention_do_not_stop_the_update
expect_success 'install runs between the repository gate and downstream updates' test_install_runs_between_the_repository_gate_and_downstream_updates
expect_success 'full-update runs Dotfiles, then one Agentbot full run' test_success_runs_dotfiles_then_agentbot_full
expect_success 'a legacy Agentbot bootstraps once before full' test_legacy_agentbot_bootstraps_once_before_full
expect_success 'an incompatible Agentbot stops after one bootstrap attempt' test_agentbot_bootstrap_stops_if_full_is_still_unavailable
expect_success 'Dotfiles repository change restarts once and a second change stops' test_dotfiles_change_restarts_once_and_second_change_stops
expect_success 'Agentbot repository change stops with rerun guidance' test_agentbot_repository_change_stops_with_guidance
expect_success 'Agentbot failure status propagates unchanged' test_agentbot_failure_propagates_its_status
expect_success 'Agentbot capability failure status propagates unchanged' test_agentbot_capability_failure_propagates_its_status
expect_success 'a missing agentbot is reported, not silently skipped' test_missing_agentbot_is_reported_not_ignored
test_full_update_module_set_is_closed_over_its_own_references() {
	# L3: the full-update loader is a hand-maintained list. It already missed
	# PKG_FILE, run_docker and menu_tty_cols once, and the apt components then
	# installed nothing while their probes still reported "installed".
	#
	# This does not hand-list the modules. It loads the real full-update set,
	# asks Bash which files that actually pulled in, scans those files for
	# functions this repository defines, and reports the ones nothing defines.
	# Adding a module widens the scan automatically.
	#
	# The set is not empty and is not expected to be. full-update deliberately
	# omits the menu, TUI and package-library layers, so loaded modules that
	# also serve interactive paths reference functions that are absent here.
	# Every one of those call sites must stay on a branch full-update never
	# takes. Pinning the set means a ninth crossing fails this test instead of
	# failing on a machine.
	local expected actual
	expected='menu_checkbox_run package_lib_render_components package_metadata_load toggle_component ui_clear ui_confirm_yes_no ui_print_header ui_print_plan_row'

	actual="$(
		set +u
		DOTFILES_DIR="$REPO_DIR"
		export DOTFILES_DIR
		DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/bin/bin/dotfiles" >/dev/null 2>&1
		dotfiles_load_command full-update >/dev/null 2>&1
		shopt -s extdebug

		defined="$(declare -F | awk '{print $3}')"
		files="$(for fn in $defined; do declare -F "$fn"; done | awk '{print $3}' | sort -u)"
		# Repository-defined function names, and the names the loaded files use.
		# Full-line comments are stripped so prose cannot trip the check.
		defs="$(grep -rhoE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$REPO_DIR/scripts" "$REPO_DIR/bin" 2>/dev/null | tr -d '()' | sort -u)"
		refs="$(sed 's/^[[:space:]]*#.*$//' $files 2>/dev/null | grep -ohE '\b[A-Za-z_][A-Za-z0-9_]*\b' | sort -u)"

		comm -12 <(printf '%s\n' "$defs") <(printf '%s\n' "$refs") | while read -r fn; do
			declare -F "$fn" >/dev/null 2>&1 || printf '%s\n' "$fn"
		done | sort -u | tr '\n' ' '
	)"
	actual="${actual% }"

	if [[ "$actual" != "$expected" ]]; then
		printf 'full-update module set references changed\n  expected: %s\n  actual:   %s\n' \
			"$expected" "$actual" >&2
		return 1
	fi
}

expect_success 'full-update reports resolved launcher and checkout identity' test_full_update_reports_resolved_launcher_identity
test_full_update_without_agentbot_is_not_a_failure() (
	# Break caught on a fresh Ubuntu 26 machine that chose "Dotfiles only" at
	# the bootstrap prompt: the Dotfiles half completed in full, and the run
	# then ended on "Agentbot is not installed" and "Action failed (exit 127)".
	# Bootstrap offers that choice and closes by saying how to add Agentbot
	# later, so it is a supported state, not a broken one.
	local output_file="$TEST_HARNESS_ROOT/full-update-no-agentbot.out"
	local missing="$TEST_HARNESS_ROOT/no-such-agentbot"
	rm -rf -- "$missing"
	local rc=0
	(
		export FULL_UPDATE_EXPECTED_AGENTBOT_HOME="$missing"
		export PATH=/usr/bin:/bin
		_dotfiles_run_update() { :; }
		full_update_dotfiles_doctor() { printf '  doctor ran\n'; }
		full_update_run_agentbot() {
			printf 'agentbot phase must not run\n'
			return 1
		}
		NO_COLOR=1 cmd_full_update
	) >"$output_file" 2>&1 || rc=$?

	[[ "$rc" -eq 0 ]] || return 1
	grep -Fq 'Agentbot is not installed, so this run updated Dotfiles only.' "$output_file" || return 1
	grep -Fq "$missing" "$output_file" || return 1
	grep -Fq 'doctor ran' "$output_file" || return 1
	grep -Fq 'Dotfiles update completed.' "$output_file" || return 1
	! grep -Fq 'agentbot phase must not run' "$output_file" || return 1
	! grep -Fq 'Action failed' "$output_file"
)

test_full_update_still_fails_when_agentbot_is_installed_but_unreachable() (
	# The other half of the distinction: a checkout that exists but whose
	# launcher is not on PATH is broken, and must still be reported as such.
	local present="$TEST_HARNESS_ROOT/present-agentbot"
	mkdir -p -- "$present"
	local rc=0
	(
		export FULL_UPDATE_EXPECTED_AGENTBOT_HOME="$present"
		export PATH=/usr/bin:/bin
		full_update_agentbot_is_absent
	) && rc=1
	[[ "$rc" -eq 0 ]]
)

test_full_update_closes_on_what_each_section_spent() (
	# The longest command in the product, and the only one saying nothing
	# about where its time went while both halves it drives close on their own
	# summary.
	local output
	C_ORANGE='' C_RESET=''
	FULL_UPDATE_SECTION_SECONDS=()
	FULL_UPDATE_STARTED="$(($(timing_now_seconds) - 90))"
	_slow() { sleep 0; }
	_full_update_section Dotfiles _slow || return 1
	_full_update_section Agentbot _slow || return 1
	output="$(_full_update_print_timing)"

	grep -Eq '^  Full update took [0-9]+m [0-9]{2}s\. Slowest sections:$' <<<"$output" || return 1
	# Both sections recorded, whatever they measured.
	[[ -n "${FULL_UPDATE_SECTION_SECONDS['Dotfiles']+set}" ]] || return 1
	[[ -n "${FULL_UPDATE_SECTION_SECONDS['Agentbot']+set}" ]]
)

test_a_section_keeps_the_status_it_wrapped() (
	# The clock must not swallow a failure: a section that fails still fails,
	# and is still recorded.
	local rc=0
	FULL_UPDATE_SECTION_SECONDS=()
	_failing() { return 7; }
	_full_update_section Agentbot _failing || rc=$?
	[[ "$rc" -eq 7 ]] || return 1
	[[ -n "${FULL_UPDATE_SECTION_SECONDS['Agentbot']+set}" ]]
)

test_agentbot_reports_its_two_halves_separately() (
	# `agentbot full` is one command from here, so its install and its update
	# could only be timed as one section -- while both halves print their own
	# timing on screen. Agentbot writes a line per stage to a file when asked.
	FULL_UPDATE_SECTION_SECONDS=()
	full_update_run_agentbot() {
		printf 'install 33\nupdate 41\n' >>"$AGENTBOT_TIMING_FILE"
		# The [info] lines are for someone running Agentbot directly.
		[[ "${AGENTBOT_QUIET:-}" == 1 ]] || return 1
	}
	_full_update_run_agentbot_timed || return 1

	[[ "${FULL_UPDATE_SECTION_SECONDS['Agentbot install']}" == 33 ]] || return 1
	[[ "${FULL_UPDATE_SECTION_SECONDS['Agentbot update']}" == 41 ]] || return 1
	[[ -z "${FULL_UPDATE_SECTION_SECONDS[Agentbot]+set}" ]]
)

test_an_agentbot_that_reports_nothing_is_still_one_section() (
	# An older checkout, or one mid-upgrade, does not know how to write the
	# file. The run still has to say how long it took.
	FULL_UPDATE_SECTION_SECONDS=()
	full_update_run_agentbot() { :; }
	_full_update_run_agentbot_timed || return 1

	[[ -n "${FULL_UPDATE_SECTION_SECONDS[Agentbot]+set}" ]] || return 1
	[[ -z "${FULL_UPDATE_SECTION_SECONDS['Agentbot install']+set}" ]]
)

test_a_failing_agentbot_keeps_its_status() (
	local rc=0
	FULL_UPDATE_SECTION_SECONDS=()
	full_update_run_agentbot() { return 7; }
	_full_update_run_agentbot_timed || rc=$?
	[[ "$rc" -eq 7 ]]
)

expect_success 'Agentbot reports its install and update separately' test_agentbot_reports_its_two_halves_separately
expect_success 'an Agentbot that reports nothing is still one section' test_an_agentbot_that_reports_nothing_is_still_one_section
expect_success 'a failing Agentbot keeps its status' test_a_failing_agentbot_keeps_its_status
expect_success 'full update closes on what each section spent' test_full_update_closes_on_what_each_section_spent
expect_success 'a timed section keeps the status it wrapped' test_a_section_keeps_the_status_it_wrapped
expect_success 'full-update refuses an unexpected Agentbot checkout' test_full_update_refuses_unexpected_agentbot_checkout
expect_success 'postflight distinguishes healthy warning and error outcomes' test_postflight_distinguishes_warnings_errors_and_health
expect_success 'Agentbot warning output maps to the postflight warning state' test_agentbot_doctor_warning_output_maps_to_warning_state
expect_success 'the full-update module set is closed over its own references' test_full_update_module_set_is_closed_over_its_own_references
expect_success 'full update without Agentbot is not a failure' test_full_update_without_agentbot_is_not_a_failure
expect_success 'full update still fails when Agentbot is installed but unreachable' test_full_update_still_fails_when_agentbot_is_installed_but_unreachable

finish_tests
