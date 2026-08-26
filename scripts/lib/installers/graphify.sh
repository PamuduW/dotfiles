# shellcheck shell=bash

GRAPHIFY_UV_INSTALL_URL="https://astral.sh/uv/install.sh"

if ! declare -F graphify_command >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi

check_graphify_cli() {
	local installed action
	installed="$(graphify_installed_version)"
	if [[ "$installed" == "not installed" ]]; then
		action=skip
	elif graphify_cli_is_uv_owned; then
		action=unknown
	else
		action=external
	fi
	printf '%s|%s|%s|%s\n' "Graphify CLI" "$installed" "—" "$action"
}

upgrade_graphify_cli() {
	local uv_cmd
	if [[ "$(graphify_installed_version)" == "not installed" ]]; then
		printf '%s\n' '  Graphify CLI not installed, skipping'
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	if ! graphify_cli_is_uv_owned; then
		printf '%s\n' '  Graphify CLI is externally managed, skipping uv upgrade'
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	uv_cmd="$(graphify_uv_command)" || return 1
	if ! "$uv_cmd" tool upgrade graphifyy; then
		"$uv_cmd" tool upgrade graphifyy --system-certs || return $?
	fi
	printf '%s\n' \
		"  If Agentbot's Graphify integration is enabled, run agentbot graphify setup" \
		"  or agentbot update to refresh the installed skill."
	if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set checked-no-change; fi
}

ensure_graphify_uv() {
	local py_version py_major py_minor tmp
	if graphify_uv_command >/dev/null 2>&1; then
		return 0
	fi

	command -v curl >/dev/null 2>&1 || {
		echo "  curl is required to install uv for Graphify." >&2
		return 1
	}
	command -v python3 >/dev/null 2>&1 || {
		echo "  python3 is required to install Graphify." >&2
		return 1
	}
	py_version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" || {
		echo "  Could not determine the installed Python version." >&2
		return 1
	}
	py_major="${py_version%%.*}"
	py_minor="${py_version#*.}"
	if ((py_major < 3 || (py_major == 3 && py_minor < 10))); then
		echo "  Graphify requires Python 3.10 or newer; found ${py_version}." >&2
		return 1
	fi

	tmp="$(mktemp)"
	if ! curl -LsSf "$GRAPHIFY_UV_INSTALL_URL" >"$tmp"; then
		rm -f -- "$tmp"
		echo "  Failed to download the official uv installer." >&2
		return 1
	fi
	if ! sh "$tmp"; then
		rm -f -- "$tmp"
		echo "  The official uv installer failed." >&2
		return 1
	fi
	rm -f -- "$tmp"

	graphify_uv_command >/dev/null 2>&1 || {
		echo "  uv installed but is not available at ${HOME}/.local/bin/uv." >&2
		return 1
	}
}

install_graphify_cli() {
	local graphify_cmd uv_cmd
	if graphify_cmd="$(graphify_command 2>/dev/null)"; then
		if graphify_cli_is_uv_owned; then
			log_skip "Graphify CLI already installed via uv"
		else
			log_warn "Graphify CLI already exists outside uv; preserving external installation"
		fi
		return 0
	fi

	ensure_graphify_uv || return 1
	uv_cmd="$(graphify_uv_command)" || return 1
	log_step "Install Graphify CLI (graphifyy)"
	if ! _run_quiet_command "Graphify CLI install" "$uv_cmd" tool install graphifyy; then
		return 1
	fi

	if graphify_cmd="$(graphify_command 2>/dev/null)"; then
		log_ok "Graphify CLI installed at ${graphify_cmd}"
		return 0
	fi
	echo "  Graphify installed, but graphify is not on PATH. Add ${HOME}/.local/bin to PATH, then retry: uv tool install graphifyy" >&2
	return 1
}
