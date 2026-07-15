# shellcheck shell=bash
# Per-component status probes (_comp_probe_<id>).

_install_short_label() {
	local label="$1"
	label="${label%%(*}"
	label="${label%% }"
	printf '%.22s' "$label"
}

_install_summary_probe() {
	comp_probe "$1"
}

_comp_probe_git_identity() {
	local name email
	name="$(git config --global user.name 2>/dev/null || true)"
	email="$(git config --global user.email 2>/dev/null || true)"
	if [[ -n "$name" && -n "$email" ]]; then
		printf 'configured|%s <%s>\n' "$name" "$email"
	else
		printf 'skipped|not configured\n'
	fi
}

_comp_probe_system_packages() {
	local pkg_file="${PKG_FILE:-${DOTFILES_DIR:-}/packages/packages.txt}"
	local line pkg status missing=0 checked=0

	if [[ ! -f "$pkg_file" ]]; then
		printf 'missing|packages.txt not found\n'
		return 0
	fi

	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%%#*}"
		line="${line// /}"
		[[ -n "$line" ]] || continue
		pkg="$line"
		checked=$((checked + 1))
		status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
		if [[ "$status" != *"install ok installed"* ]]; then
			missing=$((missing + 1))
		fi
	done <"$pkg_file"

	if [[ "$checked" -eq 0 ]]; then
		printf 'skipped|no packages listed\n'
	elif [[ "$missing" -eq 0 ]]; then
		printf 'installed|%d apt packages\n' "$checked"
	else
		printf 'missing|%d of %d packages not installed\n' "$missing" "$checked"
	fi
}

_comp_probe_python() {
	printf 'installed|python3 pip venv\n'
}

_comp_probe_powershell() {
	if command -v pwsh >/dev/null 2>&1; then
		printf 'installed|%s\n' "$(pwsh --version 2>/dev/null | head -n1)"
	else
		printf 'missing|pwsh not on PATH\n'
	fi
}

_comp_probe_go() {
	local ver
	if command -v go >/dev/null 2>&1; then
		ver="$(go version 2>/dev/null | grep -oE 'go[0-9.]+' | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-go}"
	elif command -v asdf >/dev/null 2>&1; then
		ver="$(asdf current golang 2>/dev/null | awk '$1=="golang" {print $2; exit}')"
		printf 'installed|%s\n' "${ver:-asdf golang}"
	else
		printf 'missing|go not on PATH\n'
	fi
}

_comp_probe_nodejs() {
	if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
		# shellcheck source=/dev/null
		. "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
	fi
	if command -v node >/dev/null 2>&1; then
		printf 'installed|node %s\n' "$(node --version 2>/dev/null)"
	else
		printf 'missing|node not on PATH\n'
	fi
}

_comp_probe_direnv() {
	if command -v direnv >/dev/null 2>&1; then
		printf 'installed|%s\n' "$(direnv version 2>/dev/null | head -n1)"
	else
		printf 'missing|direnv not on PATH\n'
	fi
}

_comp_probe_docker() {
	if command -v docker >/dev/null 2>&1; then
		printf 'installed|%s\n' "$(docker --version 2>/dev/null | head -n1)"
	else
		printf 'missing|docker not on PATH\n'
	fi
}

_comp_probe_portainer() {
	if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
		printf 'installed|container exists (stopped by default)\n'
	else
		printf 'missing|portainer container not found\n'
	fi
}

_comp_probe_lazygit() {
	local ver
	if command -v lazygit >/dev/null 2>&1; then
		ver="$(lazygit --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-lazygit}"
	else
		printf 'missing|lazygit not on PATH\n'
	fi
}

_comp_probe_lazydocker() {
	local ver
	if command -v lazydocker >/dev/null 2>&1; then
		ver="$(lazydocker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-lazydocker}"
	else
		printf 'missing|lazydocker not on PATH\n'
	fi
}

_comp_probe_cursor_cli() {
	local ver
	if command -v agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1; then
		if command -v agent >/dev/null 2>&1; then
			ver="$(agent --version 2>/dev/null | head -n1 || true)"
		else
			ver="$(cursor --version 2>/dev/null | head -n1 || true)"
		fi
		printf 'installed|%s\n' "${ver:-cursor cli}"
	elif [[ -x "$HOME/.local/bin/agent" ]]; then
		ver="$("$HOME/.local/bin/agent" --version 2>/dev/null | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-cursor cli}"
	else
		printf 'missing|cursor/agent not on PATH\n'
	fi
}

_comp_probe_codex_cli() {
	if command -v codex >/dev/null 2>&1; then
		printf 'installed|%s\n' "$(codex --version 2>/dev/null | head -n1)"
	else
		printf 'missing|codex not on PATH\n'
	fi
}

_comp_probe_claude_cli() {
	local ver
	if command -v claude >/dev/null 2>&1; then
		ver="$(claude --version 2>/dev/null | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-claude cli}"
	elif [[ -x "$HOME/.local/bin/claude" ]]; then
		ver="$("$HOME/.local/bin/claude" --version 2>/dev/null | head -n1 || true)"
		printf 'installed|%s\n' "${ver:-claude cli}"
	else
		printf 'missing|claude not on PATH\n'
	fi
}

_comp_probe_copilot_cli() {
	if command -v copilot >/dev/null 2>&1; then
		printf 'installed|%s\n' "$(copilot --version 2>/dev/null | head -n1)"
	elif [[ -x "$HOME/.local/bin/copilot" ]]; then
		printf 'installed|%s\n' "$("$HOME/.local/bin/copilot" --version 2>/dev/null | head -n1)"
	else
		printf 'missing|copilot not on PATH\n'
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
		printf 'skipped|no default key found\n'
	fi
}

_comp_probe_dotfiles() {
	if [[ -e "$HOME/bin/dotfiles" || -e "$HOME/bin/ex" ]]; then
		printf 'installed|stow bash bin readline\n'
	else
		printf 'check|~/bin symlinks missing\n'
	fi
}

_comp_probe_wsl_conf() {
	if [[ -f /etc/wsl.conf ]] && grep -q '^systemd=true' /etc/wsl.conf 2>/dev/null; then
		printf 'configured|systemd + appendWindowsPath\n'
	else
		printf 'check|/etc/wsl.conf not as expected\n'
	fi
}

_comp_probe_git_credential() {
	local gcm
	gcm="$(git config --global credential.helper 2>/dev/null || true)"
	if [[ -n "$gcm" ]]; then
		printf 'configured|%s\n' "$gcm"
	else
		printf 'skipped|no global credential.helper\n'
	fi
}

print_install_summary() {
	local i key label row result detail short_label
	local ok_count=0 miss_count=0

	echo ""
	printf '%s=== Install summary ===%s\n' "${C_ORANGE:-}" "${C_RESET:-}"
	printf '%-22s | %-32s | %s\n' "component" "detail" "result"
	printf '%s\n' "----------------------+----------------------------------+-----------"

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
		ui_print_component_table_row "$short_label" "$detail" "$result"
	done

	echo ""
	if [[ $miss_count -eq 0 ]]; then
		echo "Install finished — ${ok_count} component(s) look good."
	else
		echo "Install finished — ${ok_count} ok, ${miss_count} need attention (see log above)."
	fi
}
