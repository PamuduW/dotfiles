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
	# 4 means "completed, some components need attention" -- distinct from a
	# run that could not start, so a caller can continue and report.
	[[ "$rc" == 4 ]] || return 1
	[[ "$(<"$calls")" == $'first\nsecond\nsummary' ]]
)

test_install_summary_preserves_failed_installer_with_probeable_artifact() (
	declare -gA INSTALL_COMPONENT_RESULT=([partial]=failed)
	declare -gA COMP_ON=([partial]=1)
	COMP_KEYS=(partial)
	COMP_LABELS=('Partial CLI')
	menu_tty_cols() { printf '80\n'; }
	collect_component_status_rows() {
		local -n output_rows="$1"
		output_rows=('Partial CLI|version 1.2.3 is probeable|installed')
	}
	local output
	output="$(NO_COLOR=1 print_install_summary)"
	grep -Eq '^[[:space:]]+Partial CLI[[:space:]]+\|.*installer failed.*\|[[:space:]]+failed[[:space:]]*$' <<<"$output" || return 1
	grep -Fq '0 ok, 1 need attention' <<<"$output"
)

test_env_selection_enables_what_it_depends_on() (
	# The menu has always closed a selection over its dependencies -- toggling
	# Portainer on enables Docker. DOTFILES_COMPONENTS set COMP_ON directly and
	# skipped that, so `DOTFILES_COMPONENTS=dotfiles` asked to stow without
	# system_packages, which is where stow comes from, and the component failed
	# for a reason nothing on screen explained.
	local note
	for pair in 'portainer docker' 'lazydocker docker' 'dotfiles system_packages' 'graphify_cli python'; do
		set -- $pair
		# Redirected to a file rather than captured: a command substitution runs
		# it in a subshell, where everything it sets about the selection is lost.
		DOTFILES_COMPONENTS="$1" apply_dotfiles_components_env 2>"$TEST_HARNESS_ROOT/dep.note" >/dev/null
		note="$(<"$TEST_HARNESS_ROOT/dep.note")"
		[[ "${COMP_ON[$1]}" -eq 1 ]] || return 1
		[[ "${COMP_ON[$2]}" -eq 1 ]] || {
			printf 'selecting %s left %s off\n' "$1" "$2" >&2
			return 1
		}
		# Said out loud: the run is wider than what was asked for.
		[[ "$note" == *"$1 needs $2"* ]] || return 1
	done

	# And nothing else is dragged in.
	DOTFILES_COMPONENTS=portainer apply_dotfiles_components_env 2>/dev/null || true
	local enabled=0 key
	for key in "${COMP_KEYS[@]}"; do
		[[ "${COMP_ON[$key]}" -eq 1 ]] && enabled=$((enabled + 1))
	done
	((enabled == 2))
)

test_every_component_has_an_installer() (
	# The registry already refuses a component with no probe. Without the same
	# check on the installer, a new component is selectable, runs, and fails
	# with a bare non-zero from comp_call_fn and nothing to say why.
	local key
	for key in "${COMP_KEYS[@]}"; do
		declare -F "_comp_install_${key}" >/dev/null 2>&1 || {
			printf 'no installer for %s\n' "$key" >&2
			return 1
		}
	done
	comp_registry_validate
)

check 'component registry validates dependencies and installation order' test_component_registry_validates_dependencies_and_install_order
test_force_reinstall_is_a_flag_not_an_ambient_variable() (
	# cmd_full_update resets DOTFILES_FORCE_REINSTALL before reading its own
	# --force, because an exported variable would otherwise force every run
	# silently. The installer inherited it, so the same shell variable changed
	# what a non-interactive install did with nothing on the command line
	# saying so.
	local probe="$TEST_HARNESS_ROOT/force-probe.sh"
	cat >"$probe" <<'PROBE'
DOTFILES_SOURCE_ONLY=1 source "$1/scripts/install.sh"
# The dispatch is where a real run would begin; report the decision instead.
_dotfiles_dispatch_mode() { printf 'force=%s
' "${DOTFILES_FORCE_REINSTALL:-unset}"; }
main "${@:2}"
PROBE

	# An ambient value is not a decision.
	[[ "$(DOTFILES_FORCE_REINSTALL=1 bash "$probe" "$REPO_DIR" --install)" == 'force=0' ]] || return 1
	# The flag is.
	[[ "$(DOTFILES_FORCE_REINSTALL=0 bash "$probe" "$REPO_DIR" --install --force)" == 'force=1' ]] || return 1
	# And it is advertised.
	bash "$REPO_DIR/scripts/install.sh" --help 2>&1 | grep -Fq -- '--force'
)

check 'environment selection enables what it depends on' test_env_selection_enables_what_it_depends_on
check 'forced reinstall is a flag, not an ambient variable' test_force_reinstall_is_a_flag_not_an_ambient_variable
check 'every component has an installer' test_every_component_has_an_installer
check 'non-interactive install runs the repository gate before setup' test_noninteractive_install_runs_repository_gate_first
check 'non-interactive install propagates component installation failure' test_noninteractive_install_propagates_install_failure
check 'selected component installer failures propagate to the orchestrator' test_selected_component_install_failures_propagate
check 'multi-step component installers preserve the first required failure' test_multi_step_component_installers_preserve_first_failure
test_repository_update_can_be_pre_authorized() (
	# bootstrap.sh confirms the plan once and restarts itself when the checkout
	# moves, so the installer must not ask a second time.
	local prompted=0
	ui_confirm_yes_no() {
		prompted=1
		return 1
	}
	DOTFILES_REPO_UPDATE_ASSUME_YES=1 _dotfiles_install_repo_decision behind 'Pull?' >/dev/null || return 1
	((prompted == 0)) || return 1

	# Without the flag the prompt is still the decision.
	prompted=0
	DOTFILES_REPO_UPDATE_ASSUME_YES='' _dotfiles_install_repo_decision behind 'Pull?' >/dev/null && return 1
	((prompted == 1))
)

test_install_mode_goes_straight_to_component_selection() (
	# Break caught: bootstrap used --initial, which landed on a submenu
	# offering "Check status / Run setup / Back". A caller that has already
	# said "install Dotfiles" wants the component selection itself. That mode
	# is gone now, and what remains is the behaviour it was wrong about: with a
	# terminal, component selection; without one, the whole flow.
	local calls="$TEST_HARNESS_ROOT/install-mode.calls"
	: >"$calls"

	DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/scripts/install.sh"
	# Redefined after sourcing: install.sh pulls in the real implementations.
	run_install_action() { printf 'install-action\n' >>"$calls"; }
	run_initial_setup_flow() { printf 'flow\n' >>"$calls"; }

	DOTFILES_INTERACTIVE_TTY=true _dotfiles_dispatch_mode install
	DOTFILES_INTERACTIVE_TTY=false _dotfiles_dispatch_mode install

	[[ "$(<"$calls")" == $'install-action\nflow' ]] || return 1

	# And the retired flag says where it went rather than reading as a typo.
	local retired
	retired="$(bash "$REPO_DIR/scripts/install.sh" --initial 2>&1)" && return 1
	[[ "$retired" == *'--initial has been removed'* && "$retired" == *'--install'* ]]
)

check 'install mode goes straight to component selection' test_install_mode_goes_straight_to_component_selection
check 'repository update can be pre-authorized by the caller' test_repository_update_can_be_pre_authorized
check 'install orchestration reports failures after attempting all selected components' test_install_orchestrator_collects_failures_and_finishes_selected_work
check 'install summary cannot hide a failed installer behind a probeable artifact' test_install_summary_preserves_failed_installer_with_probeable_artifact

test_harness_cleanup
finish_tests
