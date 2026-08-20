# shellcheck shell=bash
# Per-component status probes (_comp_probe_<id>).

_comp_probe_capture() {
	local output_name="$1" timeout_seconds="$2" captured='' rc
	shift 2
	if captured="$(timeout --kill-after=0.2 "$timeout_seconds" "$@" 2>/dev/null)"; then
		rc=0
	else
		rc=$?
	fi
	[[ "$rc" -eq 137 ]] && rc=124
	captured="${captured%%$'\n'*}"
	printf -v "$output_name" '%s' "$captured"
	return "$rc"
}

_install_short_label() {
	local label="$1"
	label="${label%%(*}"
	label="${label%% }"
	printf '%.22s' "$label"
}

_install_summary_probe() {
	comp_probe "$1"
}

collect_component_status_rows() {
	local output_name="$1"
	local -n output_rows="$output_name"
	mapfile -t output_rows < <(_collect_component_status_rows_stream)
}

_collect_component_status_rows_stream() (
	local probe_dir i key label probe result detail pid
	local -a pids=()
	probe_dir="$(mktemp -d)" || return 1
	trap 'rm -r -- "$probe_dir"' EXIT

	for i in "${!COMP_KEYS[@]}"; do
		key="${COMP_KEYS[$i]}"
		(
			if probe="$(_install_summary_probe "$key")"; then
				probe="${probe%%$'\n'*}"
				printf '%s\n' "${probe:-check|probe returned no result}"
			else
				printf 'check|probe failed\n'
			fi
		) >"$probe_dir/$i" &
		pids+=("$!")
	done

	for pid in "${pids[@]}"; do
		wait "$pid" || true
	done

	for i in "${!COMP_KEYS[@]}"; do
		label="$(_install_short_label "${COMP_LABELS[$i]}")"
		probe="$(<"$probe_dir/$i")"
		IFS='|' read -r result detail <<<"$probe"
		printf '%s|%s|%s\n' "$label" "$detail" "$result"
	done
)

_comp_probe_git_identity() {
	local name email
	name="$(git config --global user.name 2>/dev/null || true)"
	email="$(git config --global user.email 2>/dev/null || true)"
	if [[ -n "$name" && -n "$email" ]]; then
		printf 'configured|%s <%s>\n' "$name" "$email"
	else
		printf 'missing|not configured\n'
	fi
}

_comp_probe_system_packages() {
	local pkg_file="${PKG_FILE:-${DOTFILES_DIR:-}/packages/packages.txt}"
	local pkg status missing=0 checked=0 tags
	local -a packages=()

	if [[ ! -f "$pkg_file" ]]; then
		printf 'missing|packages.txt not found\n'
		return 0
	fi

	tags="$(comp_package_tags system_packages)"
	# shellcheck disable=SC2086 # Component package tags are an internal word list.
	mapfile -t packages < <(PKG_FILE="$pkg_file" read_packages_by_tags $tags)
	for pkg in "${packages[@]}"; do
		checked=$((checked + 1))
		status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
		if [[ "$status" != *"install ok installed"* ]]; then
			missing=$((missing + 1))
		fi
	done

	if [[ "$checked" -eq 0 ]]; then
		printf 'skipped|no packages listed\n'
	elif [[ "$missing" -eq 0 ]]; then
		printf 'installed|%d apt packages\n' "$checked"
	else
		printf 'missing|%d of %d packages not installed\n' "$missing" "$checked"
	fi
}

_comp_probe_python() {
	command -v python3 >/dev/null 2>&1 || {
		printf 'missing|python3 not on PATH\n'
		return
	}
	python3 -m pip --version >/dev/null 2>&1 || {
		printf 'missing|python3-pip unavailable\n'
		return
	}
	python3 -m venv --help >/dev/null 2>&1 || {
		printf 'missing|python3-venv unavailable\n'
		return
	}
	printf 'installed|python3 pip venv\n'
}

_comp_probe_graphify_cli() {
	local graphify_path ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if graphify_path="$(graphify_command 2>/dev/null)"; then
		_comp_probe_capture ver "$timeout_seconds" "$graphify_path" --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|graphify cli probe timed out\n'
			return
		fi
		if declare -F graphify_cli_is_uv_owned >/dev/null 2>&1 && graphify_cli_is_uv_owned; then
			printf 'installed|%s (uv)\n' "${ver:-$graphify_path}"
		else
			printf 'installed|%s\n' "${ver:-$graphify_path}"
		fi
	else
		printf 'missing|graphify not on PATH\n'
	fi
}

_comp_probe_powershell() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v pwsh >/dev/null 2>&1; then
		_comp_probe_capture ver "$timeout_seconds" pwsh --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|powershell probe timed out\n'
		else
			printf 'installed|%s\n' "${ver:-pwsh}"
		fi
	else
		printf 'missing|pwsh not on PATH\n'
	fi
}

_comp_probe_go() {
	local raw ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v go >/dev/null 2>&1; then
		_comp_probe_capture raw "$timeout_seconds" go version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|go probe timed out\n'
			return
		fi
		ver="$(grep -oE 'go[0-9.]+' <<<"$raw" | head -n1 || true)"
		if [[ -n "$ver" ]]; then
			printf 'installed|%s\n' "$ver"
			return
		fi
	fi
	if command -v asdf >/dev/null 2>&1; then
		rc=0
		_comp_probe_capture raw "$timeout_seconds" asdf current golang || rc=$?
		if [[ "$rc" -eq 124 ]]; then
			printf 'check|go probe timed out\n'
			return
		fi
		ver="$(awk '$1=="golang" {print $2; exit}' <<<"$raw")"
		if [[ -n "$ver" && "$ver" != system ]]; then
			printf 'installed|go%s (asdf)\n' "$ver"
		else
			printf 'missing|asdf has no selected Go version\n'
		fi
	else
		printf 'missing|working Go installation not found\n'
	fi
}

_comp_probe_nodejs() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
		# shellcheck source=/dev/null
		. "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
	fi
	if command -v node >/dev/null 2>&1; then
		_comp_probe_capture ver "$timeout_seconds" node --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|node probe timed out\n'
		else
			printf 'installed|node %s\n' "${ver:-unknown}"
		fi
	else
		printf 'missing|node not on PATH\n'
	fi
}

_comp_probe_direnv() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v direnv >/dev/null 2>&1; then
		_comp_probe_capture ver "$timeout_seconds" direnv version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|direnv probe timed out\n'
		else
			printf 'installed|%s\n' "${ver:-direnv}"
		fi
	else
		printf 'missing|direnv not on PATH\n'
	fi
}

_comp_probe_docker() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v docker >/dev/null 2>&1; then
		_comp_probe_capture ver "$timeout_seconds" docker --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|docker probe timed out\n'
		else
			printf 'installed|%s\n' "${ver:-docker}"
		fi
	else
		printf 'missing|docker not on PATH\n'
	fi
}

_comp_probe_portainer() {
	local name rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	_comp_probe_capture name "$timeout_seconds" docker ps -a \
		--filter 'name=^/portainer$' --format '{{.Names}}' || rc=$?
	if [[ "${rc:-0}" -eq 124 ]]; then
		printf 'check|portainer probe timed out\n'
	elif [[ "$name" == portainer ]]; then
		printf 'installed|container exists (stopped by default)\n'
	else
		printf 'missing|portainer container not found\n'
	fi
}

_comp_probe_lazygit() {
	local raw ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v lazygit >/dev/null 2>&1; then
		_comp_probe_capture raw "$timeout_seconds" lazygit --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|lazygit probe timed out\n'
			return
		fi
		ver="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$raw" | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-lazygit}"
	else
		printf 'missing|lazygit not on PATH\n'
	fi
}

_comp_probe_lazydocker() {
	local raw ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v lazydocker >/dev/null 2>&1; then
		_comp_probe_capture raw "$timeout_seconds" lazydocker --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|lazydocker probe timed out\n'
			return
		fi
		ver="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$raw" | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-lazydocker}"
	else
		printf 'missing|lazydocker not on PATH\n'
	fi
}

_comp_probe_cursor_cli() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1; then
		if command -v agent >/dev/null 2>&1; then
			_comp_probe_capture ver "$timeout_seconds" agent --version || rc=$?
		else
			_comp_probe_capture ver "$timeout_seconds" cursor --version || rc=$?
		fi
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|cursor cli probe timed out\n'
			return
		fi
		printf 'installed|%s\n' "${ver:-cursor cli}"
	elif [[ -x "$HOME/.local/bin/agent" ]]; then
		_comp_probe_capture ver "$timeout_seconds" "$HOME/.local/bin/agent" --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|cursor cli probe timed out\n'
			return
		fi
		printf 'installed|%s\n' "${ver:-cursor cli}"
	else
		printf 'missing|cursor/agent not on PATH\n'
	fi
}

_comp_probe_codex_cli() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
		# shellcheck source=/dev/null
		. "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
	fi
	if command -v codex >/dev/null 2>&1; then
		_comp_probe_capture ver "$timeout_seconds" codex --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|codex cli probe timed out\n'
		else
			printf 'installed|%s\n' "${ver:-codex cli}"
		fi
	else
		printf 'missing|codex not on PATH\n'
	fi
}

_comp_probe_claude_cli() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v claude >/dev/null 2>&1; then
		_comp_probe_capture ver "$timeout_seconds" claude --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|claude cli probe timed out\n'
			return
		fi
		printf 'installed|%s\n' "${ver:-claude cli}"
	elif [[ -x "$HOME/.local/bin/claude" ]]; then
		_comp_probe_capture ver "$timeout_seconds" "$HOME/.local/bin/claude" --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|claude cli probe timed out\n'
			return
		fi
		printf 'installed|%s\n' "${ver:-claude cli}"
	else
		printf 'missing|claude not on PATH\n'
	fi
}

_comp_probe_copilot_cli() {
	local ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v copilot >/dev/null 2>&1; then
		_comp_probe_capture ver "$timeout_seconds" copilot --version || rc=$?
	elif [[ -x "$HOME/.local/bin/copilot" ]]; then
		_comp_probe_capture ver "$timeout_seconds" "$HOME/.local/bin/copilot" --version || rc=$?
	else
		printf 'missing|copilot not on PATH\n'
		return
	fi
	if [[ "${rc:-0}" -eq 124 ]]; then
		printf 'check|copilot cli probe timed out\n'
	else
		printf 'installed|%s\n' "${ver:-copilot cli}"
	fi
}

_comp_probe_monaspace_fonts() {
	local font_dir count ver
	font_dir="$HOME/.local/share/fonts/monaspace"
	if [[ -d "$font_dir" ]] && compgen -G "${font_dir}/*.otf" >/dev/null 2>&1; then
		count="$(find "$font_dir" -maxdepth 1 -name '*.otf' 2>/dev/null | wc -l | tr -d ' ')"
		ver="installed"
		[[ -f "${font_dir}/.version" ]] && ver="$(cat "${font_dir}/.version")"
		printf 'installed|%s (%s fonts)\n' "$ver" "$count"
	else
		printf 'missing|fonts not in ~/.local/share/fonts/monaspace\n'
	fi
}

_comp_probe_ssh_key() {
	if [[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]]; then
		printf 'installed|~/.ssh key present\n'
	else
		printf 'missing|no default key found\n'
	fi
}

_comp_probe_dotfiles() {
	local repo_dir="${DOTFILES_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)}"
	local target expected missing=0
	while IFS='|' read -r target expected; do
		if [[ ! -L "$target" || "$(readlink -f "$target" 2>/dev/null || true)" != "$expected" ]]; then
			missing=$((missing + 1))
		fi
	done <<EOF
$HOME/.bashrc|$repo_dir/bash/.bashrc
$HOME/.bash_aliases|$repo_dir/bash/.bash_aliases
$HOME/.inputrc|$repo_dir/readline/.inputrc
$HOME/bin/ex|$repo_dir/bin/bin/ex
$HOME/bin/clip|$repo_dir/bin/bin/clip
$HOME/bin/dotfiles|$repo_dir/bin/bin/dotfiles
EOF
	if ((missing == 0)); then
		printf 'installed|stow bash bin readline\n'
	else
		printf 'missing|%d managed stow target(s) missing or incorrect\n' "$missing"
	fi
}

_comp_probe_wsl_conf() {
	local conf="${DOTFILES_WSL_CONF:-/etc/wsl.conf}"
	if [[ -f "$conf" ]] &&
		wsl_conf_has_setting "$conf" boot systemd true &&
		wsl_conf_has_setting "$conf" interop appendWindowsPath true; then
		printf 'configured|systemd + appendWindowsPath\n'
	else
		printf 'check|/etc/wsl.conf not as expected\n'
	fi
}

_comp_probe_git_credential() {
	local helper recurse fetch push summary
	helper="$(git config --global --get-all credential.helper 2>/dev/null || true)"
	recurse="$(git config --global --get submodule.recurse 2>/dev/null || true)"
	fetch="$(git config --global --get fetch.recurseSubmodules 2>/dev/null || true)"
	push="$(git config --global --get push.recurseSubmodules 2>/dev/null || true)"
	summary="$(git config --global --get status.submoduleSummary 2>/dev/null || true)"
	if [[ -n "$helper" && "$recurse" == true && "$fetch" == on-demand &&
		"$push" == check && "$summary" == true ]]; then
		printf 'configured|credential helper + recursive submodule defaults\n'
	elif [[ -z "$helper" && "$recurse" == true && "$fetch" == on-demand &&
		"$push" == check && "$summary" == true ]]; then
		printf 'check|submodule defaults set; credential helper not configured\n'
	else
		printf 'check|Git configuration incomplete\n'
	fi
}

print_install_summary() {
	local i key label row result detail short_label
	local ok_count=0 miss_count=0
	local cols

	cols="$(menu_tty_cols)"
	ui_print_report_header "Install summary" "" "$cols"
	ui_print_report_table_columns

	for i in "${!COMP_KEYS[@]}"; do
		key="${COMP_KEYS[$i]}"
		is_on "$key" || continue
		label="${COMP_LABELS[$i]}"
		row="$(_install_summary_probe "$key")"
		IFS='|' read -r result detail <<<"$row"
		short_label="$(_install_short_label "$label")"
		case "$result" in
		installed | configured) ((++ok_count)) ;;
		missing | check) ((++miss_count)) ;;
		esac
		ui_print_report_table_row "$short_label" "$detail" "$result"
	done

	echo ""
	if [[ $miss_count -eq 0 ]]; then
		echo "Install finished — ${ok_count} component(s) look good."
	else
		echo "Install finished — ${ok_count} ok, ${miss_count} need attention (see log above)."
	fi
}
