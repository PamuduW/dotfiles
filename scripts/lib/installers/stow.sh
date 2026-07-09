# shellcheck shell=bash
# Requires: DOTFILES_DIR

apply_git_config() {
	git config --global user.name "$SETUP_GIT_NAME"
	git config --global user.email "$SETUP_GIT_EMAIL"
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
	ssh-keygen -t ed25519 -C "$ssh_comment" -f "$HOME/.ssh/id_ed25519"
	eval "$(ssh-agent -s)" >/dev/null
	ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null

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
	local conf="/etc/wsl.conf"
	local needs_systemd=true
	local needs_interop=true

	if [[ -f "$conf" ]]; then
		grep -q 'systemd\s*=\s*true' "$conf" 2>/dev/null && needs_systemd=false
		grep -q 'appendWindowsPath\s*=\s*true' "$conf" 2>/dev/null && needs_interop=false
	fi

	if [[ "$needs_systemd" == "false" && "$needs_interop" == "false" ]]; then
		log_skip "/etc/wsl.conf already configured"
		return 0
	fi

	log_step "Configure /etc/wsl.conf"
	[[ -f "$conf" ]] && sudo cp "$conf" "${conf}.bak"

	if [[ "$needs_systemd" == "true" ]]; then
		if [[ -f "$conf" ]] && grep -qP '^\s*systemd\s*=' "$conf"; then
			sudo sed -i 's/^\(\s*\)systemd\s*=.*/\1systemd=true/' "$conf"
		elif [[ -f "$conf" ]] && grep -q '^\[boot\]' "$conf"; then
			sudo sed -i '/^\[boot\]/a systemd=true' "$conf"
		else
			printf '\n[boot]\nsystemd=true\n' | sudo tee -a "$conf" >/dev/null
		fi
	fi

	if [[ "$needs_interop" == "true" ]]; then
		if [[ -f "$conf" ]] && grep -qP '^\s*appendWindowsPath\s*=' "$conf"; then
			sudo sed -i 's/^\(\s*\)appendWindowsPath\s*=.*/\1appendWindowsPath=true/' "$conf"
		elif [[ -f "$conf" ]] && grep -q '^\[interop\]' "$conf"; then
			sudo sed -i '/^\[interop\]/a appendWindowsPath=true' "$conf"
		else
			printf '\n[interop]\nappendWindowsPath=true\n' | sudo tee -a "$conf" >/dev/null
		fi
	fi

	log_ok "WSL config updated (restart WSL to apply: wsl --shutdown)"
}

configure_git_credential_helper() {
	local gcm_path=""
	local -a candidates=(
		"/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
		"/mnt/c/Program Files (x86)/Git/mingw64/bin/git-credential-manager.exe"
		"/mnt/c/Program Files/Git/mingw64/libexec/git-core/git-credential-manager.exe"
	)

	for path in "${candidates[@]}"; do
		if [[ -f "$path" ]]; then
			gcm_path="$path"
			break
		fi
	done

	if [[ -n "$gcm_path" ]]; then
		git config --global credential.helper "$gcm_path"
		log_ok "Git credential helper: $gcm_path"
	else
		log_warn "Windows Git Credential Manager not found"
		echo "    Install Git for Windows, then re-run or set manually."
	fi
}

post_install_fixes() {
	mkdir -p "$HOME/bin"
	if command -v fdfind >/dev/null 2>&1 && [[ ! -e "$HOME/bin/fd" ]]; then
		ln -s "$(command -v fdfind)" "$HOME/bin/fd"
	fi
}

backup_existing_dotfiles() {
	local backup_dir="$DOTFILES_DIR/old_bash"
	local timestamp
	timestamp="$(date +%Y%m%d_%H%M%S)"
	local files_backed_up=0

	local needs_backup=false
	[[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]] && needs_backup=true
	[[ -f "$HOME/.bash_aliases" && ! -L "$HOME/.bash_aliases" ]] && needs_backup=true
	[[ -f "$HOME/.inputrc" && ! -L "$HOME/.inputrc" ]] && needs_backup=true
	[[ -f "$HOME/bin/ex" && ! -L "$HOME/bin/ex" ]] && needs_backup=true
	[[ -f "$HOME/bin/clip" && ! -L "$HOME/bin/clip" ]] && needs_backup=true

	if [[ "$needs_backup" == "false" ]]; then return 0; fi

	backup_dir="${backup_dir}_${timestamp}"
	mkdir -p "$backup_dir"
	log_step "Back up existing dotfiles to: $backup_dir"

	if [[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]]; then
		mv "$HOME/.bashrc" "$backup_dir/.bashrc"
		log_ok "Backed up .bashrc"
		((++files_backed_up))
	fi

	if [[ -f "$HOME/.bash_aliases" && ! -L "$HOME/.bash_aliases" ]]; then
		mv "$HOME/.bash_aliases" "$backup_dir/.bash_aliases"
		log_ok "Backed up .bash_aliases"
		((++files_backed_up))
	fi

	if [[ -f "$HOME/.inputrc" && ! -L "$HOME/.inputrc" ]]; then
		mv "$HOME/.inputrc" "$backup_dir/.inputrc"
		log_ok "Backed up .inputrc"
		((++files_backed_up))
	fi

	if [[ -f "$HOME/bin/ex" && ! -L "$HOME/bin/ex" ]]; then
		mkdir -p "$backup_dir/bin"
		mv "$HOME/bin/ex" "$backup_dir/bin/ex"
		log_ok "Backed up bin/ex"
		((++files_backed_up))
	fi

	if [[ -f "$HOME/bin/clip" && ! -L "$HOME/bin/clip" ]]; then
		mkdir -p "$backup_dir/bin"
		mv "$HOME/bin/clip" "$backup_dir/bin/clip"
		log_ok "Backed up bin/clip"
		((++files_backed_up))
	fi

	if [[ $files_backed_up -gt 0 ]]; then
		log_ok "Backed up $files_backed_up file(s) in: $backup_dir"
	fi
}

stow_dotfiles() {
	if ! command -v stow >/dev/null 2>&1; then
		echo "Error: 'stow' is not installed." >&2
		exit 1
	fi

	log_step "Apply stow packages: bash, bin, readline"
	if stow --dir "$DOTFILES_DIR" --target "$HOME" bash bin readline; then
		log_ok "Dotfiles stowed successfully"
	else
		echo "Error: stow failed. See output above." >&2
		exit 1
	fi
}

ensure_bash_profile_sources_bashrc() {
	local bash_profile="$HOME/.bash_profile"

	touch "$bash_profile"

	if grep -Fq '. "$HOME/.bashrc"' "$bash_profile" ||
		grep -Fq '. ~/.bashrc' "$bash_profile" ||
		grep -Fq 'source "$HOME/.bashrc"' "$bash_profile" ||
		grep -Fq 'source ~/.bashrc' "$bash_profile"; then
		log_skip "~/.bash_profile already sources ~/.bashrc"
		return 0
	fi

	{
		echo ""
		echo "# Load interactive bash settings for login shells"
		echo 'if [ -f "$HOME/.bashrc" ]; then'
		echo '	. "$HOME/.bashrc"'
		echo 'fi'
	} >>"$bash_profile"

	log_ok "Updated ~/.bash_profile to source ~/.bashrc"
}
