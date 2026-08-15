# shellcheck shell=bash
# Update component probes and upgrade operations. Public interface: CHECK_FUNCS
# plus the check_*/upgrade_* functions consumed by update_workflow.sh.

declare -A UPGRADE_STEP_RESULT=()

_report_command_failure() {
	local exit_status="$1" retry_command="$2"
	printf '%s>> FAILED (exit %s) — retry manually: %s <<%s\n' \
		"$C_RED" "$exit_status" "$retry_command" "$C_RESET" >&2
}

_run_upgrade_step() {
	local label="$1" retry_command="$2"
	shift 2
	printf '\n%s%s== %s ==%s\n' "$C_BOLD" "$C_YELLOW" "$label" "$C_RESET"
	set +e
	"$@"
	local rc=$?
	set -e
	if [[ $rc -ne 0 ]]; then
		_report_command_failure "$rc" "$retry_command"
		UPGRADE_STEP_RESULT["$label"]="failed"
	else
		UPGRADE_STEP_RESULT["$label"]="ok"
	fi
}

_github_latest_version() {
	github_latest_release_version "$1"
}

_version_gt() {
	# Returns 0 if $1 > $2 (sort -V)
	[[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" && "$1" != "$2" ]]
}

# Verify tarball SHA256 appears in a GitHub release checksums.txt (filename-agnostic).
_load_nvm() {
	local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
	# shellcheck source=/dev/null
	[[ -s "${nvm_dir}/nvm.sh" ]] && . "${nvm_dir}/nvm.sh"
}

# --- apt ---
apt_upgradable_count() {
	if ! command -v apt-get >/dev/null 2>&1; then
		echo 0
		return
	fi
	local count
	# Use cached indices for the pre-confirmation preview; refresh during apply.
	count="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || true)"
	echo "${count:-0}"
}

check_apt() {
	local count installed available action upgradable=0
	count="$(apt_upgradable_count)"
	if command -v apt-get >/dev/null 2>&1; then
		installed="system packages"
	else
		installed="$NOT_INSTALLED"
	fi
	if [[ "$count" -gt 0 ]]; then
		available="${count} package(s)"
		action="upgrade"
		upgradable=1
	else
		available="none"
		action="up to date"
	fi
	printf '%s|%s|%s|%s\n' "apt packages" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_apt() {
	if ! command -v apt-get >/dev/null 2>&1; then
		_warn "apt-get not found, skipping apt upgrade"
		return 0
	fi
	sudo apt-get update -qq && sudo apt-get -o Dpkg::Use-Pty=0 upgrade -y
}

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
copilot_installed_version() {
	if command -v copilot >/dev/null 2>&1; then
		copilot --version 2>/dev/null | head -n1 || echo "installed"
	elif [[ -x "$HOME/.local/bin/copilot" ]]; then
		"$HOME/.local/bin/copilot" --version 2>/dev/null | head -n1 || echo "installed"
	else
		echo "$NOT_INSTALLED"
	fi
}

copilot_is_installed() {
	command -v copilot >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/copilot" ]]
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
	if copilot_is_installed; then
		copilot update
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

# --- Node.js (nvm) — opt-in ---
node_installed_version() {
	_load_nvm
	if command -v nvm >/dev/null 2>&1; then
		local default_version
		default_version="$(nvm version default 2>/dev/null || true)"
		if [[ "$default_version" =~ ^v[0-9]+(\.[0-9]+){2}$ ]]; then
			printf '%s\n' "${default_version#v}"
			return 0
		fi
	fi
	if command -v node >/dev/null 2>&1; then
		node --version 2>/dev/null | tr -d 'v'
	else
		echo "$NOT_INSTALLED"
	fi
}

node_lts_version() {
	_load_nvm
	if command -v nvm >/dev/null 2>&1; then
		nvm version-remote --lts 2>/dev/null | tr -d 'v' || echo "—"
	else
		echo "—"
	fi
}

check_node() {
	local installed available action upgradable=0
	installed="$(node_installed_version)"
	available="$(node_lts_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		action="skip"
	elif [[ "$available" != "—" ]] && _version_gt "$available" "$installed"; then
		action="upgrade (--all)"
		upgradable=1
	else
		action="up to date"
	fi
	printf '%s|%s|%s|%s\n' "Node.js (nvm)" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_node() {
	_load_nvm
	if ! command -v nvm >/dev/null 2>&1; then
		_msg "  nvm not installed, skipping Node.js upgrade"
		return 0
	fi
	nvm install --lts || return $?
	nvm alias --no-colors default 'lts/*'
}

# --- npm (nvm) — opt-in ---
npm_installed_version() {
	_load_nvm
	if command -v npm >/dev/null 2>&1; then
		npm --version 2>/dev/null || echo "$NOT_INSTALLED"
	else
		echo "$NOT_INSTALLED"
	fi
}

npm_available_version() {
	_load_nvm
	if command -v npm >/dev/null 2>&1; then
		npm view npm version 2>/dev/null || echo "—"
	else
		echo "—"
	fi
}

check_npm() {
	local installed available action upgradable=0
	installed="$(npm_installed_version)"
	available="$(npm_available_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		action="skip"
	elif [[ "$available" != "—" ]] && _version_gt "$available" "$installed"; then
		action="upgrade (--all)"
		upgradable=1
	else
		action="up to date"
	fi
	printf '%s|%s|%s|%s\n' "npm" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

npm_version_token_is_safe() {
	[[ "${1:-}" =~ ^[0-9]+(\.[0-9]+){2}([+-][0-9A-Za-z.-]+)?$ ]]
}

npm_version_reached() {
	local target="${1:-}" observed
	npm_version_token_is_safe "$target" || return 1
	observed="$(npm_installed_version)"
	[[ "$observed" != "$NOT_INSTALLED" ]] || return 1
	npm_version_token_is_safe "$observed" || return 1
	[[ "$observed" == "$target" ]] || _version_gt "$observed" "$target"
}

upgrade_npm() {
	local target="${1:-}" nvm_rc=0 fallback_rc=0
	_load_nvm
	if ! command -v nvm >/dev/null 2>&1; then
		_msg "  nvm not installed, skipping npm upgrade"
		return 0
	fi
	if [[ "$(npm_installed_version)" == "$NOT_INSTALLED" ]]; then
		_msg "  npm not installed for the active Node version, skipping"
		return 0
	fi
	if ! npm_version_token_is_safe "$target"; then
		_warn "  npm target is unavailable or invalid; refusing an unpinned upgrade"
		return 1
	fi
	if npm_version_reached "$target"; then
		_msg "  npm is already at the target version $target"
		return 0
	fi

	nvm install-latest-npm || nvm_rc=$?
	hash -r
	if npm_version_reached "$target"; then
		_msg "  npm verified at $(npm_installed_version)"
		return 0
	fi

	_warn "  nvm did not reach npm $target (exit $nvm_rc); trying the pinned fallback"
	npm install -g "npm@$target" --engine-strict --allow-remote=all || fallback_rc=$?
	hash -r
	if [[ $fallback_rc -ne 0 ]] || ! npm_version_reached "$target"; then
		_warn "  npm remains at $(npm_installed_version); expected at least $target"
		[[ $fallback_rc -ne 0 ]] && return "$fallback_rc"
		return 1
	fi
	_msg "  npm verified at $(npm_installed_version)"
}

# --- Go (asdf) — opt-in ---
go_installed_version() {
	if command -v asdf >/dev/null 2>&1; then
		local ver
		ver="$(asdf current golang 2>/dev/null | awk '$1=="golang" {print $2; exit}')"
		if [[ -n "$ver" ]]; then
			echo "$ver"
		else
			echo "$NOT_INSTALLED"
		fi
	elif command -v go >/dev/null 2>&1; then
		go version 2>/dev/null | grep -oP 'go\K[0-9.]+' | head -n1 || echo "installed"
	else
		echo "$NOT_INSTALLED"
	fi
}

go_latest_version() {
	if command -v asdf >/dev/null 2>&1; then
		asdf latest golang 2>/dev/null || echo "—"
	else
		echo "—"
	fi
}

check_go() {
	local installed available action upgradable=0
	installed="$(go_installed_version)"
	available="$(go_latest_version)"
	if [[ "$installed" == "$NOT_INSTALLED" ]]; then
		action="skip"
	elif [[ "$available" != "—" ]] && _version_gt "$available" "$installed"; then
		action="upgrade (--all)"
		upgradable=1
	else
		action="up to date"
	fi
	printf '%s|%s|%s|%s\n' "Go (asdf)" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_go() {
	if ! command -v asdf >/dev/null 2>&1; then
		_msg "  asdf not installed, skipping Go upgrade"
		return 0
	fi
	asdf install golang latest || return $?
	asdf set -u golang latest || return $?
	asdf reshim golang
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

# --- dotfiles repo ---
dotfiles_repo_status() {
	if ! command -v git >/dev/null 2>&1; then
		echo "$NOT_INSTALLED|—|skip"
		return
	fi
	local branch local_rev installed available='none' action='up to date'
	branch="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
	local_rev="$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
	installed="${branch}@${local_rev}"
	case "${REPO_UPDATE_STATE:-current}" in
	ahead)
		available="${REPO_UPDATE_AHEAD:-0} local commit(s) ahead"
		action='verified'
		;;
	behind)
		available="${REPO_UPDATE_BEHIND:-0} commit(s) behind"
		action='verified'
		;;
	diverged)
		available="${REPO_UPDATE_AHEAD:-0} ahead / ${REPO_UPDATE_BEHIND:-0} behind"
		action='blocked'
		;;
	esac
	printf '%s|%s|%s|%s\n' "dotfiles repo" "$installed" "$available" "$action"
	[[ "$action" == blocked ]]
}

# --- Report helpers ---
CHECK_FUNCS=(
	check_apt
	check_graphify_cli
	check_cursor_cli
	check_codex_cli
	check_claude_cli
	check_copilot_cli
	check_lazygit
	check_lazydocker
	check_node
	check_npm
	check_go
	check_monaspace
	dotfiles_repo_status
)
