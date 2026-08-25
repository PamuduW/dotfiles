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
	if command -v lazygit >/dev/null 2>&1; then
		log_skip "lazygit already installed"
	else
		install_lazygit_from_github
	fi
}

_comp_install_lazydocker() {
	if command -v lazydocker >/dev/null 2>&1; then
		log_skip "lazydocker already installed"
	else
		install_lazydocker_from_github
	fi
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

_comp_install_copilot_cli() {
	install_copilot_cli
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
	git config --global init.defaultBranch main

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

run_install() {
	local key failures=0
	declare -gA INSTALL_COMPONENT_RESULT=()

	echo ""
	printf '%s=== Installing ===%s\n' "${C_ORANGE:-}" "${C_RESET:-}"
	_log_legend_line
	echo ""

	_run_install_preamble || return $?

	for key in "${COMP_INSTALL_ORDER[@]}"; do
		is_on "$key" || continue
		if comp_install "$key"; then
			INSTALL_COMPONENT_RESULT["$key"]=completed
		else
			INSTALL_COMPONENT_RESULT["$key"]=failed
			failures=$((failures + 1))
			log_warn "Component install failed: $key"
		fi
	done

	print_install_summary

	echo ""
	echo "Done. Log saved to: $LOG_FILE"
	echo "Open a new terminal, or run: source ~/.bashrc"
	((failures == 0))
}
