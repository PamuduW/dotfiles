# shellcheck shell=bash
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
		action="$UPDATE_CHECK_SKIP"
	elif [[ "$available" != "—" ]] && _version_gt "$available" "$installed"; then
		action="$UPDATE_CHECK_UPGRADE"
		upgradable=1
	else
		action="$UPDATE_CHECK_CURRENT"
	fi
	printf '%s|%s|%s|%s\n' "Node.js (nvm)" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_node() {
	_load_nvm
	if ! command -v nvm >/dev/null 2>&1; then
		log_skip "nvm is not installed; skipping the Node.js upgrade"
		upgrade_result_set skipped
		return 0
	fi
	_run_quiet_command 'nvm install --lts' nvm install --lts || return $?
	_run_quiet_command 'nvm alias default' nvm alias --no-colors default 'lts/*' || return $?
	log_ok "Node.js on the LTS default ($(node_installed_version))"
	upgrade_result_set checked-no-change
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
		action="$UPDATE_CHECK_SKIP"
	elif [[ "$available" != "—" ]] && _version_gt "$available" "$installed"; then
		action="$UPDATE_CHECK_UPGRADE"
		upgradable=1
	else
		action="$UPDATE_CHECK_CURRENT"
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
		log_skip "nvm is not installed; skipping the npm upgrade"
		upgrade_result_set skipped
		return 0
	fi
	if [[ "$(npm_installed_version)" == "$NOT_INSTALLED" ]]; then
		log_skip "npm is not installed for the active Node version"
		upgrade_result_set skipped
		return 0
	fi
	if ! npm_version_token_is_safe "$target"; then
		log_warn "npm target is unavailable or invalid; refusing an unpinned upgrade"
		return 1
	fi
	if npm_version_reached "$target"; then
		log_skip "npm is already at the target version $target"
		upgrade_result_set already-current
		return 0
	fi

	_run_quiet_command 'nvm install-latest-npm' nvm install-latest-npm || nvm_rc=$?
	hash -r
	if npm_version_reached "$target"; then
		log_ok "npm verified at $(npm_installed_version)"
		upgrade_result_set updated
		return 0
	fi

	log_warn "nvm did not reach npm $target (exit $nvm_rc); trying the pinned fallback"
	log_step "Install npm@$target directly"
	_run_quiet_command "npm install -g npm@$target" \
		npm install -g "npm@$target" --engine-strict --allow-remote=all || fallback_rc=$?
	hash -r
	if [[ $fallback_rc -ne 0 ]] || ! npm_version_reached "$target"; then
		log_warn "npm remains at $(npm_installed_version); expected at least $target"
		[[ $fallback_rc -ne 0 ]] && return "$fallback_rc"
		return 1
	fi
	log_ok "npm verified at $(npm_installed_version)"
	upgrade_result_set recovered
}

# --- Go (asdf) — opt-in ---

# asdf installs to ~/.asdf and reaches PATH through the stowed .bashrc, so a
# process that has not sourced it cannot see it -- which is every `dotfiles
# update` run from a shell older than the install, and the bootstrap's update
# phase moments after its own install phase reported "Go installed". The update
# read that as "not installed" and skipped the Go upgrade.
#
# The installer already knows the location; this is the same knowledge on the
# reading side, and it publishes the shims too so `go` itself resolves.
_asdf_available() {
	command -v asdf >/dev/null 2>&1 && return 0
	local asdf_dir="${ASDF_DIR:-$HOME/.asdf}"
	[[ -x "$asdf_dir/bin/asdf" ]] || return 1
	export PATH="$asdf_dir/bin:$asdf_dir/shims:$PATH"
	hash -r 2>/dev/null || true
	command -v asdf >/dev/null 2>&1
}

go_installed_version() {
	if _asdf_available; then
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
	if _asdf_available; then
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
		action="$UPDATE_CHECK_SKIP"
	elif [[ "$available" != "—" ]] && _version_gt "$available" "$installed"; then
		action="$UPDATE_CHECK_UPGRADE"
		upgradable=1
	else
		action="$UPDATE_CHECK_CURRENT"
	fi
	printf '%s|%s|%s|%s\n' "Go (asdf)" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_go() {
	if ! _asdf_available; then
		log_skip "asdf is not installed; skipping the Go upgrade"
		upgrade_result_set skipped
		return 0
	fi
	_run_quiet_command 'asdf install golang latest' asdf install golang latest || return $?
	_run_quiet_command 'asdf set golang latest' asdf set -u golang latest || return $?
	_run_quiet_command 'asdf reshim golang' asdf reshim golang || return $?
	log_ok "Go on the latest asdf release ($(go_installed_version))"
	upgrade_result_set checked-no-change
}
