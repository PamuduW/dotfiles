# shellcheck shell=bash
# Read-only local state shared by component probes and managed CLI installers.

graphify_uv_command() {
	if command -v uv >/dev/null 2>&1; then
		command -v uv
	elif [[ -x "$HOME/.local/bin/uv" ]]; then
		printf '%s\n' "$HOME/.local/bin/uv"
	else
		return 1
	fi
}

graphify_command() {
	if command -v graphify >/dev/null 2>&1; then
		command -v graphify
	elif [[ -x "$HOME/.local/bin/graphify" ]]; then
		printf '%s\n' "$HOME/.local/bin/graphify"
	else
		return 1
	fi
}

graphify_cli_is_uv_owned() {
	local uv_cmd tool_list
	uv_cmd="$(graphify_uv_command)" || return 1
	tool_list="$("$uv_cmd" tool list 2>/dev/null)" || return 1
	grep -Eq '(^|[[:space:]])graphifyy([[:space:]]|$)' <<<"$tool_list"
}

graphify_installed_version() {
	local graphify_cmd version
	if graphify_cmd="$(graphify_command 2>/dev/null)"; then
		version="$("$graphify_cmd" --version 2>/dev/null | head -n1 || true)"
		printf '%s\n' "${version:-installed}"
	else
		printf '%s\n' 'not installed'
	fi
}

boost_install_path() {
	printf '%s\n' "$HOME/.local/bin/boost"
}

boost_management_stamp() {
	printf '%s\n' "$HOME/.local/share/dotfiles/boost-cli.version"
}

boost_command() {
	if command -v boost >/dev/null 2>&1; then
		command -v boost
	elif [[ -x "$HOME/.local/bin/boost" ]]; then
		printf '%s\n' "$HOME/.local/bin/boost"
	else
		return 1
	fi
}

boost_installed_version() {
	local boost_cmd version
	boost_cmd="$(boost_command 2>/dev/null)" || {
		printf '%s\n' 'not installed'
		return 0
	}
	version="$("$boost_cmd" version 2>/dev/null | head -n1 || true)"
	printf '%s\n' "${version:-installed}"
}

boost_cli_is_dotfiles_owned() {
	local command_path install_path stamp
	command_path="$(boost_command 2>/dev/null)" || return 1
	install_path="$(boost_install_path)"
	stamp="$(boost_management_stamp)"
	[[ "$command_path" == "$install_path" ]] || return 1
	[[ -f "$stamp" && ! -L "$stamp" ]] || return 1
	[[ "$(<"$stamp")" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]
}

boost_installed_tag() {
	local version
	version="$(boost_installed_version)"
	version="$(grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?' <<<"$version" | head -n1)"
	[[ -n "$version" ]] || return 1
	[[ "$version" == v* ]] || version="v$version"
	printf '%s\n' "$version"
}
