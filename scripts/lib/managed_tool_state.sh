# shellcheck shell=bash
# Read-only local state shared by component probes and managed CLI installers.

codex_standalone_root() {
	printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/packages/standalone"
}

codex_visible_install_path() {
	printf '%s\n' "${CODEX_INSTALL_DIR:-$HOME/.local/bin}/codex"
}

codex_active_command() {
	command -v codex 2>/dev/null
}

codex_path_is_standalone_owned() {
	local candidate="$1" candidate_path standalone_root
	[[ -f "$candidate" && -x "$candidate" ]] || return 1
	candidate_path="$(readlink -f -- "$candidate" 2>/dev/null)" || return 1
	standalone_root="$(readlink -f -- "$(codex_standalone_root)" 2>/dev/null)" || return 1
	[[ "$candidate_path" == "$standalone_root"/* ]]
}

codex_standalone_is_installed() {
	codex_path_is_standalone_owned "$(codex_visible_install_path)"
}

codex_cli_is_standalone_active() {
	local active_command active_path visible_path
	active_command="$(codex_active_command)" || return 1
	codex_path_is_standalone_owned "$active_command" || return 1
	active_path="$(readlink -f -- "$active_command" 2>/dev/null)" || return 1
	visible_path="$(readlink -f -- "$(codex_visible_install_path)" 2>/dev/null)" || return 1
	[[ "$active_path" == "$visible_path" ]]
}

codex_cli_install_state() {
	if codex_standalone_is_installed; then
		if codex_cli_is_standalone_active; then
			printf '%s\n' standalone
		else
			printf '%s\n' standalone-shadowed
		fi
	elif codex_active_command >/dev/null; then
		printf '%s\n' external
	else
		printf '%s\n' absent
	fi
}

codex_collect_nvm_commands() {
	local output_name="$1" root="${NVM_DIR:-$HOME/.nvm}" command_path
	local -n output_ref="$output_name"
	output_ref=()
	for command_path in "$root"/versions/node/*/bin/codex; do
		[[ -e "$command_path" ]] || continue
		output_ref+=("$command_path")
	done
}

codex_collect_nvm_packages() {
	local output_name="$1" root="${NVM_DIR:-$HOME/.nvm}" package_dir
	local -n output_ref="$output_name"
	output_ref=()
	for package_dir in "$root"/versions/node/*/lib/node_modules/@openai/codex; do
		[[ -e "$package_dir" ]] || continue
		output_ref+=("$package_dir")
	done
}

codex_nvm_command_is_managed_package() {
	local command_path="$1" tree package_dir canonical_command canonical_tree canonical_package
	tree="${command_path%/bin/codex}"
	package_dir="$tree/lib/node_modules/@openai/codex"
	[[ -x "$command_path" && -x "$tree/bin/npm" && -f "$package_dir/package.json" ]] || return 1
	canonical_command="$(readlink -f -- "$command_path" 2>/dev/null)" || return 1
	canonical_tree="$(readlink -f -- "$tree" 2>/dev/null)" || return 1
	canonical_package="$(readlink -f -- "$package_dir" 2>/dev/null)" || return 1
	[[ "$canonical_package" == "$canonical_tree"/* && "$canonical_command" == "$canonical_package"/* ]]
}

codex_nvm_migration_inventory() {
	local output_name="$1" active canonical_active command_path canonical_command active_matched=0
	local -a found_commands=() found_packages=()
	codex_collect_nvm_commands found_commands
	((${#found_commands[@]} > 0)) || return 1
	codex_collect_nvm_packages found_packages
	((${#found_packages[@]} == ${#found_commands[@]})) || return 1
	active="$(codex_active_command)" || return 1
	canonical_active="$(readlink -f -- "$active" 2>/dev/null)" || return 1
	for command_path in "${found_commands[@]}"; do
		codex_nvm_command_is_managed_package "$command_path" || return 1
		canonical_command="$(readlink -f -- "$command_path" 2>/dev/null)" || return 1
		[[ "$canonical_active" == "$canonical_command" ]] && active_matched=1
	done
	[[ "$active_matched" -eq 1 ]] || return 1
	local -n output_ref="$output_name"
	output_ref=("${found_commands[@]}")
}

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
