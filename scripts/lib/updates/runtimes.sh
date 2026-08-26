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
		_msg "  nvm not installed, skipping Node.js upgrade"
		upgrade_result_set skipped
		return 0
	fi
	nvm install --lts || return $?
	nvm alias --no-colors default 'lts/*' || return $?
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
		_msg "  nvm not installed, skipping npm upgrade"
		upgrade_result_set skipped
		return 0
	fi
	if [[ "$(npm_installed_version)" == "$NOT_INSTALLED" ]]; then
		_msg "  npm not installed for the active Node version, skipping"
		upgrade_result_set skipped
		return 0
	fi
	if ! npm_version_token_is_safe "$target"; then
		_warn "  npm target is unavailable or invalid; refusing an unpinned upgrade"
		return 1
	fi
	if npm_version_reached "$target"; then
		_msg "  npm is already at the target version $target"
		upgrade_result_set already-current
		return 0
	fi

	nvm install-latest-npm || nvm_rc=$?
	hash -r
	if npm_version_reached "$target"; then
		_msg "  npm verified at $(npm_installed_version)"
		upgrade_result_set updated
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
	upgrade_result_set recovered
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
	if ! command -v asdf >/dev/null 2>&1; then
		_msg "  asdf not installed, skipping Go upgrade"
		upgrade_result_set skipped
		return 0
	fi
	asdf install golang latest || return $?
	asdf set -u golang latest || return $?
	asdf reshim golang || return $?
	upgrade_result_set checked-no-change
}
