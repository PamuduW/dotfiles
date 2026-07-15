# shellcheck shell=bash

install_node_via_nvm() {
	local NVM_DIR="${HOME}/.nvm"
	local NVM_MIN_NODE="24"

	if command -v node >/dev/null 2>&1; then
		local current_major
		current_major="$(node --version | grep -oP '^v\K[0-9]+')"
		if [[ "$current_major" -ge "$NVM_MIN_NODE" ]]; then
			log_skip "Node.js v$(node --version | tr -d 'v') already installed"
			return 0
		fi
	fi

	if [[ ! -d "$NVM_DIR" ]]; then
		log_step "Install nvm"
		local wsl_clean_path
		wsl_clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':' | sed 's/:$//')"
		local nvm_tmp
		nvm_tmp="$(mktemp)"
		if ! { curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh |
			PROFILE=/dev/null PATH="$wsl_clean_path" bash; } >"$nvm_tmp" 2>&1; then
			echo "  Error during nvm install:" >&2
			cat "$nvm_tmp" >&2
			rm -f "$nvm_tmp"
			return 1
		fi
		rm -f "$nvm_tmp"
	fi

	export NVM_DIR
	# shellcheck source=/dev/null
	[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

	log_step "Install Node.js ${NVM_MIN_NODE} via nvm"
	_run_quiet_command "Node.js install" nvm install "$NVM_MIN_NODE"
	_run_quiet_command "Node.js default alias" nvm alias default "$NVM_MIN_NODE"
	log_ok "Node.js $(node --version) installed via nvm"
}

ensure_asdf_installed() {
	local asdf_dir="$HOME/.asdf"
	local asdf_bin="$asdf_dir/bin/asdf"
	local needs_install=0
	if [[ ! -x "$asdf_bin" ]]; then
		needs_install=1
	elif head -n 1 "$asdf_bin" 2>/dev/null | grep -q '^#!/usr/bin/env bash'; then
		needs_install=1
	fi

	if [[ "$needs_install" -eq 1 ]]; then
		command -v curl >/dev/null 2>&1 || {
			echo "  curl is required to install asdf." >&2
			return 1
		}
		command -v tar >/dev/null 2>&1 || {
			echo "  tar is required to install asdf." >&2
			return 1
		}

		local arch
		case "$(uname -m)" in
		x86_64 | amd64) arch="amd64" ;;
		aarch64 | arm64) arch="arm64" ;;
		i386 | i686) arch="386" ;;
		*)
			echo "  Unsupported architecture for asdf: $(uname -m)" >&2
			return 1
			;;
		esac

		echo "Installing asdf..."
		local tag tmp tarball_url tarball_name expected_sha256 actual_sha256 extracted
		tag="$(github_latest_release_version asdf-vm/asdf)" || {
			echo "  Could not determine latest asdf release." >&2
			return 1
		}

		tarball_name="asdf-v${tag}-linux-${arch}.tar.gz"
		tarball_url="https://github.com/asdf-vm/asdf/releases/download/v${tag}/${tarball_name}"
		command -v sha256sum >/dev/null 2>&1 || {
			echo "  sha256sum is required to verify the asdf release." >&2
			return 1
		}
		expected_sha256="$(github_release_asset_sha256 asdf-vm/asdf "$tarball_name")" || {
			echo "  Could not obtain the published SHA-256 digest for ${tarball_name}; refusing unchecked download." >&2
			return 1
		}
		tmp="$(mktemp -d)"
		trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
		if ! github_curl -fsSL -o "$tmp/asdf.tar.gz" "$tarball_url"; then
			echo "  Failed to download asdf. Check TLS trust in WSL or retry after fixing CA certificates." >&2
			return 1
		fi
		actual_sha256="$(sha256sum "$tmp/asdf.tar.gz" | awk '{print $1}')"
		if [[ "$actual_sha256" != "$expected_sha256" ]]; then
			echo "  asdf SHA-256 verification failed; refusing to install the downloaded binary." >&2
			return 1
		fi

		mkdir -p "$asdf_dir/bin"
		rm -f "$asdf_bin"
		if ! tar -xzf "$tmp/asdf.tar.gz" -C "$asdf_dir/bin" asdf 2>/dev/null; then
			tar -xzf "$tmp/asdf.tar.gz" -C "$tmp"
			extracted="$(find "$tmp" -maxdepth 3 -type f -name asdf | head -n1 || true)"
			[[ -n "$extracted" ]] || {
				echo "  Failed to extract asdf binary." >&2
				return 1
			}
			install -m 0755 "$extracted" "$asdf_bin"
		fi
		chmod +x "$asdf_bin"
		rm -rf "$tmp"
		trap - RETURN
	fi

	export PATH="$asdf_dir/bin:$asdf_dir/shims:$PATH"

	command -v asdf >/dev/null 2>&1 || {
		echo "  asdf install completed but command is still unavailable." >&2
		return 1
	}

	log_ok "asdf available"
}

install_go_via_asdf() {
	if ! ensure_asdf_installed; then
		echo "  Could not set up asdf for Go installation." >&2
		return 1
	fi

	if ! asdf plugin list 2>/dev/null | grep -qx 'golang'; then
		log_step "Add asdf golang plugin"
		asdf plugin add golang
	fi

	log_step "Install Go latest via asdf"
	_run_quiet_command "Go install" asdf install golang latest
	_run_quiet_command "Go version selection" asdf set -u golang latest
	asdf reshim golang 2>/dev/null || true
	log_ok "Go installed and set for user via asdf"
}

install_cursor_cli() {
	if command -v agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1; then
		if [[ ! -x "$HOME/bin/agent" && -x "$HOME/.local/bin/agent" ]]; then
			mkdir -p "$HOME/bin"
			ln -sf "$HOME/.local/bin/agent" "$HOME/bin/agent"
		fi
		log_skip "Cursor CLI already installed"
		return 0
	fi
	log_step "Install Cursor CLI"
	local cursor_tmp
	cursor_tmp="$(mktemp)"
	if ! { curl -fsSL https://cursor.com/install | bash; } >"$cursor_tmp" 2>&1; then
		echo "  Error during Cursor CLI install:" >&2
		cat "$cursor_tmp" >&2
		rm -f "$cursor_tmp"
		return 1
	fi
	rm -f "$cursor_tmp"
	if [[ -x "$HOME/.local/bin/agent" ]]; then
		mkdir -p "$HOME/bin"
		ln -sf "$HOME/.local/bin/agent" "$HOME/bin/agent"
	fi
	log_ok "Cursor CLI installed"
}

install_codex_cli() {
	if command -v codex >/dev/null 2>&1; then
		log_skip "Codex CLI already installed"
		return 0
	fi
	command -v npm >/dev/null 2>&1 || {
		echo "  npm not found. Install Node.js first." >&2
		return 1
	}
	log_step "Install Codex CLI"
	npm i -g @openai/codex
	log_ok "Codex CLI installed"
}

install_claude_cli() {
	if command -v claude >/dev/null 2>&1; then
		log_skip "Claude CLI already installed"
		return 0
	fi
	log_step "Install Claude CLI"
	local claude_tmp
	claude_tmp="$(mktemp)"
	if ! { curl -fsSL https://claude.ai/install.sh | bash; } >"$claude_tmp" 2>&1; then
		echo "  Error during Claude CLI install:" >&2
		cat "$claude_tmp" >&2
		rm -f "$claude_tmp"
		return 1
	fi
	rm -f "$claude_tmp"
	log_ok "Claude CLI installed"
}

install_copilot_cli() {
	if command -v copilot >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/copilot" ]]; then
		log_skip "Copilot CLI already installed"
		return 0
	fi
	log_step "Install Copilot CLI"
	local copilot_tmp
	copilot_tmp="$(mktemp)"
	if ! { curl -fsSL https://gh.io/copilot-install | PREFIX="$HOME/.local" PATH="$HOME/.local/bin:$PATH" bash; } >"$copilot_tmp" 2>&1; then
		echo "  Error during Copilot CLI install:" >&2
		cat "$copilot_tmp" >&2
		rm -f "$copilot_tmp"
		return 1
	fi
	rm -f "$copilot_tmp"

	if [[ -x "$HOME/.local/bin/copilot" ]]; then
		mkdir -p "$HOME/bin"
		ln -sf "$HOME/.local/bin/copilot" "$HOME/bin/copilot"
	fi

	log_ok "Copilot CLI installed"
}

install_powershell() {
	if command -v pwsh >/dev/null 2>&1; then
		log_skip "PowerShell already installed ($(pwsh --version 2>/dev/null || echo 'unknown'))"
		return 0
	fi

	if [[ ! -f /etc/os-release ]]; then
		echo "  Could not detect OS version (/etc/os-release missing)." >&2
		return 1
	fi

	# shellcheck disable=SC1091
	. /etc/os-release

	local distro="${ID:-}" version_id="${VERSION_ID:-}"
	case "$distro" in
	ubuntu | debian) ;;
	*)
		echo "  PowerShell install supports Ubuntu/Debian only (detected: ${distro:-unknown})." >&2
		return 1
		;;
	esac

	if [[ -z "$version_id" ]]; then
		echo "  Could not determine VERSION_ID from /etc/os-release." >&2
		return 1
	fi

	log_step "Install PowerShell from Microsoft packages repo"
	sudo apt-get update -qq
	# HTTPS transport is built into supported modern apt releases; the legacy
	# apt-transport-https package is unnecessary and may not exist on newer systems.
	sudo apt-get -o Dpkg::Use-Pty=0 install -y wget software-properties-common

	if [[ ! -f /etc/apt/sources.list.d/microsoft-prod.list && ! -f /etc/apt/sources.list.d/microsoft-prod.sources ]]; then
		local deb_file
		deb_file="$(mktemp /tmp/packages-microsoft-prod.XXXXXX.deb)"
		wget -q "https://packages.microsoft.com/config/${distro}/${version_id}/packages-microsoft-prod.deb" -O "$deb_file"
		sudo dpkg -i "$deb_file"
		rm -f "$deb_file"
		log_ok "Added Microsoft apt repository"
	else
		log_skip "Microsoft apt repository already configured"
	fi

	sudo apt-get update -qq
	sudo apt-get -o Dpkg::Use-Pty=0 install -y powershell

	if command -v pwsh >/dev/null 2>&1; then
		log_ok "PowerShell installed ($(pwsh --version 2>/dev/null || echo 'unknown'))"
	else
		echo "  PowerShell package installed but 'pwsh' was not found on PATH." >&2
		return 1
	fi
}

install_direnv() {
	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for direnv install." >&2
		return 1
	}

	log_step "Install/update direnv"
	mkdir -p "$HOME/.local/bin"
	local direnv_tmp
	direnv_tmp="$(mktemp)"
	if ! { bin_path="$HOME/.local/bin" curl -sfL https://direnv.net/install.sh | bash; } >"$direnv_tmp" 2>&1; then
		echo "  Error during direnv install:" >&2
		cat "$direnv_tmp" >&2
		rm -f "$direnv_tmp"
		return 1
	fi
	rm -f "$direnv_tmp"

	if [[ -x "$HOME/.local/bin/direnv" ]]; then
		mkdir -p "$HOME/bin"
		ln -sf "$HOME/.local/bin/direnv" "$HOME/bin/direnv"
	fi

	if command -v direnv >/dev/null 2>&1; then
		log_ok "direnv installed: $(direnv version)"
	else
		log_warn "direnv installed to ~/.local/bin but is not on PATH yet"
	fi
}

ensure_direnv_hook_in_bashrc() {
	log_skip "direnv hook lives in stowed .bashrc"
}

ensure_wslview_browser_in_bashrc() {
	log_skip "BROWSER=wslview lives in stowed .bashrc"
}
