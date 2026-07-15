# shellcheck shell=bash
# Per-component description functions (_comp_desc_<id>).

_COMP_DESC_LINES=2

_comp_desc_git_identity() {
	echo "Set global git user.name and user.email."
	echo "Skip this if you use includeIf for per-directory identities."
}

_comp_desc_system_packages() {
	echo "Installs the curated apt package catalog from packages/packages.txt."
	echo "Package Lib shows every package name, tag, and description."
}

_comp_desc_python() {
	echo "Installs python3, pip, and venv via apt."
	echo "Provides the standard Python runtime and virtual-environment tooling."
}

_comp_desc_powershell() {
	echo "Installs Microsoft PowerShell from packages.microsoft.com."
	echo "Adds the Microsoft apt repository if missing, then installs 'powershell'."
}

_comp_desc_go() {
	echo "Installs latest Go via asdf and sets it global."
	echo "The selected Go version is available to shells and Go-based tools."
}

_comp_desc_nodejs() {
	echo "Installs Node.js v24 via nvm (Node Version Manager)."
	echo "Also provides npm for global packages like Codex CLI."
}

_comp_desc_direnv() {
	echo "Installs or updates direnv to ~/.local/bin via official installer."
	echo "Adds 'eval \"\$(direnv hook bash)\"' to ~/.bashrc if missing."
}

_comp_desc_docker() {
	echo "Installs Docker Engine CE from the official Docker apt repo and safely merges logging defaults into daemon.json."
	echo "Adds your user to the docker group for rootless access."
}

_comp_desc_portainer() {
	echo "Deploys the Portainer CE container (web UI for Docker)."
	echo "Container is stopped by default — start with 'dpot'."
}

_comp_desc_lazygit() {
	echo "Terminal UI for git. Downloaded from GitHub releases."
	echo "Use it to review status, stage changes, and manage commits interactively."
}

_comp_desc_lazydocker() {
	echo "Terminal UI for Docker. Downloaded from GitHub releases."
	echo "Use it to inspect containers, images, logs, and compose services."
}

_comp_desc_cursor_cli() {
	echo "Installs Cursor editor CLI from cursor.com."
	echo "Update later with 'update-cursor' or 'update-all'."
}

_comp_desc_codex_cli() {
	echo "Installs OpenAI Codex CLI via npm (requires Node.js)."
	echo "Update later with 'update-codex' or 'update-all'."
}

_comp_desc_claude_cli() {
	echo "Installs Anthropic Claude CLI from claude.ai."
	echo "Update later with 'update-claude' or 'update-all'."
}

_comp_desc_copilot_cli() {
	echo "Installs GitHub Copilot CLI via the official installer script."
	echo "Runs: curl -fsSL https://gh.io/copilot-install | bash"
}

_comp_desc_monaspace_fonts() {
	echo "Downloads GitHub Monaspace Nerd Fonts to ~/.local/share/fonts/."
	echo "Includes all 5 variants with Powerline glyphs and dev icons."
}

_comp_desc_ssh_key() {
	echo "Generates an ed25519 SSH key and adds it to ssh-agent."
	echo "Saves public key and GitHub setup steps to ~/.ssh/github-setup.txt."
}

_comp_desc_dotfiles() {
	echo "Uses GNU Stow to symlink bash, bin, and readline configs into \$HOME."
	echo "Backs up existing .bashrc, .bash_aliases, .inputrc first."
}

_comp_desc_wsl_conf() {
	echo "Sets systemd=true and appendWindowsPath=true in /etc/wsl.conf."
	echo "Requires 'wsl --shutdown' from Windows to take effect."
}

_comp_desc_git_credential() {
	echo "Configures git to use Windows Git Credential Manager for HTTPS auth."
	echo "Searches common install paths for git-credential-manager.exe."
}

_comp_menu_desc_fn() {
	comp_description "${COMP_KEYS[$1]}"
}

_comp_description_line() {
	menu_desc_nth_line_fn comp_description "${COMP_KEYS[$1]}" "$2"
}
