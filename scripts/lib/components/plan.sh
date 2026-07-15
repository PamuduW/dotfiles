# shellcheck shell=bash
# shellcheck disable=SC2015  # Existing compact enabled/skip row pattern.
# Per-component execution plan rows (_comp_plan_<id>).

_comp_plan_git_identity() {
	if is_on git_identity; then
		ui_print_plan_row "Git identity" "$SETUP_GIT_NAME <$SETUP_GIT_EMAIL>" 1
	elif git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
		ui_print_plan_row "Git identity" "skip (conditional includes detected)" 0
	else
		ui_print_plan_row "Git identity" "skip" 0
	fi
}

_comp_plan_system_packages() {
	local pkg_count
	if is_on system_packages; then
		pkg_count="$(read_packages_by_tags core cli system | wc -l)"
		ui_print_plan_row "System packages" "${pkg_count} packages (@core @cli @system)" 1
	else
		ui_print_plan_row "System packages" "skip" 0
	fi
}

_comp_plan_python() {
	is_on python \
		&& ui_print_plan_row "Python" "python3, pip, venv" 1 \
		|| ui_print_plan_row "Python" "skip" 0
}

_comp_plan_powershell() {
	is_on powershell \
		&& ui_print_plan_row "PowerShell" "Microsoft repo + powershell" 1 \
		|| ui_print_plan_row "PowerShell" "skip" 0
}

_comp_plan_go() {
	is_on go \
		&& ui_print_plan_row "Go" "asdf golang latest" 1 \
		|| ui_print_plan_row "Go" "skip" 0
}

_comp_plan_nodejs() {
	is_on nodejs \
		&& ui_print_plan_row "Node.js" "v24 via nvm" 1 \
		|| ui_print_plan_row "Node.js" "skip" 0
}

_comp_plan_direnv() {
	is_on direnv \
		&& ui_print_plan_row "direnv" "install/update + bash hook" 1 \
		|| ui_print_plan_row "direnv" "skip" 0
}

_comp_plan_docker() {
	is_on docker \
		&& ui_print_plan_row "Docker" "Docker Engine CE + docker group" 1 \
		|| ui_print_plan_row "Docker" "skip" 0
}

_comp_plan_portainer() {
	is_on portainer \
		&& ui_print_plan_row "Portainer" "Portainer CE (stopped by default)" 1 \
		|| ui_print_plan_row "Portainer" "skip" 0
}

_comp_plan_lazygit() {
	is_on lazygit \
		&& ui_print_plan_row "lazygit" "latest from GitHub" 1 \
		|| ui_print_plan_row "lazygit" "skip" 0
}

_comp_plan_lazydocker() {
	is_on lazydocker \
		&& ui_print_plan_row "lazydocker" "latest from GitHub" 1 \
		|| ui_print_plan_row "lazydocker" "skip" 0
}

_comp_plan_cursor_cli() {
	is_on cursor_cli \
		&& ui_print_plan_row "Cursor CLI" "cursor.com installer" 1 \
		|| ui_print_plan_row "Cursor CLI" "skip" 0
}

_comp_plan_codex_cli() {
	is_on codex_cli \
		&& ui_print_plan_row "Codex CLI" "npm @openai/codex" 1 \
		|| ui_print_plan_row "Codex CLI" "skip" 0
}

_comp_plan_claude_cli() {
	is_on claude_cli \
		&& ui_print_plan_row "Claude CLI" "claude.ai installer" 1 \
		|| ui_print_plan_row "Claude CLI" "skip" 0
}

_comp_plan_copilot_cli() {
	is_on copilot_cli \
		&& ui_print_plan_row "Copilot CLI" "gh.io/copilot-install" 1 \
		|| ui_print_plan_row "Copilot CLI" "skip" 0
}

_comp_plan_monaspace_fonts() {
	is_on monaspace_fonts \
		&& ui_print_plan_row "Monaspace fonts" "Monaspace Nerd Fonts -> ~/.local/share/fonts/" 1 \
		|| ui_print_plan_row "Monaspace fonts" "skip" 0
}

_comp_plan_ssh_key() {
	if is_on ssh_key; then
		if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
			ui_print_plan_row "SSH key" "already exists, will skip" 1
		else
			ui_print_plan_row "SSH key" "generate ed25519 -> ~/.ssh/github-setup.txt" 1
		fi
	else
		ui_print_plan_row "SSH key" "skip" 0
	fi
}

_comp_plan_dotfiles() {
	is_on dotfiles \
		&& ui_print_plan_row "Dotfiles" "stow bash, bin, readline" 1 \
		|| ui_print_plan_row "Dotfiles" "skip" 0
}

_comp_plan_wsl_conf() {
	is_on wsl_conf \
		&& ui_print_plan_row "WSL config" "systemd=true, appendWindowsPath=true" 1 \
		|| ui_print_plan_row "WSL config" "skip" 0
}

_comp_plan_git_credential() {
	is_on git_credential \
		&& ui_print_plan_row "Git credential" "Windows Credential Manager" 1 \
		|| ui_print_plan_row "Git credential" "skip" 0
}

show_plan() {
	local cols i key

	cols="$(menu_tty_cols)"

	{
		ui_clear
		ui_print_header "Execution Plan" "Dotfiles › Install Dotfiles › Execution Plan" "$cols"
		printf '\n'

		for i in "${!COMP_KEYS[@]}"; do
			key="${COMP_KEYS[$i]}"
			comp_plan_row "$key"
		done

		printf '\n'
	} >/dev/tty
}
