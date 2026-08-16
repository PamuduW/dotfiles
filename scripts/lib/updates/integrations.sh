# shellcheck shell=bash
# --- Cursor CLI ---
cursor_installed_version() {
	if command -v agent >/dev/null 2>&1; then
		agent --version 2>/dev/null | head -n1 || echo "installed"
	elif command -v cursor >/dev/null 2>&1; then
		cursor --version 2>/dev/null | head -n1 || echo "installed"
	elif [[ -x "$HOME/.local/bin/agent" ]]; then
		"$HOME/.local/bin/agent" --version 2>/dev/null | head -n1 || echo "installed"
	else
		echo "$NOT_INSTALLED"
	fi
}

cursor_is_installed() {
	command -v agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/agent" ]]
}

check_cursor_cli() {
	local installed available action upgradable=0
	installed="$(cursor_installed_version)"
	if cursor_is_installed; then
		available="—"
		action="latest unchecked"
	else
		available="—"
		action="skip"
	fi
	printf '%s|%s|%s|%s\n' "Cursor CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_cursor_cli() {
	if command -v agent >/dev/null 2>&1; then
		local update_rc=0
		agent update || update_rc=$?
		if [[ $update_rc -eq 0 ]]; then
			return 0
		fi
		_report_command_failure "$update_rc" "agent update"
		_warn "  Cursor Agent update command failed; retrying with the official installer."
		run_vendor_shell_installer 'https://cursor.com/install' 'Cursor CLI'
	elif command -v cursor >/dev/null 2>&1; then
		cursor update
	elif [[ -x "$HOME/.local/bin/agent" ]]; then
		"$HOME/.local/bin/agent" update || run_vendor_shell_installer 'https://cursor.com/install' 'Cursor CLI'
	else
		_msg "  Cursor CLI not installed, skipping"
	fi
}

# --- Codex CLI ---
codex_installed_version() {
	_load_nvm
	if command -v codex >/dev/null 2>&1; then
		codex --version 2>/dev/null | head -n1 || echo "installed"
	else
		echo "$NOT_INSTALLED"
	fi
}

codex_available_version() {
	if ! command -v npm >/dev/null 2>&1; then
		echo "—"
		return
	fi
	npm view @openai/codex version 2>/dev/null || echo "—"
}

check_codex_cli() {
	local installed available action upgradable=0
	installed="$(codex_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		available="—"
		action="skip"
	else
		available="$(codex_available_version)"
		if [[ "$available" != "—" && "$installed" != *"${available}"* ]]; then
			action="upgrade"
			upgradable=1
		else
			available="${available:-—}"
			action="up to date"
		fi
	fi
	printf '%s|%s|%s|%s\n' "Codex CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_codex_cli() {
	_load_nvm
	if command -v codex >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
		npm i -g @openai/codex@latest
	else
		_msg "  Codex CLI or npm not installed, skipping"
	fi
}

# --- Claude CLI ---
claude_installed_version() {
	if command -v claude >/dev/null 2>&1; then
		claude --version 2>/dev/null | head -n1 || echo "installed"
	elif [[ -x "$HOME/.local/bin/claude" ]]; then
		"$HOME/.local/bin/claude" --version 2>/dev/null | head -n1 || echo "installed"
	else
		echo "$NOT_INSTALLED"
	fi
}

check_claude_cli() {
	local installed available action upgradable=0
	installed="$(claude_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		available="—"
		action="skip"
	else
		available="—"
		action="latest unchecked"
	fi
	printf '%s|%s|%s|%s\n' "Claude CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_claude_cli() {
	if command -v claude >/dev/null 2>&1; then
		claude update
	elif [[ -x "$HOME/.local/bin/claude" ]]; then
		"$HOME/.local/bin/claude" update
	else
		_msg "  Claude CLI not installed, skipping"
	fi
}

# --- Copilot CLI ---
copilot_command() {
	if command -v copilot >/dev/null 2>&1; then
		command -v copilot
	elif [[ -x "$HOME/.local/bin/copilot" ]]; then
		printf '%s\n' "$HOME/.local/bin/copilot"
	else
		return 1
	fi
}

copilot_installed_version() {
	local executable
	if executable="$(copilot_command)"; then
		"$executable" --version 2>/dev/null | head -n1 || echo "installed"
	else
		echo "$NOT_INSTALLED"
	fi
}

copilot_is_installed() {
	copilot_command >/dev/null 2>&1
}

check_copilot_cli() {
	local installed available action upgradable=0
	installed="$(copilot_installed_version)"
	if copilot_is_installed; then
		available="—"
		action="latest unchecked"
	else
		available="—"
		action="skip"
	fi
	printf '%s|%s|%s|%s\n' "Copilot CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_copilot_cli() {
	local executable
	if executable="$(copilot_command)"; then
		"$executable" update
	else
		_msg "  Copilot CLI not installed, skipping"
	fi
}

# --- lazygit ---
lazygit_installed_version() {
	if command -v lazygit >/dev/null 2>&1; then
		lazygit --version 2>/dev/null | grep -oP 'version=\K[0-9.]+' | head -n1 ||
			lazygit --version 2>/dev/null | head -n1 || echo "installed"
	else
		echo "$NOT_INSTALLED"
	fi
}

check_lazygit() {
	local installed latest available action upgradable=0
	installed="$(lazygit_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		available="—"
		action="skip"
	else
		latest="$(_github_latest_version jesseduffield/lazygit || true)"
		available="${latest:-—}"
		if [[ -n "$latest" ]] && _version_gt "$latest" "$installed"; then
			action="upgrade"
			upgradable=1
		else
			action="up to date"
		fi
	fi
	printf '%s|%s|%s|%s\n' "lazygit" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_lazygit() {
	if ! command -v lazygit >/dev/null 2>&1; then
		_msg "  lazygit not installed, skipping"
		return 0
	fi
	local installed latest
	installed="$(lazygit_installed_version)"
	latest="$(_github_latest_version jesseduffield/lazygit || true)"
	if [[ -n "$latest" && -n "$installed" ]] && _version_gt "$latest" "$installed"; then
		install_lazygit_from_github
	else
		_msg "  lazygit already up to date (${installed})"
	fi
}

# --- lazydocker ---
lazydocker_installed_version() {
	if command -v lazydocker >/dev/null 2>&1; then
		lazydocker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 ||
			echo "$NOT_INSTALLED"
	else
		echo "$NOT_INSTALLED"
	fi
}

check_lazydocker() {
	local installed latest available action upgradable=0
	installed="$(lazydocker_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		available="—"
		action="skip"
	else
		latest="$(_github_latest_version jesseduffield/lazydocker || true)"
		available="${latest:-—}"
		if [[ -n "$latest" ]] && _version_gt "$latest" "$installed"; then
			action="upgrade"
			upgradable=1
		else
			action="up to date"
		fi
	fi
	printf '%s|%s|%s|%s\n' "lazydocker" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_lazydocker() {
	if ! command -v lazydocker >/dev/null 2>&1; then
		_msg "  lazydocker not installed, skipping"
		return 0
	fi
	local installed latest
	installed="$(lazydocker_installed_version)"
	latest="$(_github_latest_version jesseduffield/lazydocker || true)"
	if [[ -n "$latest" && -n "$installed" ]] && _version_gt "$latest" "$installed"; then
		install_lazydocker_from_github
	else
		_msg "  lazydocker already up to date (${installed})"
	fi
}

# --- Monaspace fonts — opt-in ---
monaspace_installed_version() {
	local font_dir="$HOME/.local/share/fonts/monaspace"
	if [[ -d "$font_dir" ]] && compgen -G "${font_dir}/*.otf" >/dev/null 2>&1; then
		if [[ -f "${font_dir}/.version" ]]; then
			cat "${font_dir}/.version"
		else
			echo "installed"
		fi
	else
		echo "$NOT_INSTALLED"
	fi
}

monaspace_latest_version() {
	_github_latest_version githubnext/monaspace
}

check_monaspace() {
	local installed available action upgradable=0
	installed="$(monaspace_installed_version)"
	available="$(monaspace_latest_version 2>/dev/null || true)"
	[[ -n "$available" ]] || available="—"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		action="skip"
	elif [[ "$available" != "—" && "$installed" != "$available" ]]; then
		action="upgrade (--all)"
		upgradable=1
	else
		action="up to date"
	fi
	printf '%s|%s|%s|%s\n' "Monaspace fonts" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_monaspace() {
	local installed latest
	installed="$(monaspace_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		install_monaspace_fonts
		return $?
	fi
	latest="$(monaspace_latest_version 2>/dev/null || true)"
	if [[ -z "$latest" ]]; then
		_warn "  Could not check Monaspace release (GitHub API); keeping ${installed}"
		return 0
	fi
	if [[ "$installed" == "$latest" ]]; then
		_msg "  Monaspace fonts already up to date (${installed})"
		return 0
	fi
	install_monaspace_fonts --replace
}
