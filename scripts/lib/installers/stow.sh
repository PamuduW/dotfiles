# shellcheck shell=bash
# Requires: DOTFILES_DIR

apply_git_config() {
	git config --global user.name "$SETUP_GIT_NAME" || return $?
	git config --global user.email "$SETUP_GIT_EMAIL" || return $?
	log_ok "Git configured: $SETUP_GIT_NAME <$SETUP_GIT_EMAIL>"
}

generate_ssh_key() {
	if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
		log_skip "SSH key ~/.ssh/id_ed25519 already exists"
		return 0
	fi

	log_step "Generate SSH key (ed25519)"
	mkdir -p "$HOME/.ssh"
	local ssh_comment="${SETUP_GIT_EMAIL:-}"
	if [[ -z "$ssh_comment" ]]; then
		ssh_comment="${USER:-user}@$(hostname 2>/dev/null || echo wsl)"
	fi
	echo "  You'll be prompted for a passphrase (press Enter to skip / use no passphrase)."
	ssh-keygen -t ed25519 -C "$ssh_comment" -f "$HOME/.ssh/id_ed25519" || return $?
	eval "$(ssh-agent -s)" >/dev/null || return $?
	ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null || return $?

	local pub_key
	pub_key="$(cat "$HOME/.ssh/id_ed25519.pub")"

	cat >"$HOME/.ssh/github-setup.txt" <<EOF
SSH Key Setup Notes
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Public key:
  ${pub_key}

Next steps:
  1. Copy the public key above
  2. Go to https://github.com/settings/keys
  3. Click "New SSH key"
  4. Paste the key, give it a title (e.g. "WSL - $(hostname)")
  5. Test with: ssh -T git@github.com
EOF

	log_ok "SSH key generated"
	log_ok "Details saved to ~/.ssh/github-setup.txt"
}

configure_wsl() {
	local conf="${DOTFILES_WSL_CONF:-/etc/wsl.conf}" rendered backup_file

	if [[ -f "$conf" ]] &&
		wsl_conf_has_setting "$conf" boot systemd true &&
		wsl_conf_has_setting "$conf" interop appendWindowsPath true; then
		log_skip "$conf already configured"
		return 0
	fi

	log_step "Configure $conf"
	rendered="$(mktemp)" || return 1
	if ! wsl_conf_render_required "$conf" >"$rendered"; then
		rm -f "$rendered"
		log_warn "Could not render a safe WSL configuration"
		return 1
	fi

	if [[ "$conf" == /etc/* ]]; then
		if [[ -f "$conf" ]]; then
			backup_file="${conf}.bak.$(date +%Y%m%d_%H%M%S)"
			sudo cp "$conf" "$backup_file" || {
				rm -f "$rendered"
				return 1
			}
			log_ok "Backed up existing WSL config to $backup_file"
		fi
		sudo install -m 0644 "$rendered" "$conf" || {
			rm -f "$rendered"
			return 1
		}
	else
		[[ -f "$conf" ]] && cp "$conf" "${conf}.bak"
		install -m 0644 "$rendered" "$conf" || {
			rm -f "$rendered"
			return 1
		}
	fi
	rm -f "$rendered"

	log_ok "WSL config updated (restart WSL to apply: wsl --shutdown)"
}

find_windows_git_credential_manager() {
	local path
	local -a candidates=(
		"/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
		"/mnt/c/Program Files (x86)/Git/mingw64/bin/git-credential-manager.exe"
		"/mnt/c/Program Files/Git/mingw64/libexec/git-core/git-credential-manager.exe"
	)

	for path in "${candidates[@]}"; do
		if [[ -f "$path" ]]; then
			printf '%s\n' "$path"
			return 0
		fi
	done
	return 1
}

configure_git_submodule_defaults() {
	git config --global submodule.recurse true || return $?
	git config --global fetch.recurseSubmodules on-demand || return $?
	git config --global push.recurseSubmodules check || return $?
	git config --global status.submoduleSummary true || return $?
	log_ok "Git submodule defaults: recurse, on-demand fetch, checked push, status summary"
}

configure_git_settings() {
	local gcm_path=''
	configure_git_submodule_defaults || return 1
	if gcm_path="$(find_windows_git_credential_manager)"; then
		git config --global credential.helper "$gcm_path" || return 1
		log_ok "Git credential helper: $gcm_path"
	else
		log_warn "Windows Git Credential Manager not found"
		echo "    Submodule defaults were configured; the existing credential helper was unchanged."
	fi
}

post_install_fixes() {
	mkdir -p "$HOME/bin"
	if command -v fdfind >/dev/null 2>&1 && [[ ! -e "$HOME/bin/fd" ]]; then
		ln -s "$(command -v fdfind)" "$HOME/bin/fd"
	fi
}

DOTFILES_BACKUP_DIR=''

_dotfiles_managed_targets() {
	printf '%s\n' \
		"$HOME/.bashrc|.bashrc" \
		"$HOME/.bash_aliases|.bash_aliases" \
		"$HOME/.inputrc|.inputrc" \
		"$HOME/bin/ex|bin/ex" \
		"$HOME/bin/clip|bin/clip" \
		"$HOME/bin/dotfiles|bin/dotfiles"
}

backup_existing_dotfiles() {
	local timestamp target relative files_backed_up=0
	DOTFILES_BACKUP_DIR=''
	timestamp="$(date +%Y%m%d_%H%M%S)"

	while IFS='|' read -r target relative; do
		[[ -e "$target" && ! -L "$target" ]] || continue
		if [[ -z "$DOTFILES_BACKUP_DIR" ]]; then
			DOTFILES_BACKUP_DIR="$DOTFILES_DIR/old_bash_${timestamp}"
			mkdir -p "$DOTFILES_BACKUP_DIR"
			log_step "Back up existing dotfiles to: $DOTFILES_BACKUP_DIR"
		fi
		mkdir -p "$(dirname "$DOTFILES_BACKUP_DIR/$relative")"
		mv "$target" "$DOTFILES_BACKUP_DIR/$relative" || return 1
		log_ok "Backed up $relative"
		files_backed_up=$((files_backed_up + 1))
	done < <(_dotfiles_managed_targets)

	if ((files_backed_up > 0)); then
		log_ok "Backed up $files_backed_up file(s) in: $DOTFILES_BACKUP_DIR"
	fi
}

restore_dotfiles_backup() {
	local target relative backup resolved
	[[ -n "$DOTFILES_BACKUP_DIR" && -d "$DOTFILES_BACKUP_DIR" ]] || return 0
	while IFS='|' read -r target relative; do
		backup="$DOTFILES_BACKUP_DIR/$relative"
		[[ -e "$backup" ]] || continue
		if [[ -L "$target" ]]; then
			resolved="$(readlink -f "$target" 2>/dev/null || true)"
			[[ "$resolved" == "$DOTFILES_DIR/"* ]] && rm -f -- "$target"
		fi
		if [[ -e "$target" || -L "$target" ]]; then
			printf 'Error: cannot restore %s because the target is occupied. Backup remains at %s.\n' \
				"$target" "$backup" >&2
			continue
		fi
		mkdir -p "$(dirname "$target")"
		mv "$backup" "$target"
	done < <(_dotfiles_managed_targets)
	find "$DOTFILES_BACKUP_DIR" -depth -type d -empty -delete 2>/dev/null || true
	[[ -d "$DOTFILES_BACKUP_DIR" ]] || DOTFILES_BACKUP_DIR=''
}

stow_dotfiles() {
	if ! command -v stow >/dev/null 2>&1; then
		echo "Error: 'stow' is not installed." >&2
		return 1
	fi

	log_step "Apply stow packages: bash, bin, readline"
	if stow --dir "$DOTFILES_DIR" --target "$HOME" bash bin readline; then
		log_ok "Dotfiles stowed successfully"
	else
		echo "Error: stow failed. See output above." >&2
		restore_dotfiles_backup
		return 1
	fi
}

ensure_bash_profile_sources_bashrc() {
	local bash_profile="$HOME/.bash_profile"

	touch "$bash_profile"

	# shellcheck disable=SC2016  # Search for and write literal shell source lines.
	if grep -Fq '. "$HOME/.bashrc"' "$bash_profile" ||
		grep -Fq '. ~/.bashrc' "$bash_profile" ||
		grep -Fq 'source "$HOME/.bashrc"' "$bash_profile" ||
		grep -Fq 'source ~/.bashrc' "$bash_profile"; then
		log_skip "$HOME/.bash_profile already sources $HOME/.bashrc"
		return 0
	fi

	{
		echo ""
		echo "# Load interactive bash settings for login shells"
		# shellcheck disable=SC2016  # Write a portable literal for the target shell.
		echo 'if [ -f "$HOME/.bashrc" ]; then'
		# shellcheck disable=SC2016  # Write a portable literal for the target shell.
		echo '	. "$HOME/.bashrc"'
		echo 'fi'
	} >>"$bash_profile"

	log_ok "Updated ~/.bash_profile to source ~/.bashrc"
}
