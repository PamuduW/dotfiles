# shellcheck shell=bash
# shellcheck disable=SC2034  # INSTALL_COMPONENT_RESULT is read by the install orchestrator.
# Per-component install dispatch (_comp_install_<id>) and run_install orchestration.

_comp_install_git_identity() {
	apply_git_config
}

_comp_install_system_packages() {
	local tags
	tags="$(comp_package_tags system_packages)"
	# shellcheck disable=SC2086 # Component package tags are an internal word list.
	apt_install_packages $tags || return $?
	post_install_fixes || return $?
	ensure_wslview_browser_in_bashrc || return $?
}

_comp_install_python() {
	local tags
	tags="$(comp_package_tags python)"
	# shellcheck disable=SC2086 # Component package tags are an internal word list.
	apt_install_packages $tags
}

_comp_install_graphify_cli() {
	install_graphify_cli
}

_comp_install_boost_cli() {
	install_boost_cli
}

_comp_install_powershell() {
	install_powershell
}

_comp_install_go() {
	install_go_via_asdf
}

_comp_install_lazygit() {
	if command -v lazygit >/dev/null 2>&1 && skip_unless_forced "lazygit already installed"; then
		return 0
	fi
	install_lazygit_from_github
}

_comp_install_lazydocker() {
	if command -v lazydocker >/dev/null 2>&1 && skip_unless_forced "lazydocker already installed"; then
		return 0
	fi
	install_lazydocker_from_github
}

_comp_install_wsl_conf() {
	configure_wsl
}

_comp_install_git_credential() {
	configure_git_settings
}

_comp_install_docker() {
	install_docker
}

_comp_install_portainer() {
	install_portainer
}

_comp_install_nodejs() {
	install_node_via_nvm
}

_comp_install_direnv() {
	install_direnv || return $?
	ensure_direnv_hook_in_bashrc || return $?
}

_comp_install_cursor_cli() {
	install_cursor_cli
}

_comp_install_codex_cli() {
	install_codex_cli
}

_comp_install_claude_cli() {
	install_claude_cli
}

_comp_install_monaspace_fonts() {
	install_monaspace_fonts
}

_comp_install_dotfiles() {
	backup_existing_dotfiles || return $?
	stow_dotfiles || return $?
	ensure_bash_profile_sources_bashrc || return $?
}

# Components whose installer needs a usable apt index. When the refresh fails
# these cannot honestly be attempted; everything else on the list -- fonts,
# nvm, the vendor CLIs, stow, the config writers -- is untouched by it.
INSTALL_APT_INDEX_COMPONENTS=(system_packages python powershell docker)

_install_needs_apt_index() {
	local key="$1" needed
	for needed in "${INSTALL_APT_INDEX_COMPONENTS[@]}"; do
		[[ "$key" == "$needed" ]] && return 0
	done
	return 1
}

_run_install_preamble() {
	if is_on system_packages || is_on python || is_on powershell; then
		log_step "Refresh apt indexes"
		if _run_quiet_command "apt indexes refresh" sudo apt-get update -qq; then
			log_ok "apt indexes refreshed"
		else
			log_warn "apt indexes refresh failed"
			return 1
		fi
		# This is the run's own work, not the first component's. Without the
		# rule the index refresh sat inside the first component's block and
		# read as part of it.
		declare -F log_component_rule >/dev/null 2>&1 && log_component_rule
	fi
}

# Exit status meaning "installed, but some components failed".
DOTFILES_INSTALL_PARTIAL_RC=4

# Both moved to scripts/lib/installers/logging.sh, where the update's load set
# reaches them too. Kept as names because this file's callers use them.
_install_now_seconds() { timing_now_seconds; }
_install_format_duration() { timing_format "$1"; }

print_install_timing() {
	print_timing_summary Install INSTALL_COMPONENT_SECONDS "$1"
}

# Restart-your-shell, printed when the run gave it a reason.
#
# The notice is about the operator's *current* shell being stale, and only the
# stow component changes what a login shell loads: direnv's hook and
# BROWSER=wslview live inside the stowed .bashrc rather than being appended to
# the operator's, and every other component installs a binary the existing PATH
# already finds. A run that installed docker was telling them to restart for
# nothing.
_install_shell_notice() {
	[[ "${INSTALL_COMPONENT_RESULT[dotfiles]:-}" == completed ]] || return 0
	echo ""
	echo "  Shell configuration changed. Run: exec bash -l"
}

run_install() {
	local key failures=0
	declare -gA INSTALL_COMPONENT_RESULT=()

	rt_print_header 'Installing' 'Dotfiles › Install Dotfiles › Installing'
	_log_legend_line
	echo ""

	# One masked prompt here rather than sudo's silent one at whichever
	# component happens to need root first. The rest of the run uses sudo's
	# credential cache and never prompts again.
	if declare -F sudo_prime >/dev/null 2>&1; then
		sudo_prime || true
	fi

	# Per-component wall-clock, so where a long install actually spends its time
	# is a measurement rather than a guess.
	#
	# Started before the preamble and after the prompt: the apt index refresh is
	# the run's own work and belongs in "Install took", which was under-reporting
	# by however long it took. How long the operator spent typing a password is
	# not the run's time and stays out of it.
	declare -gA INSTALL_COMPONENT_SECONDS=()
	local run_started started
	run_started="$(_install_now_seconds)"

	# A failed index refresh used to end the run here: no component ran, no
	# summary printed, and the operator was not even told where the log was --
	# after having typed their password. It is the likeliest failure in the
	# run (a network blip, an apt lock) and it was the only one that produced
	# no report at all, while a component that fails is recorded and the run
	# carries on. The apt-backed components cannot honestly be attempted, so
	# they are marked and skipped; the rest of the run proceeds and reports.
	local apt_index_failed=false
	_run_install_preamble || apt_index_failed=true
	if [[ "$apt_index_failed" == true ]]; then
		log_warn "Skipping apt-backed components; the rest of the run continues."
		declare -F log_component_rule >/dev/null 2>&1 && log_component_rule
	fi

	local first_component=true
	for key in "${COMP_INSTALL_ORDER[@]}"; do
		is_on "$key" || continue
		# Between components, not before the first: the heading above already
		# separates the run from what came before it.
		if [[ "$first_component" == true ]]; then
			first_component=false
		else
			declare -F log_component_rule >/dev/null 2>&1 && log_component_rule
		fi
		if [[ "$apt_index_failed" == true ]] && _install_needs_apt_index "$key"; then
			INSTALL_COMPONENT_RESULT["$key"]=not-run
			failures=$((failures + 1))
			log_skip "Not run, apt index refresh failed: $key"
			continue
		fi
		started="$(_install_now_seconds)"
		if comp_install "$key"; then
			INSTALL_COMPONENT_RESULT["$key"]=completed
		else
			INSTALL_COMPONENT_RESULT["$key"]=failed
			failures=$((failures + 1))
			log_warn "Component install failed: $key"
		fi
		INSTALL_COMPONENT_SECONDS["$key"]=$(($(_install_now_seconds) - started))
	done

	# Nothing is running any more; the last step's animation must not outlive
	# the loop that owned it.
	declare -F _step_spinner_stop >/dev/null 2>&1 && _step_spinner_stop

	print_install_summary
	# Published as well as printed. A full update timed this phase by wrapping
	# it, which started the clock before the sudo prompt -- so the same install
	# reported "Install took 2m 04s" and "Dotfiles install 3m 17s" on one
	# screen, the difference being how long the operator took to type a
	# password. This number is the run's own work, and it is the one both say.
	declare -g DOTFILES_INSTALL_SECONDS=$(($(_install_now_seconds) - run_started))
	print_install_timing "$DOTFILES_INSTALL_SECONDS"

	_install_shell_notice
	# A distinct status for "the run completed, but N components need
	# attention". A caller sequencing further work -- bootstrap.sh -- can then
	# carry on and report, instead of treating one failed component as a reason
	# to abandon the rest of the machine setup.
	((failures == 0)) || return "$DOTFILES_INSTALL_PARTIAL_RC"
}
