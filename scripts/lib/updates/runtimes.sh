# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"
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
	dotfiles_catalog_begin && dotfiles_catalog_get nodejs version
}

check_node() {
	dotfiles_catalog_check nodejs "Node.js (nvm)"
}

upgrade_node() {
	dotfiles_catalog_upgrade nodejs
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
	dotfiles_catalog_begin && dotfiles_catalog_get npm version
}

check_npm() {
	dotfiles_catalog_check npm "npm"
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
	dotfiles_catalog_upgrade npm
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
	dotfiles_catalog_begin && dotfiles_catalog_get go version
}

check_go() {
	dotfiles_catalog_check go "Go (asdf)"
}

upgrade_go() {
	dotfiles_catalog_upgrade go
}
