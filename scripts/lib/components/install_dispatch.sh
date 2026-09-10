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

_comp_install_ssh_key() {
	generate_ssh_key
}

_comp_install_dotfiles() {
	backup_existing_dotfiles || return $?
	stow_dotfiles || return $?
	ensure_bash_profile_sources_bashrc || return $?
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
	fi
}

# Exit status meaning "installed, but some components failed".
DOTFILES_INSTALL_PARTIAL_RC=4

_install_now_seconds() {
	printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}"
}

# The slowest handful and the total. Enough to tell a network-bound component
# from a slow one without turning the summary into a profile.
# Minutes and seconds, the way the total above the list is written. A column of
# raw seconds made the reader convert every row to compare it with the heading.
_install_format_duration() {
	printf '%dm %02ds' "$(($1 / 60))" "$(($1 % 60))"
}

print_install_timing() {
	local total="$1" key seconds
	((${#INSTALL_COMPONENT_SECONDS[@]} > 0)) || return 0
	echo ""
	printf '%sInstall took %s. Slowest components:%s\n' \
		"${C_ORANGE:-}" "$(_install_format_duration "$total")" "${C_RESET:-}"
	while read -r seconds key; do
		((seconds > 0)) || continue
		printf '  %7s  %s\n' "$(_install_format_duration "$seconds")" "$key"
	done < <(
		for key in "${!INSTALL_COMPONENT_SECONDS[@]}"; do
			printf '%s %s\n' "${INSTALL_COMPONENT_SECONDS[$key]}" "$key"
		done | sort -rn | head -6
	)
}

run_install() {
	local key failures=0
	declare -gA INSTALL_COMPONENT_RESULT=()

	echo ""
	printf '%s=== Installing ===%s\n\n' "${C_ORANGE:-}" "${C_RESET:-}"
	_log_legend_line
	echo ""

	# One masked prompt here rather than sudo's silent one at whichever
	# component happens to need root first. The rest of the run uses sudo's
	# credential cache and never prompts again.
	if declare -F sudo_prime >/dev/null 2>&1; then
		sudo_prime || true
	fi

	_run_install_preamble || return $?

	# Per-component wall-clock, so where a long install actually spends its time
	# is a measurement rather than a guess.
	declare -gA INSTALL_COMPONENT_SECONDS=()
	local run_started started
	run_started="$(_install_now_seconds)"

	for key in "${COMP_INSTALL_ORDER[@]}"; do
		is_on "$key" || continue
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
	print_install_timing "$((($(_install_now_seconds)) - run_started))"

	echo ""
	echo "Done. Log saved to: $LOG_FILE"
	echo ""
	echo "Open a new terminal, or run: exec bash -l"
	# A distinct status for "the run completed, but N components need
	# attention". A caller sequencing further work -- bootstrap.sh -- can then
	# carry on and report, instead of treating one failed component as a reason
	# to abandon the rest of the machine setup.
	((failures == 0)) || return "$DOTFILES_INSTALL_PARTIAL_RC"
}
