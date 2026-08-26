# shellcheck shell=bash
# Tool discovery and version reading are shared with the status probes.
if ! declare -F tool_resolve >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/tool_resolve.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tool_resolve.sh"
fi

# --- Cursor CLI ---
cursor_installed_version() {
	local binary raw
	binary="$(tool_resolve 'agent cursor')" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
}

cursor_is_installed() {
	tool_resolve 'agent cursor' >/dev/null 2>&1
}

# Cursor publishes no queryable "latest" version, so this probe never reports an
# upgrade and always returns nonzero (no upgrade available).
check_cursor_cli() {
	local installed action
	installed="$(cursor_installed_version)"
	if cursor_is_installed; then
		action="$UPDATE_CHECK_UNKNOWN"
	else
		action="$UPDATE_CHECK_SKIP"
	fi
	printf '%s|%s|%s|%s\n' "Cursor CLI" "$installed" "—" "$action"
	return 1
}

upgrade_cursor_cli() {
	local executable='' update_rc=0 fallback_rc=0
	if command -v agent >/dev/null 2>&1; then
		executable="$(command -v agent)"
	elif command -v cursor >/dev/null 2>&1; then
		executable="$(command -v cursor)"
	elif [[ -x "$HOME/.local/bin/agent" ]]; then
		executable="$HOME/.local/bin/agent"
	fi
	if [[ -z "$executable" ]]; then
		_msg "  Cursor CLI not installed, skipping"
		upgrade_result_set skipped
		return 0
	fi
	"$executable" update || update_rc=$?
	if [[ $update_rc -eq 0 ]]; then
		upgrade_result_set checked-no-change
		return 0
	fi
	_warn "  Cursor primary update failed (exit $update_rc); retrying with the official installer."
	run_vendor_shell_installer 'https://cursor.com/install' 'Cursor CLI' || fallback_rc=$?
	[[ $fallback_rc -eq 0 ]] || return "$fallback_rc"
	upgrade_result_set recovered
}

# --- Codex CLI ---
codex_installed_version() {
	local binary raw
	_load_nvm
	binary="$(tool_resolve codex)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
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
		action="$UPDATE_CHECK_SKIP"
	else
		available="$(codex_available_version)"
		if [[ "$available" != "—" && "$installed" != *"${available}"* ]]; then
			action="$UPDATE_CHECK_UPGRADE"
			upgradable=1
		else
			available="${available:-—}"
			action="$UPDATE_CHECK_CURRENT"
		fi
	fi
	printf '%s|%s|%s|%s\n' "Codex CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_codex_cli() {
	_load_nvm
	if command -v codex >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
		npm i -g @openai/codex@latest || return $?
		upgrade_result_set updated
	else
		_msg "  Codex CLI or npm not installed, skipping"
		upgrade_result_set skipped
	fi
}

# --- Claude CLI ---
claude_installed_version() {
	local binary raw
	binary="$(tool_resolve claude)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
}

check_claude_cli() {
	local installed available action upgradable=0
	installed="$(claude_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		available="—"
		action="$UPDATE_CHECK_SKIP"
	else
		available="—"
		action="$UPDATE_CHECK_UNKNOWN"
	fi
	printf '%s|%s|%s|%s\n' "Claude CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_claude_cli() {
	if command -v claude >/dev/null 2>&1; then
		claude update || return $?
	elif [[ -x "$HOME/.local/bin/claude" ]]; then
		"$HOME/.local/bin/claude" update || return $?
	else
		_msg "  Claude CLI not installed, skipping"
		upgrade_result_set skipped
		return 0
	fi
	upgrade_result_set checked-no-change
}

# --- Copilot CLI ---
copilot_command() {
	tool_resolve copilot
}

copilot_installed_version() {
	local binary raw
	binary="$(copilot_command)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
}

copilot_is_installed() {
	copilot_command >/dev/null 2>&1
}

check_copilot_cli() {
	local installed available action upgradable=0
	installed="$(copilot_installed_version)"
	if copilot_is_installed; then
		available="—"
		action="$UPDATE_CHECK_UNKNOWN"
	else
		available="—"
		action="$UPDATE_CHECK_SKIP"
	fi
	printf '%s|%s|%s|%s\n' "Copilot CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_copilot_cli() {
	local executable
	if executable="$(copilot_command)"; then
		"$executable" update || return $?
		upgrade_result_set checked-no-change
	else
		_msg "  Copilot CLI not installed, skipping"
		upgrade_result_set skipped
	fi
}

# --- lazygit ---
lazygit_installed_version() {
	local binary raw version
	binary="$(tool_resolve lazygit)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	version="$(grep -oP 'version=\K[0-9.]+' <<<"$raw" | head -n1 || true)"
	printf '%s\n' "${version:-${raw%%$'\n'*}}"
}

check_lazygit() {
	local installed latest available action upgradable=0
	installed="$(lazygit_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		available="—"
		action="$UPDATE_CHECK_SKIP"
	else
		latest="$(_github_latest_version jesseduffield/lazygit || true)"
		available="${latest:-—}"
		if [[ -n "$latest" ]] && _version_gt "$latest" "$installed"; then
			action="$UPDATE_CHECK_UPGRADE"
			upgradable=1
		else
			action="$UPDATE_CHECK_CURRENT"
		fi
	fi
	printf '%s|%s|%s|%s\n' "lazygit" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_lazygit() {
	if ! command -v lazygit >/dev/null 2>&1; then
		_msg "  lazygit not installed, skipping"
		upgrade_result_set skipped
		return 0
	fi
	local installed latest
	installed="$(lazygit_installed_version)"
	latest="$(_github_latest_version jesseduffield/lazygit || true)"
	if [[ -n "$latest" && -n "$installed" ]] && _version_gt "$latest" "$installed"; then
		install_lazygit_from_github || return $?
		upgrade_result_set updated
	else
		_msg "  lazygit already up to date (${installed})"
		upgrade_result_set already-current
	fi
}

# --- lazydocker ---
lazydocker_installed_version() {
	local binary raw version
	binary="$(tool_resolve lazydocker)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo "$NOT_INSTALLED"
		return
	}
	version="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$raw" | head -n1 || true)"
	printf '%s\n' "${version:-$NOT_INSTALLED}"
}

check_lazydocker() {
	local installed latest available action upgradable=0
	installed="$(lazydocker_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		available="—"
		action="$UPDATE_CHECK_SKIP"
	else
		latest="$(_github_latest_version jesseduffield/lazydocker || true)"
		available="${latest:-—}"
		if [[ -n "$latest" ]] && _version_gt "$latest" "$installed"; then
			action="$UPDATE_CHECK_UPGRADE"
			upgradable=1
		else
			action="$UPDATE_CHECK_CURRENT"
		fi
	fi
	printf '%s|%s|%s|%s\n' "lazydocker" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_lazydocker() {
	if ! command -v lazydocker >/dev/null 2>&1; then
		_msg "  lazydocker not installed, skipping"
		upgrade_result_set skipped
		return 0
	fi
	local installed latest
	installed="$(lazydocker_installed_version)"
	latest="$(_github_latest_version jesseduffield/lazydocker || true)"
	if [[ -n "$latest" && -n "$installed" ]] && _version_gt "$latest" "$installed"; then
		install_lazydocker_from_github || return $?
		upgrade_result_set updated
	else
		_msg "  lazydocker already up to date (${installed})"
		upgrade_result_set already-current
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
		action="$UPDATE_CHECK_SKIP"
	elif [[ "$available" != "—" && "$installed" != "$available" ]]; then
		action="$UPDATE_CHECK_UPGRADE"
		upgradable=1
	else
		action="$UPDATE_CHECK_CURRENT"
	fi
	printf '%s|%s|%s|%s\n' "Monaspace fonts" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_monaspace() {
	local installed latest
	installed="$(monaspace_installed_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		install_monaspace_fonts || return $?
		upgrade_result_set updated
		return 0
	fi
	latest="$(monaspace_latest_version 2>/dev/null || true)"
	if [[ -z "$latest" ]]; then
		_warn "  Could not check Monaspace release (GitHub API); keeping ${installed}"
		upgrade_result_set checked-no-change
		return 0
	fi
	if [[ "$installed" == "$latest" ]]; then
		_msg "  Monaspace fonts already up to date (${installed})"
		upgrade_result_set already-current
		return 0
	fi
	install_monaspace_fonts --replace || return $?
	upgrade_result_set updated
}
