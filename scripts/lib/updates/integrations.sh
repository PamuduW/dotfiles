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
CODEX_RELEASE_VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-alpha(\.[0-9]+){0,2}|-beta(\.[0-9]+)?)?$'

codex_release_version_is_valid() {
	[[ "$1" =~ $CODEX_RELEASE_VERSION_REGEX ]]
}

codex_installed_version() {
	local binary raw
	binary="$(codex_visible_install_path)"
	codex_path_is_standalone_owned "$binary" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
}

codex_version_number() {
	local line word
	local -a words=()
	line="${1:-}"
	line="${line%%$'\n'*}"
	read -r -a words <<<"$line"
	for word in "${words[@]}"; do
		if codex_release_version_is_valid "$word"; then
			printf '%s\n' "$word"
			return 0
		fi
	done
	return 1
}

codex_latest_channel_json() {
	curl -fsSL --proto '=https' --tlsv1.2 'https://releases.openai.com/codex/channels/latest'
}

codex_available_version() {
	local json tag version
	json="$(codex_latest_channel_json 2>/dev/null)" || {
		printf '%s\n' '—'
		return 0
	}
	tag="$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("tag_name", ""))' <<<"$json" 2>/dev/null)" || {
		printf '%s\n' '—'
		return 0
	}
	[[ "$tag" == rust-v* ]] || {
		printf '%s\n' '—'
		return 0
	}
	version="${tag#rust-v}"
	if codex_release_version_is_valid "$version"; then
		printf '%s\n' "$version"
	else
		printf '%s\n' '—'
	fi
}

codex_semver_compare() {
	local left="$1" right="$2" left_core right_core left_pre='' right_pre=''
	local -a left_parts right_parts left_ids right_ids
	local i left_number right_number left_rank right_rank
	codex_release_version_is_valid "$left" && codex_release_version_is_valid "$right" || return 2

	left_core="${left%%-*}"
	right_core="${right%%-*}"
	[[ "$left" == *-* ]] && left_pre="${left#*-}"
	[[ "$right" == *-* ]] && right_pre="${right#*-}"
	IFS='.' read -r -a left_parts <<<"$left_core"
	IFS='.' read -r -a right_parts <<<"$right_core"
	for i in 0 1 2; do
		left_number=$((10#${left_parts[$i]}))
		right_number=$((10#${right_parts[$i]}))
		if ((left_number < right_number)); then
			printf '%s\n' -1
			return 0
		fi
		if ((left_number > right_number)); then
			printf '%s\n' 1
			return 0
		fi
	done

	if [[ -z "$left_pre" && -z "$right_pre" ]]; then
		printf '%s\n' 0
		return 0
	fi
	if [[ -z "$left_pre" ]]; then
		printf '%s\n' 1
		return 0
	fi
	if [[ -z "$right_pre" ]]; then
		printf '%s\n' -1
		return 0
	fi
	IFS='.' read -r -a left_ids <<<"$left_pre"
	IFS='.' read -r -a right_ids <<<"$right_pre"
	[[ "${left_ids[0]}" == alpha ]] && left_rank=0 || left_rank=1
	[[ "${right_ids[0]}" == alpha ]] && right_rank=0 || right_rank=1
	if ((left_rank < right_rank)); then
		printf '%s\n' -1
		return 0
	fi
	if ((left_rank > right_rank)); then
		printf '%s\n' 1
		return 0
	fi
	for ((i = 1; i < ${#left_ids[@]} && i < ${#right_ids[@]}; i++)); do
		left_number=$((10#${left_ids[$i]}))
		right_number=$((10#${right_ids[$i]}))
		if ((left_number < right_number)); then
			printf '%s\n' -1
			return 0
		fi
		if ((left_number > right_number)); then
			printf '%s\n' 1
			return 0
		fi
	done
	if ((${#left_ids[@]} < ${#right_ids[@]})); then
		printf '%s\n' -1
		return 0
	fi
	if ((${#left_ids[@]} > ${#right_ids[@]})); then
		printf '%s\n' 1
		return 0
	fi
	printf '%s\n' 0
}

check_codex_cli() {
	local state installed available installed_number comparison action upgradable=0
	state="$(codex_cli_install_state)" || state=absent
	case "$state" in
	standalone)
		installed="$(codex_installed_version)"
		available="$(codex_available_version)"
		installed_number="$(codex_version_number "$installed" 2>/dev/null || true)"
		if [[ "$available" == '—' || -z "$installed_number" ]]; then
			action="$UPDATE_CHECK_UNKNOWN"
		elif comparison="$(codex_semver_compare "$installed_number" "$available")"; then
			if ((comparison < 0)); then
				action="$UPDATE_CHECK_UPGRADE"
				upgradable=1
			else
				action="$UPDATE_CHECK_CURRENT"
			fi
		else
			available='—'
			action="$UPDATE_CHECK_UNKNOWN"
		fi
		;;
	absent)
		installed="$NOT_INSTALLED"
		available='—'
		action="$UPDATE_CHECK_SKIP"
		;;
	external)
		installed='external installation'
		available='—'
		action="$UPDATE_CHECK_EXTERNAL"
		;;
	standalone-shadowed)
		installed='standalone shadowed'
		available='—'
		action="$UPDATE_CHECK_EXTERNAL"
		;;
	*)
		installed="$NOT_INSTALLED"
		available='—'
		action="$UPDATE_CHECK_SKIP"
		;;
	esac
	printf '%s|%s|%s|%s\n' "Codex CLI" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_codex_cli() {
	local state before after active
	state="$(codex_cli_install_state)" || state=absent
	case "$state" in
	standalone)
		before="$(codex_installed_version)"
		codex_sync_standalone || return $?
		after="$(codex_installed_version)"
		if [[ "$before" != "$after" ]]; then
			upgrade_result_set updated
		else
			upgrade_result_set checked-no-change
		fi
		;;
	absent)
		_msg "  Codex CLI standalone is not installed, skipping"
		upgrade_result_set skipped
		;;
	external | standalone-shadowed)
		active="$(codex_active_command 2>/dev/null || true)"
		_msg "  Codex CLI is externally managed or shadowed: ${active:-unknown}"
		_msg "  See README.md#codex-cli-migration."
		upgrade_result_set skipped
		;;
	*)
		_msg "  Unknown Codex installation state, skipping"
		upgrade_result_set skipped
		;;
	esac
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
	local binary raw line
	binary="$(copilot_command)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	line="${raw%%$'\n'*}"
	line="${line%"${line##*[![:space:]]}"}"
	printf '%s\n' "${line%.}"
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
