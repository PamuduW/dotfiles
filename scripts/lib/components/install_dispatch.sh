# shellcheck shell=bash
# Per-component install dispatch (_comp_install_<id>) and run_install orchestration.

_comp_install_git_identity() {
	apply_git_config
}

_comp_install_system_packages() {
	apt_install_packages core cli system
	post_install_fixes
	ensure_wslview_browser_in_bashrc
}

_comp_install_python() {
	apt_install_packages python
}

_comp_install_powershell() {
	install_powershell || echo "  Warning: PowerShell install failed."
}

_comp_install_go() {
	install_go_via_asdf || echo "  Warning: Go install via asdf failed."
}

_comp_install_lazygit() {
	if command -v lazygit >/dev/null 2>&1; then
		log_skip "lazygit already installed"
	else
		install_lazygit_from_github || echo "  Warning: lazygit install failed."
	fi
}

_comp_install_lazydocker() {
	if command -v lazydocker >/dev/null 2>&1; then
		log_skip "lazydocker already installed"
	else
		install_lazydocker_from_github || echo "  Warning: lazydocker install failed."
	fi
}

_comp_install_wsl_conf() {
	configure_wsl
}

_comp_install_git_credential() {
	configure_git_credential_helper
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
	install_direnv || echo "  Warning: direnv install failed."
	ensure_direnv_hook_in_bashrc
}

_comp_install_cursor_cli() {
	install_cursor_cli || echo "  Warning: Cursor CLI install failed."
}

_comp_install_codex_cli() {
	install_codex_cli || echo "  Warning: Codex CLI install failed."
}

_comp_install_claude_cli() {
	install_claude_cli || echo "  Warning: Claude CLI install failed."
}

_comp_install_copilot_cli() {
	install_copilot_cli || echo "  Warning: Copilot CLI install failed."
}

_comp_install_monaspace_fonts() {
	install_monaspace_fonts || echo "  Warning: Monaspace fonts install failed."
}

_comp_install_ssh_key() {
	generate_ssh_key
}

_comp_install_dotfiles() {
	backup_existing_dotfiles
	stow_dotfiles
	ensure_bash_profile_sources_bashrc
}

_run_install_preamble() {
	git config --global init.defaultBranch main

	if is_on system_packages || is_on python || is_on powershell; then
		log_step "Refresh apt indexes"
		if _run_quiet_command "apt indexes refresh" sudo apt-get update -qq; then
			log_ok "apt indexes refreshed"
		else
			log_warn "apt indexes refresh failed"
			exit 1
		fi
	fi
}

run_install() {
	local key

	echo ""
	printf '%s=== Installing ===%s\n' "${C_YELLOW:-}" "${C_RESET:-}"
	_log_legend_line
	echo ""

	_run_install_preamble

	for key in "${COMP_INSTALL_ORDER[@]}"; do
		is_on "$key" || continue
		comp_install "$key"
	done

	print_install_summary

	echo ""
	echo "Done. Log saved to: $LOG_FILE"
	echo "Open a new terminal, or run: source ~/.bashrc"
}
