# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"

install_node_via_nvm() {
	if ! declare -F dotfiles_catalog_node_install >/dev/null; then
		# shellcheck source=/dev/null
		source "$_DOTFILES_CATALOG_LIB/catalog_runtimes.sh"
	fi
	dotfiles_catalog_node_install || return $?
	export PATH="$HOME/.local/bin:$PATH"
	hash -r
}

ensure_asdf_installed() {
	dotfiles_catalog_install "asdf"
}

install_go_via_asdf() {
	if ! declare -F dotfiles_catalog_go_install >/dev/null; then
		# shellcheck source=/dev/null
		source "$_DOTFILES_CATALOG_LIB/catalog_runtimes.sh"
	fi
	dotfiles_catalog_go_install
}

install_cursor_cli() {
	dotfiles_catalog_install "cursor_cli"
}

codex_sync_standalone() {
	dotfiles_catalog_install "codex_cli"
}

codex_nvm_migration_authorized() {
	case "${DOTFILES_MIGRATE_NPM_CODEX:-}" in
	1) return 0 ;;
	'') ;;
	*)
		printf '%s\n' '  DOTFILES_MIGRATE_NPM_CODEX must be 1 when set.' >&2
		return 1
		;;
	esac
	if [[ "${DOTFILES_INTERACTIVE_TTY:-false}" == true ]] && declare -F ui_confirm_yes_no >/dev/null 2>&1; then
		ui_confirm_yes_no '  Remove the listed npm Codex installations and install standalone?'
		return $?
	fi
	printf '%s\n' '  Re-run with DOTFILES_MIGRATE_NPM_CODEX=1 to authorize this migration.' >&2
	return 1
}

codex_migrate_nvm_installations() (
	local command_path tree directory rc=0 committed=0 keep_directory=0 index
	local -a commands=() rechecked=() packages=()
	if ! codex_nvm_migration_inventory commands; then
		printf '%s\n' '  cannot migrate unverified external Codex installation.' >&2
		return 1
	fi
	printf '  Migrating %d npm-managed Codex installations:\n' "${#commands[@]}"
	printf '    %s\n' "${commands[@]}"
	codex_nvm_migration_authorized || {
		printf '%s\n' '  Codex npm migration was not authorized; nothing was removed.' >&2
		return 1
	}
	[[ "${CODEX_INSTALL_DIR:-$HOME/.local/bin}" == "$HOME/.local/bin" ]] || {
		printf '%s\n' '  Catalog Codex requires CODEX_INSTALL_DIR to be ~/.local/bin.' >&2
		return 2
	}
	dotfiles_catalog_begin || return $?
	local version archive binary
	version="$(dotfiles_catalog_get codex_cli version)" || return 2
	archive="$(dotfiles_catalog_get codex_cli archive)" || return 2
	binary="$(dotfiles_catalog_get codex_cli binary)" || return 2
	[[ "$(dotfiles_catalog_get codex_cli owner)" == dotfiles && "$binary" == bin/codex ]] || return 2
	case "$archive" in tar | tar.gz | tar.xz | tgz | zip) ;; *) return 2 ;; esac
	directory="$(mktemp -d "${NVM_DIR:-$HOME/.nvm}/.dotfiles-codex-migration-XXXXXX")" || return 1
	# shellcheck disable=SC2329  # Invoked by this subshell's EXIT trap.
	codex_migration_cleanup() {
		local status=$? rollback_failed=0
		if [[ "$committed" == 0 ]]; then
			for ((index = ${#commands[@]} - 1; index >= 0; index--)); do
				if [[ -e "$directory/package-$index" ]]; then
					mv -- "$directory/package-$index" "${packages[index]}" || rollback_failed=1
				fi
				if [[ -e "$directory/command-$index" || -L "$directory/command-$index" ]]; then
					mv -- "$directory/command-$index" "${commands[index]}" || rollback_failed=1
				fi
			done
		fi
		if [[ "$rollback_failed" == 1 ]]; then
			keep_directory=1
			printf '  Codex migration rollback needs recovery; originals retained at %s.\n' "$directory" >&2
		fi
		[[ "$keep_directory" == 1 ]] || rm -rf -- "$directory"
		return "$status"
	}
	for command_path in "${commands[@]}"; do
		tree="${command_path%/bin/codex}"
		packages+=("$tree/lib/node_modules/@openai/codex")
	done
	trap 'codex_migration_cleanup' EXIT
	# Verify the complete approved bundle before moving any existing command.
	dotfiles_catalog_download codex_cli "$directory/archive" || return $?
	mkdir "$directory/payload" || return 1
	dotfiles_catalog_extract "$archive" "$directory/archive" "$directory/payload" || return $?
	dotfiles_catalog_codex_layout "$directory/payload" "$version" "$binary" || return 2
	dotfiles_catalog_codex_defaults || return 2
	dotfiles_catalog_version_matches "$directory/payload/$binary" "$version" --version || return 2
	codex_nvm_migration_inventory rechecked || return 2
	[[ "${rechecked[*]}" == "${commands[*]}" ]] || return 2
	# Keep originals until publication succeeds. Moving verified package paths
	# avoids running npm removal scripts or changing other global packages.
	for index in "${!commands[@]}"; do
		mv -- "${commands[index]}" "$directory/command-$index" || return $?
		mv -- "${packages[index]}" "$directory/package-$index" || return $?
	done
	hash -r
	if dotfiles_catalog_external codex_cli; then
		printf '%s\n' '  Another external Codex command would remain active; restoring npm installations.' >&2
		return 2
	fi
	dotfiles_catalog_install codex_cli "${DOTFILES_FORCE_REINSTALL:-0}" "$directory/archive" || rc=$?
	((rc == 0)) || return "$rc"
	committed=1
	log_ok "Codex CLI migrated from npm to the approved standalone bundle"
)

# PowerShell straight from the upstream release, for releases the Microsoft
# feed has not caught up with yet.
install_powershell_from_github() {
	dotfiles_catalog_install "powershell"
}

install_codex_cli() {
	local state active
	state="$(codex_cli_install_state)" || return $?
	case "$state" in
	absent | standalone | standalone-not-on-path) codex_sync_standalone ;;
	external | standalone-shadowed)
		active="$(codex_active_command)"
		codex_migrate_nvm_installations || {
			printf '  Migration did not complete; original active Codex path: %s\n' "${active:-unknown}" >&2
			printf '%s\n' '  See README.md#codex-cli-migration.' >&2
			return 1
		}
		;;
	*)
		printf '  Unknown Codex installation state: %s\n' "$state" >&2
		return 2
		;;
	esac
}

install_claude_cli() {
	dotfiles_catalog_install "claude_cli"
}

install_powershell() {
	dotfiles_catalog_install "powershell"
}

install_direnv() {
	local shortcut="$HOME/bin/direnv" managed="$HOME/.local/bin/direnv"
	if [[ -e "$shortcut" || -L "$shortcut" ]]; then
		if [[ ! -L "$shortcut" || "$(readlink -- "$shortcut")" != "$managed" ]]; then
			printf 'Preserving external direnv shortcut; activation is blocked.\n' >&2
			return 2
		fi
	fi
	dotfiles_catalog_install "direnv" || return $?
	if dotfiles_catalog_owned direnv; then
		mkdir -p -- "$HOME/bin" || return 1
		ln -sfn -- "$managed" "$shortcut" || return 1
	fi
}

ensure_direnv_hook_in_bashrc() {
	log_skip "direnv hook lives in stowed .bashrc"
}

ensure_wslview_browser_in_bashrc() {
	log_skip "BROWSER=wslview lives in stowed .bashrc"
}
