#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# Component registry validity and install orchestration: ordering, dependency
# rules, and how failures propagate out of a selected-component run.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

test_component_registry_validates_dependencies_and_install_order() (
	comp_registry_validate
)

test_noninteractive_install_runs_repository_gate_first() (
	local events="$TEST_HARNESS_ROOT/noninteractive-install-order"
	: >"$events"
	DOTFILES_INTERACTIVE_TTY=false
	_dotfiles_install_repo_gate() { printf 'gate\n' >>"$events"; }
	apply_dotfiles_components_env() { printf 'components\n' >>"$events"; }
	_apply_noninteractive_git_defaults() { :; }
	_run_setup_header() { :; }
	show_plan() { :; }
	run_install() { printf 'install\n' >>"$events"; }
	run_initial_setup_flow
	[[ "$(<"$events")" == $'gate\ncomponents\ninstall' ]]
)

test_noninteractive_install_propagates_install_failure() (
	DOTFILES_INTERACTIVE_TTY=false
	_dotfiles_install_repo_gate() { :; }
	apply_dotfiles_components_env() { :; }
	_apply_noninteractive_git_defaults() { :; }
	_run_setup_header() { :; }
	show_plan() { :; }
	run_install() { return 31; }
	set +e
	run_initial_setup_flow
	local rc=$?
	set -e
	[[ "$rc" -eq 31 ]]
)

test_selected_component_install_failures_propagate() (
	install_graphify_cli() { return 23; }
	set +e
	_comp_install_graphify_cli >/dev/null
	local rc=$?
	set -e
	[[ "$rc" == 23 ]]
)

test_multi_step_component_installers_preserve_first_failure() (
	apt_install_packages() { return 23; }
	post_install_fixes() { return 0; }
	ensure_wslview_browser_in_bashrc() { return 0; }
	install_direnv() { return 24; }
	ensure_direnv_hook_in_bashrc() { return 0; }
	backup_existing_dotfiles() { return 25; }
	stow_dotfiles() { return 0; }
	ensure_bash_profile_sources_bashrc() { return 0; }

	local installer expected rc
	for installer in _comp_install_system_packages _comp_install_direnv _comp_install_dotfiles; do
		case "$installer" in
		_comp_install_system_packages) expected=23 ;;
		_comp_install_direnv) expected=24 ;;
		_comp_install_dotfiles) expected=25 ;;
		esac
		set +e
		"$installer" >/dev/null 2>&1
		rc=$?
		set -e
		[[ "$rc" == "$expected" ]] || return 1
	done
)

test_install_orchestrator_collects_failures_and_finishes_selected_work() (
	local calls="$TEST_HARNESS_ROOT/install-failure-calls"
	: >"$calls"
	COMP_INSTALL_ORDER=(first second)
	declare -gA COMP_ON=([first]=1 [second]=1)
	LOG_FILE="$TEST_HARNESS_ROOT/install.log"
	is_on() { [[ "${COMP_ON[$1]}" == 1 ]]; }
	_run_install_preamble() { :; }
	_log_legend_line() { :; }
	print_install_summary() { printf 'summary\n' >>"$calls"; }
	log_warn() { :; }
	comp_install() {
		printf '%s\n' "$1" >>"$calls"
		[[ "$1" != first ]]
	}
	set +e
	run_install >/dev/null
	local rc=$?
	set -e
	[[ "$rc" == 1 ]] || return 1
	[[ "$(<"$calls")" == $'first\nsecond\nsummary' ]]
)

check 'component registry validates dependencies and installation order' test_component_registry_validates_dependencies_and_install_order
check 'non-interactive install runs the repository gate before setup' test_noninteractive_install_runs_repository_gate_first
check 'non-interactive install propagates component installation failure' test_noninteractive_install_propagates_install_failure
check 'selected component installer failures propagate to the orchestrator' test_selected_component_install_failures_propagate
check 'multi-step component installers preserve the first required failure' test_multi_step_component_installers_preserve_first_failure
check 'install orchestration reports failures after attempting all selected components' test_install_orchestrator_collects_failures_and_finishes_selected_work

test_harness_cleanup
finish_tests
