#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------
# WSL/Debian/Ubuntu interactive bootstrap
# - Prompts for git identity
# - Toggle menu to select components
# - Shows execution plan for review
# - Installs only selected components
# --------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"
# When run from scripts/install.sh, repo root is parent directory.
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" ]]; then
	DOTFILES_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
fi
PKG_FILE="$DOTFILES_DIR/packages/packages.txt"

# Capture before logging redirect — exec > >(tee) makes stdout non-TTY.
DOTFILES_INTERACTIVE_TTY=false
if [[ -t 0 ]]; then
	DOTFILES_INTERACTIVE_TTY=true
fi

_clean_log_stream() {
	perl -pe '
		s/\r/\n/g;
		s/\e\[[0-9;?]*[ -\/]*[@-~]//g;
		s/\e\][^\a]*(?:\a|\e\\)//g;
	' | sed -u 's/[[:space:]]*$//'
}

# --- Logging: mirror all output to a timestamped log file ---
LOG_DIR="$DOTFILES_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d_%H-%M-%S').log"
RAW_LOG_FILE="${LOG_FILE}.raw"

finalize_log_file() {
	[[ -f "$RAW_LOG_FILE" ]] || return 0
	_clean_log_stream <"$RAW_LOG_FILE" >"$LOG_FILE"
	rm -f "$RAW_LOG_FILE"
}

trap finalize_log_file EXIT
exec > >(tee -a "$RAW_LOG_FILE") 2>&1

# shellcheck source=scripts/lib/load.sh
source "$DOTFILES_DIR/scripts/lib/load.sh"
# shellcheck source=scripts/menus/helpers.sh
source "$DOTFILES_DIR/scripts/menus/helpers.sh"
# shellcheck source=scripts/menus/main.sh
source "$DOTFILES_DIR/scripts/menus/main.sh"
# shellcheck source=scripts/menus/initial_setup.sh
source "$DOTFILES_DIR/scripts/menus/initial_setup.sh"
# shellcheck source=scripts/menus/update.sh
source "$DOTFILES_DIR/scripts/menus/update.sh"
# shellcheck source=scripts/menus/extensions.sh
source "$DOTFILES_DIR/scripts/menus/extensions.sh"
# shellcheck source=scripts/menus/agents.sh
source "$DOTFILES_DIR/scripts/menus/agents.sh"

# ============================================================
# Component registry
# ============================================================
COMP_KEYS=(
	git_identity
	system_packages
	python
	powershell
	go
	nodejs
	direnv
	docker
	portainer
	lazygit
	lazydocker
	cursor_cli
	codex_cli
	claude_cli
	copilot_cli
	monaspace_fonts
	ssh_key
	dotfiles
	wsl_conf
	git_credential
)

COMP_LABELS=(
	"Git identity (global user.name / email)"
	"System packages"
	"Python (python3, pip, venv)"
	"PowerShell (pwsh)"
	"Go (asdf)"
	"Node.js 24 LTS (nvm)"
	"direnv (env loader + shell hook)"
	"Docker Engine"
	"Portainer CE"
	"lazygit (git TUI)"
	"lazydocker (docker TUI)"
	"Cursor CLI"
	"Codex CLI"
	"Claude CLI"
	"Copilot CLI"
	"Monaspace fonts (Nerd Fonts)"
	"Generate SSH key"
	"Apply dotfiles (stow)"
	"WSL config (systemd, appendWindowsPath)"
	"Git credential helper (Windows)"
)

# Dependency: index of required component, -1 = none
#              gid sys py  psh go  njs dir doc por lg  ld  cur cdx cla cop mon ssh dot wsl gcr
COMP_DEPS=(-1 -1 -1 -1 -1 -1 -1 -1 7 -1 7 -1 5 -1 -1 -1 -1 1 -1 -1)

declare -A COMP_ON
for _key in "${COMP_KEYS[@]}"; do COMP_ON["$_key"]=1; done

# Auto-detect conditional git includes (multi-identity setup) and default OFF
if git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
	COMP_ON[git_identity]=0
fi

# Git identity (populated by prompt)
SETUP_GIT_NAME=""
SETUP_GIT_EMAIL=""

# Status message from toggle_component (avoids echo which breaks in-place redraw)
TOGGLE_MSG=""

# ============================================================
# packages.txt parser
# ============================================================

read_packages_by_tags() {
	# Usage: read_packages_by_tags tag1 tag2 ...
	# Outputs package names under matching @tag sections.
	[[ -f "$PKG_FILE" ]] || {
		echo "Error: $PKG_FILE not found" >&2
		return 1
	}

	local -A wanted
	local tag
	for tag in "$@"; do wanted["$tag"]=1; done

	local current_tag="" active=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^#[[:space:]]*@([a-zA-Z_]+) ]]; then
			current_tag="${BASH_REMATCH[1]}"
			[[ -n "${wanted[$current_tag]+_}" ]] && active=1 || active=0
			continue
		fi
		[[ "$active" -eq 0 ]] && continue
		local pkg="${line%%#*}"
		pkg="${pkg#"${pkg%%[![:space:]]*}"}"
		pkg="${pkg%"${pkg##*[![:space:]]}"}"
		[[ -n "$pkg" ]] && echo "$pkg"
	done <"$PKG_FILE"
}

# ============================================================
# Interactive UI
# ============================================================

is_on() { [[ "${COMP_ON[$1]}" -eq 1 ]]; }

prompt_git_identity() {
	local current_name current_email
	current_name="$(git config --global user.name 2>/dev/null || true)"
	current_email="$(git config --global user.email 2>/dev/null || true)"

	echo ""
	echo "Git identity (press Enter to keep default):"
	read_tty_line SETUP_GIT_NAME "  Name [${current_name:-}]: "
	SETUP_GIT_NAME="${SETUP_GIT_NAME:-$current_name}"

	read_tty_line SETUP_GIT_EMAIL "  Email [${current_email:-}]: "
	SETUP_GIT_EMAIL="${SETUP_GIT_EMAIL:-$current_email}"
}

toggle_component() {
	local idx="$1"
	local key="${COMP_KEYS[$idx]}"
	TOGGLE_MSG=""

	if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
		COMP_ON["$key"]=0
		local i
		for i in "${!COMP_DEPS[@]}"; do
			if [[ "${COMP_DEPS[$i]}" -eq "$idx" ]]; then
				local dep_key="${COMP_KEYS[$i]}"
				if [[ "${COMP_ON[$dep_key]}" -eq 1 ]]; then
					COMP_ON["$dep_key"]=0
					TOGGLE_MSG+="auto-disabled: ${COMP_LABELS[$i]}  "
				fi
			fi
		done
	else
		COMP_ON["$key"]=1
		local req="${COMP_DEPS[$idx]}"
		if [[ "$req" -ne -1 ]]; then
			local req_key="${COMP_KEYS[$req]}"
			if [[ "${COMP_ON[$req_key]}" -eq 0 ]]; then
				COMP_ON["$req_key"]=1
				TOGGLE_MSG+="auto-enabled: ${COMP_LABELS[$req]}"
			fi
		fi
	fi
}

_comp_description() {
	local idx=$1
	case "${COMP_KEYS[$idx]}" in
	git_identity)
		echo "Set global git user.name and user.email."
		echo "Skip this if you use includeIf for per-directory identities."
		;;
	system_packages)
		local pkgs
		pkgs="$(read_packages_by_tags core cli system | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
		echo "Installs via apt: ${pkgs}"
		;;
	python)
		echo "Installs python3, pip, and venv via apt."
		;;
	powershell)
		echo "Installs Microsoft PowerShell from packages.microsoft.com."
		echo "Adds the Microsoft apt repository if missing, then installs 'powershell'."
		;;
	go)
		echo "Installs latest Go via asdf and sets it global."
		;;
	nodejs)
		echo "Installs Node.js v24 via nvm (Node Version Manager)."
		echo "Also provides npm for global packages like Codex CLI."
		;;
	direnv)
		echo "Installs or updates direnv to ~/.local/bin via official installer."
		echo "Adds 'eval \"\$(direnv hook bash)\"' to ~/.bashrc if missing."
		;;
	docker)
		echo "Installs Docker Engine CE from the official Docker apt repo."
		echo "Adds your user to the docker group for rootless access."
		;;
	portainer)
		echo "Deploys the Portainer CE container (web UI for Docker)."
		echo "Container is stopped by default — start with 'dpot'."
		;;
	lazygit)
		echo "Terminal UI for git. Downloaded from GitHub releases."
		;;
	lazydocker)
		echo "Terminal UI for Docker. Downloaded from GitHub releases."
		;;
	cursor_cli)
		echo "Installs Cursor editor CLI from cursor.com."
		echo "Update later with 'update-cursor' or 'update-all'."
		;;
	codex_cli)
		echo "Installs OpenAI Codex CLI via npm (requires Node.js)."
		echo "Update later with 'update-codex' or 'update-all'."
		;;
	claude_cli)
		echo "Installs Anthropic Claude CLI from claude.ai."
		echo "Update later with 'update-claude' or 'update-all'."
		;;
	copilot_cli)
		echo "Installs GitHub Copilot CLI via the official installer script."
		echo "Runs: curl -fsSL https://gh.io/copilot-install | bash"
		;;
	monaspace_fonts)
		echo "Downloads GitHub Monaspace Nerd Fonts to ~/.local/share/fonts/."
		echo "Includes all 5 variants with Powerline glyphs and dev icons."
		;;
	ssh_key)
		echo "Generates an ed25519 SSH key and adds it to ssh-agent."
		echo "Saves public key and GitHub setup steps to ~/.ssh/github-setup.txt."
		;;
	dotfiles)
		echo "Uses GNU Stow to symlink bash, bin, and readline configs into \$HOME."
		echo "Backs up existing .bashrc, .bash_aliases, .inputrc first."
		;;
	wsl_conf)
		echo "Sets systemd=true and appendWindowsPath=true in /etc/wsl.conf."
		echo "Requires 'wsl --shutdown' from Windows to take effect."
		;;
	git_credential)
		echo "Configures git to use Windows Git Credential Manager for HTTPS auth."
		echo "Searches common install paths for git-credential-manager.exe."
		;;
	esac
}

_COMP_DESC_LINES=2

_component_menu_page_size() {
	local rows="$1"
	local page_size=$((rows - 7))
	((page_size < 1)) && page_size=1
	echo "$page_size"
}

_component_menu_page_for_cursor() {
	local cursor="$1"
	local page_size="$2"
	echo $((cursor / page_size))
}

_component_menu_page_count() {
	local count="$1"
	local page_size="$2"
	echo $(((count + page_size - 1) / page_size))
}

_component_menu_page_range() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local start=$((page * page_size))
	local end=$((start + page_size - 1))

	((end >= count)) && end=$((count - 1))
	echo "$start $end"
}

_component_menu_visible_count() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local start end

	read -r start end < <(_component_menu_page_range "$count" "$page_size" "$page")
	echo $((end - start + 1))
}

_component_menu_render_lines() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local visible_count

	visible_count="$(_component_menu_visible_count "$count" "$page_size" "$page")"
	echo $((visible_count + 7))
}

_component_menu_description_line() {
	local idx="$1"
	local line_index="$2"
	local line=""
	local lines=()

	mapfile -t lines < <(_comp_description "$idx")
	if ((line_index < ${#lines[@]})); then
		line="${lines[$line_index]}"
	fi
	echo "$line"
}

_draw_component_menu() {
	local cur=$1
	local page_size=$2
	local status=$3
	local cols=$4
	local count="${#COMP_KEYS[@]}"
	local page total_pages start end
	local i key mark note row

	page="$(_component_menu_page_for_cursor "$cur" "$page_size")"
	total_pages="$(_component_menu_page_count "$count" "$page_size")"
	read -r start end < <(_component_menu_page_range "$count" "$page_size" "$page")

	ui_print_header "Select Components" "" "$cols"
	printf '  %s%s%s\e[K\n' "$C_DIM" "$(_fit_menu_line_with_indent "Up/Down navigate   Space toggle   a all   n none   Enter confirm   q back" "$cols" 2)" "$C_RESET"
	printf '  %s%s%s\e[K\n\n' "$C_DIM" "$(_fit_menu_line_with_indent "Page $((page + 1))/$total_pages   Showing $((start + 1))-$((end + 1)) of $count" "$cols" 2)" "$C_RESET"

	for ((i = start; i <= end; i++)); do
		key="${COMP_KEYS[$i]}"
		mark="x"
		[[ "${COMP_ON[$key]}" -eq 0 ]] && mark=" "
		note=""
		[[ "${COMP_DEPS[$i]}" -ne -1 ]] && note="  (requires #$((COMP_DEPS[i] + 1)))"
		row="$(printf " %2d. [%s] %s%s" "$((i + 1))" "$mark" "${COMP_LABELS[$i]}" "$note")"

		if [[ $i -eq $cur ]]; then
			printf '  %s>%s ' "$C_BOLD" "$C_RESET"
			if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
				printf '%s\e[K\n' "$(_fit_menu_line "$row" "$((cols - 4))")"
			else
				printf '%s%s%s\e[K\n' "$C_DIM" "$(_fit_menu_line "$row" "$((cols - 4))")" "$C_RESET"
			fi
		else
			if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
				printf '  %s\e[K\n' "$(_fit_menu_line "$row" "$((cols - 2))")"
			else
				printf '  %s%s%s\e[K\n' "$C_DIM" "$(_fit_menu_line "$row" "$((cols - 2))")" "$C_RESET"
			fi
		fi
	done

	if [[ -n "$status" ]]; then
		printf '  %s%s%s\e[K\n' "$C_YELLOW" "$(_fit_menu_line_with_indent "$status" "$cols" 2)" "$C_RESET"
	else
		printf '\e[K\n'
	fi

	local desc_idx
	for ((desc_idx = 0; desc_idx < _COMP_DESC_LINES; desc_idx++)); do
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(_fit_menu_line_with_indent "$(_component_menu_description_line "$cur" "$desc_idx")" "$cols" 2)" "$C_RESET"
	done
}

component_menu() {
	local count="${#COMP_KEYS[@]}"
	local cursor=0
	local status_msg=""
	local rows cols page_size menu_lines action page
	local cancelled=false
	local prev_page=-1 prev_lines=0

	rows="$(_menu_tty_rows)"
	cols="$(_menu_tty_cols)"
	page_size="$(_component_menu_page_size "$rows")"
	page="$(_component_menu_page_for_cursor "$cursor" "$page_size")"
	menu_lines="$(_component_menu_render_lines "$count" "$page_size" "$page")"

	{
		tput civis 2>/dev/null || true
		_menu_clear_screen
		_draw_component_menu "$cursor" "$page_size" "" "$cols"
		prev_page="$page"
		prev_lines="$menu_lines"

		while true; do
			action="$(_read_component_menu_key)"

			case "$action" in
			up)
				[[ $cursor -gt 0 ]] && cursor=$((cursor - 1))
				status_msg=""
				;;
			down)
				[[ $cursor -lt $((count - 1)) ]] && cursor=$((cursor + 1))
				status_msg=""
				;;
			toggle)
				toggle_component "$cursor"
				status_msg="$TOGGLE_MSG"
				;;
			confirm)
				break
				;;
			cancel)
				cancelled=true
				break
				;;
			all)
				for k in "${COMP_KEYS[@]}"; do COMP_ON["$k"]=1; done
				status_msg="All components enabled"
				;;
			none)
				for k in "${COMP_KEYS[@]}"; do COMP_ON["$k"]=0; done
				status_msg="All components disabled"
				;;
			ignore)
				continue
				;;
			esac

			prev_page="$page"
			prev_lines="$menu_lines"
			page="$(_component_menu_page_for_cursor "$cursor" "$page_size")"
			menu_lines="$(_component_menu_render_lines "$count" "$page_size" "$page")"
			menu_redraw_prepare "$prev_lines" "$menu_lines" "$prev_page" "$page"
			_draw_component_menu "$cursor" "$page_size" "$status_msg" "$cols"
		done
		tput cnorm 2>/dev/null || true
	} >/dev/tty

	[[ "$cancelled" == true ]] && return 1
	return 0
}

show_plan() {
	local cols pkg_count
	cols="$(menu_tty_cols)"

	{
		ui_clear
		ui_print_header "Execution Plan" "" "$cols"
		printf '\n'

		if is_on git_identity; then
			ui_print_plan_row "Git identity" "$SETUP_GIT_NAME <$SETUP_GIT_EMAIL>" 1
		elif git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
			ui_print_plan_row "Git identity" "skip (conditional includes detected)" 0
		else
			ui_print_plan_row "Git identity" "skip" 0
		fi

		if is_on system_packages; then
			pkg_count="$(read_packages_by_tags core cli system | wc -l)"
			ui_print_plan_row "System packages" "${pkg_count} packages (@core @cli @system)" 1
		else
			ui_print_plan_row "System packages" "skip" 0
		fi

		is_on python \
			&& ui_print_plan_row "Python" "python3, pip, venv" 1 \
			|| ui_print_plan_row "Python" "skip" 0

		is_on powershell \
			&& ui_print_plan_row "PowerShell" "Microsoft repo + powershell" 1 \
			|| ui_print_plan_row "PowerShell" "skip" 0

		is_on go \
			&& ui_print_plan_row "Go" "asdf golang latest" 1 \
			|| ui_print_plan_row "Go" "skip" 0

		is_on nodejs \
			&& ui_print_plan_row "Node.js" "v24 via nvm" 1 \
			|| ui_print_plan_row "Node.js" "skip" 0

		is_on direnv \
			&& ui_print_plan_row "direnv" "install/update + bash hook" 1 \
			|| ui_print_plan_row "direnv" "skip" 0

		is_on docker \
			&& ui_print_plan_row "Docker" "Docker Engine CE + docker group" 1 \
			|| ui_print_plan_row "Docker" "skip" 0

		is_on portainer \
			&& ui_print_plan_row "Portainer" "Portainer CE (stopped by default)" 1 \
			|| ui_print_plan_row "Portainer" "skip" 0

		is_on lazygit \
			&& ui_print_plan_row "lazygit" "latest from GitHub" 1 \
			|| ui_print_plan_row "lazygit" "skip" 0

		is_on lazydocker \
			&& ui_print_plan_row "lazydocker" "latest from GitHub" 1 \
			|| ui_print_plan_row "lazydocker" "skip" 0

		is_on cursor_cli \
			&& ui_print_plan_row "Cursor CLI" "cursor.com installer" 1 \
			|| ui_print_plan_row "Cursor CLI" "skip" 0

		is_on codex_cli \
			&& ui_print_plan_row "Codex CLI" "npm @openai/codex" 1 \
			|| ui_print_plan_row "Codex CLI" "skip" 0

		is_on claude_cli \
			&& ui_print_plan_row "Claude CLI" "claude.ai installer" 1 \
			|| ui_print_plan_row "Claude CLI" "skip" 0

		is_on copilot_cli \
			&& ui_print_plan_row "Copilot CLI" "gh.io/copilot-install" 1 \
			|| ui_print_plan_row "Copilot CLI" "skip" 0

		is_on monaspace_fonts \
			&& ui_print_plan_row "Monaspace fonts" "Monaspace Nerd Fonts -> ~/.local/share/fonts/" 1 \
			|| ui_print_plan_row "Monaspace fonts" "skip" 0

		if is_on ssh_key; then
			if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
				ui_print_plan_row "SSH key" "already exists, will skip" 1
			else
				ui_print_plan_row "SSH key" "generate ed25519 -> ~/.ssh/github-setup.txt" 1
			fi
		else
			ui_print_plan_row "SSH key" "skip" 0
		fi

		is_on dotfiles \
			&& ui_print_plan_row "Dotfiles" "stow bash, bin, readline" 1 \
			|| ui_print_plan_row "Dotfiles" "skip" 0

		is_on wsl_conf \
			&& ui_print_plan_row "WSL config" "systemd=true, appendWindowsPath=true" 1 \
			|| ui_print_plan_row "WSL config" "skip" 0

		is_on git_credential \
			&& ui_print_plan_row "Git credential" "Windows Credential Manager" 1 \
			|| ui_print_plan_row "Git credential" "skip" 0

		printf '\n'
	} >/dev/tty
}

# confirm_loop and run_initial_setup_flow live in scripts/menus/initial_setup.sh

# ============================================================
# Installer functions
# ============================================================

_run_quiet_command() {
	local label="$1"
	shift

	local tmp
	tmp="$(mktemp)"

	if "$@" >"$tmp" 2>&1; then
		rm -f "$tmp"
		return 0
	fi

	echo "  Error during ${label}:" >&2
	cat "$tmp" >&2
	rm -f "$tmp"
	return 1
}

_log_prefix() {
	local level="$1"
	local message="$2"
	printf '[%s] %s\n' "$level" "$message"
}

_log_legend_line() {
	printf '%s\n' '[Legend] STEP=starting  OK=completed  SKIP=already satisfied  WARN=needs attention'
}

log_step() { _log_prefix STEP "$1"; }
log_ok() { _log_prefix OK "$1"; }
log_skip() { _log_prefix SKIP "$1"; }
log_warn() { _log_prefix WARN "$1"; }

apt_install_packages() {
	local pkgs
	mapfile -t pkgs < <(read_packages_by_tags "$@")
	if [[ ${#pkgs[@]} -eq 0 ]]; then
		log_skip "No packages for tags: $*"
		return 0
	fi
	log_step "Install apt packages: $*"
	if _run_quiet_command "apt packages ($*)" sudo apt-get -qq -o Dpkg::Use-Pty=0 install -y "${pkgs[@]}"; then
		log_ok "Apt packages installed: $*"
	else
		log_warn "Apt package install failed: $*"
	fi
}

install_lazygit_from_github() {
	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for lazygit install." >&2
		return 1
	}
	command -v tar >/dev/null 2>&1 || {
		echo "  tar required for lazygit install." >&2
		return 1
	}

	log_step "Install lazygit from GitHub releases"
	local ver tmp
	ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
		grep -Po '"tag_name":\s*"v\K[^"]*' | head -n1)"
	[[ -n "$ver" ]] || {
		echo "  Could not determine lazygit version." >&2
		return 1
	}

	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' RETURN
	local tarball="lazygit_${ver}_Linux_x86_64.tar.gz"
	curl -fsSL -o "$tmp/$tarball" \
		"https://github.com/jesseduffield/lazygit/releases/download/v${ver}/${tarball}"
	curl -fsSL -o "$tmp/checksums.txt" \
		"https://github.com/jesseduffield/lazygit/releases/download/v${ver}/checksums.txt"
	if ! (cd "$tmp" && sha256sum --check --ignore-missing checksums.txt); then
		echo "  lazygit checksum verification failed." >&2
		return 1
	fi
	tar -C "$tmp" -xzf "$tmp/$tarball" lazygit
	sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
	rm -rf "$tmp"
	trap - RETURN
	log_ok "lazygit v${ver} installed"
}

install_lazydocker_from_github() {
	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for lazydocker install." >&2
		return 1
	}
	command -v tar >/dev/null 2>&1 || {
		echo "  tar required for lazydocker install." >&2
		return 1
	}

	log_step "Install lazydocker from GitHub releases"
	local ver tmp
	ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest |
		grep -Po '"tag_name":\s*"v\K[^"]*' | head -n1)"
	[[ -n "$ver" ]] || {
		echo "  Could not determine lazydocker version." >&2
		return 1
	}

	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' RETURN
	local tarball="lazydocker_${ver}_Linux_x86_64.tar.gz"
	curl -fsSL -o "$tmp/$tarball" \
		"https://github.com/jesseduffield/lazydocker/releases/download/v${ver}/${tarball}"
	curl -fsSL -o "$tmp/checksums.txt" \
		"https://github.com/jesseduffield/lazydocker/releases/download/v${ver}/checksums.txt"
	if ! (cd "$tmp" && sha256sum --check --ignore-missing checksums.txt); then
		echo "  lazydocker checksum verification failed." >&2
		return 1
	fi
	tar -C "$tmp" -xzf "$tmp/$tarball"

	if [[ ! -f "$tmp/lazydocker" ]]; then
		local binpath
		binpath="$(find "$tmp" -maxdepth 3 -type f -name lazydocker | head -n1 || true)"
		[[ -n "$binpath" ]] && cp "$binpath" "$tmp/lazydocker"
	fi

	sudo install -m 0755 "$tmp/lazydocker" /usr/local/bin/lazydocker
	rm -rf "$tmp"
	trap - RETURN
	log_ok "lazydocker v${ver} installed"
}

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
		# Legacy asdf installs ship a Bash script in bin/asdf; replace with modern binary.
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
		local tag tmp tarball_url extracted
		tag="$(curl -fsSL https://api.github.com/repos/asdf-vm/asdf/releases/latest | grep -Po '"tag_name":\s*"\K[^"]+' | head -n1)"
		[[ -n "$tag" ]] || {
			echo "  Could not determine latest asdf release." >&2
			return 1
		}

		tarball_url="https://github.com/asdf-vm/asdf/releases/download/${tag}/asdf-${tag}-linux-${arch}.tar.gz"
		tmp="$(mktemp -d)"
		trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
		if ! curl -fsSL -o "$tmp/asdf.tar.gz" "$tarball_url"; then
			echo "  Failed to download asdf. Check TLS trust in WSL or retry after fixing CA certificates." >&2
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

# Run docker with sudo fallback if user isn't in the docker group yet
run_docker() {
	if groups 2>/dev/null | grep -qw docker; then
		command docker "$@"
	else
		sudo docker "$@"
	fi
}

configure_docker_daemon() {
	local daemon_json="/etc/docker/daemon.json"
	local tmp_file backup_file

	tmp_file="$(mktemp)"
	cat >"$tmp_file" <<'EOF'
{
	"storage-driver": "overlay2",
	"log-driver": "json-file",
	"log-opts": {
		"max-size": "10m",
		"max-file": "3"
	}
}
EOF

	sudo install -d -m 0755 /etc/docker

	if sudo test -f "$daemon_json" && sudo cmp -s "$tmp_file" "$daemon_json"; then
		log_skip "Docker daemon config already set in /etc/docker/daemon.json"
		rm -f "$tmp_file"
		return 0
	fi

	if sudo test -f "$daemon_json"; then
		backup_file="/etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)"
		sudo cp "$daemon_json" "$backup_file"
		log_step "Backed up existing Docker daemon config to $backup_file"
	fi

	sudo install -m 0644 "$tmp_file" "$daemon_json"
	rm -f "$tmp_file"
	log_ok "Docker daemon config written to /etc/docker/daemon.json"
}

restart_docker_service() {
	if command -v systemctl >/dev/null 2>&1 && sudo systemctl status docker >/dev/null 2>&1; then
		log_step "Restart Docker service (systemctl)"
		sudo systemctl restart docker
		return 0
	fi

	if command -v service >/dev/null 2>&1; then
		log_step "Restart Docker service (service)"
		sudo service docker restart
		return 0
	fi

	log_warn "Could not determine how to restart Docker service"
	return 1
}

verify_docker_storage_driver() {
	local driver
	driver="$(run_docker info --format '{{.Driver}}' 2>/dev/null || true)"

	if [[ -z "$driver" ]]; then
		driver="$(run_docker info 2>/dev/null | awk -F': ' '/^ Storage Driver:/ {print $2; exit}' || true)"
	fi

	if [[ "$driver" == "overlay2" ]]; then
		log_ok "Docker storage driver verified: overlay2"
		return 0
	fi

	if [[ -n "$driver" ]]; then
		log_warn "Docker storage driver is '$driver' (expected: overlay2)"
	else
		log_warn "Unable to determine Docker storage driver"
	fi

	return 1
}

install_docker() {
	if command -v docker >/dev/null 2>&1; then
		log_skip "Docker already installed ($(docker --version 2>/dev/null || echo 'unknown'))"
	else
		log_step "Install Docker Engine from official repo"
		sudo apt-get -o Dpkg::Use-Pty=0 install -y ca-certificates curl
		sudo install -m 0755 -d /etc/apt/keyrings
		sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
		sudo chmod a+r /etc/apt/keyrings/docker.asc

		local codename
		# shellcheck disable=SC1091
		codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
		sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<DOCKEREOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKEREOF

		sudo apt-get update -qq
		sudo apt-get -o Dpkg::Use-Pty=0 install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
		log_ok "Docker Engine installed"
	fi

	if ! groups "$USER" | grep -qw docker; then
		sudo groupadd -f docker
		sudo usermod -aG docker "$USER"
		log_ok "Added $USER to docker group (log out/in or 'newgrp docker' to activate)"
	fi

	configure_docker_daemon
	if ! restart_docker_service; then
		log_warn "Docker restart failed after daemon config update"
	fi
	if ! verify_docker_storage_driver; then
		log_warn "Please check: docker info | grep \"Storage Driver\""
	fi
}

install_portainer() {
	if run_docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qw portainer; then
		log_skip "Portainer container already exists"
		return 0
	fi

	log_step "Install Portainer CE"
	run_docker volume create portainer_data
	run_docker run -d \
		-p 8000:8000 \
		-p 9443:9443 \
		--name portainer \
		--restart unless-stopped \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v portainer_data:/data \
		portainer/portainer-ce:latest
	run_docker stop portainer
	log_ok "Portainer installed (stopped — use 'dpot' to start, 'dpotstop' to stop)"
}

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
	echo "  You'll be prompted for a passphrase (press Enter to skip / use no passphrase)."
	ssh-keygen -t ed25519 -C "$SETUP_GIT_EMAIL" -f "$HOME/.ssh/id_ed25519"
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
	if command -v copilot >/dev/null 2>&1 ||
		[[ -x "$HOME/.local/bin/copilot" ]] ||
		(command -v gh >/dev/null 2>&1 && gh copilot --help >/dev/null 2>&1); then
		log_skip "Copilot CLI already installed"
		return 0
	fi
	log_step "Install Copilot CLI"
	local copilot_tmp
	copilot_tmp="$(mktemp)"
	# Force install location and PATH so upstream installer does not prompt on /dev/tty.
	if ! { curl -fsSL https://gh.io/copilot-install | PREFIX="$HOME/.local" PATH="$HOME/.local/bin:$PATH" bash; } >"$copilot_tmp" 2>&1; then
		echo "  Error during Copilot CLI install:" >&2
		cat "$copilot_tmp" >&2
		rm -f "$copilot_tmp"
		return 1
	fi
	rm -f "$copilot_tmp"

	# Keep Copilot reachable in shells where ~/.local/bin is not yet on PATH.
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
	sudo apt-get -o Dpkg::Use-Pty=0 install -y wget apt-transport-https software-properties-common

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

	# Keep direnv reachable even in shells where ~/.local/bin is not on PATH.
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

install_monaspace_fonts() {
	local font_dir="$HOME/.local/share/fonts/monaspace"

	if [[ -d "$font_dir" ]] && compgen -G "$font_dir/*.otf" >/dev/null 2>&1; then
		log_skip "Monaspace fonts already installed in $font_dir"
		return 0
	fi

	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for Monaspace install." >&2
		return 1
	}
	command -v unzip >/dev/null 2>&1 || sudo apt-get -o Dpkg::Use-Pty=0 install -y unzip

	log_step "Install Monaspace Nerd Fonts from GitHub"
	local ver tmp
	ver="$(curl -fsSL https://api.github.com/repos/githubnext/monaspace/releases/latest |
		grep -Po '"tag_name":\s*"\K[^"]*' | head -n1)"
	[[ -n "$ver" ]] || {
		echo "  Could not determine Monaspace version." >&2
		return 1
	}

	tmp="$(mktemp -d)"
	trap "rm -rf '${tmp}'" RETURN
	if ! curl -fsSL -o "$tmp/monaspace-nerdfonts.zip" \
		"https://github.com/githubnext/monaspace/releases/download/${ver}/monaspace-nerdfonts-${ver}.zip"; then
		echo "  Monaspace download failed." >&2
		return 1
	fi
	if ! unzip -qo "$tmp/monaspace-nerdfonts.zip" -d "$tmp/monaspace"; then
		echo "  Monaspace unzip failed." >&2
		return 1
	fi

	local extracted_path
	while IFS= read -r -d '' extracted_path; do
		if [[ "$extracted_path" == *".."* ]]; then
			echo "  Rejected suspicious path in Monaspace archive." >&2
			return 1
		fi
	done < <(find "$tmp/monaspace" -print0)

	mkdir -p "$font_dir"
	local otf_count=0
	while IFS= read -r -d '' otf; do
		cp "$otf" "$font_dir/"
		otf_count=$((otf_count + 1))
	done < <(find "$tmp/monaspace" -name '*.otf' -print0)
	if [[ $otf_count -eq 0 ]]; then
		echo "  No .otf files found in Monaspace archive." >&2
		return 1
	fi

	fc-cache -f 2>/dev/null || true

	local count
	count="$(find "$font_dir" -name '*.otf' | wc -l)"
	rm -rf "$tmp"
	trap - RETURN
	log_ok "Monaspace Nerd Fonts ${ver} installed (${count} fonts in ${font_dir})"
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

# ============================================================
# Menus — scripts/menus/*.sh (sourced after logging setup)
# ============================================================

print_usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --initial     Open initial setup submenu (or run setup non-interactively)
  --update      Open update submenu
  --extensions  Open IDE extensions submenu
  --agents      Open agents bootstrap submenu
  --help        Show this help and exit

Without options on an interactive terminal, shows the main menu (loops until Quit).
Non-interactive runs (no TTY stdin, CI, piped) default to initial setup.
EOF
}

_install_short_label() {
	local label="$1"
	label="${label%%(*}"
	label="${label%% }"
	printf '%.22s' "$label"
}

_install_summary_probe() {
	local key="$1"
	local name email ver count gcm font_dir

	case "$key" in
	git_identity)
		name="$(git config --global user.name 2>/dev/null || true)"
		email="$(git config --global user.email 2>/dev/null || true)"
		if [[ -n "$name" && -n "$email" ]]; then
			printf 'configured|%s <%s>' "$name" "$email"
		else
			printf 'skipped|not configured'
		fi
		;;
	system_packages) printf 'installed|apt @core @cli @system\n' ;;
	python) printf 'installed|python3 pip venv\n' ;;
	powershell)
		if command -v pwsh >/dev/null 2>&1; then
			printf 'installed|%s\n' "$(pwsh --version 2>/dev/null | head -n1)"
		else
			printf 'missing|pwsh not on PATH'
		fi
		;;
	go)
		if command -v go >/dev/null 2>&1; then
			ver="$(go version 2>/dev/null | grep -oE 'go[0-9.]+' | head -n1 || true)"
			printf 'installed|%s\n' "${ver:-go}"
		elif command -v asdf >/dev/null 2>&1; then
			ver="$(asdf current golang 2>/dev/null | awk '$1=="golang" {print $2; exit}')"
			printf 'installed|%s\n' "${ver:-asdf golang}"
		else
			printf 'missing|go not on PATH'
		fi
		;;
	nodejs)
		if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
			# shellcheck source=/dev/null
			. "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
		fi
		if command -v node >/dev/null 2>&1; then
			printf 'installed|node %s\n' "$(node --version 2>/dev/null)"
		else
			printf 'missing|node not on PATH'
		fi
		;;
	direnv)
		if command -v direnv >/dev/null 2>&1; then
			printf 'installed|%s\n' "$(direnv version 2>/dev/null | head -n1)"
		else
			printf 'missing|direnv not on PATH'
		fi
		;;
	docker)
		if command -v docker >/dev/null 2>&1; then
			printf 'installed|%s\n' "$(docker --version 2>/dev/null | head -n1)"
		else
			printf 'missing|docker not on PATH'
		fi
		;;
	portainer)
		if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
			printf 'installed|container exists (stopped by default)'
		else
			printf 'missing|portainer container not found'
		fi
		;;
	lazygit)
		if command -v lazygit >/dev/null 2>&1; then
			ver="$(lazygit --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
			printf 'installed|%s\n' "${ver:-lazygit}"
		else
			printf 'missing|lazygit not on PATH'
		fi
		;;
	lazydocker)
		if command -v lazydocker >/dev/null 2>&1; then
			ver="$(lazydocker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
			printf 'installed|%s\n' "${ver:-lazydocker}"
		else
			printf 'missing|lazydocker not on PATH'
		fi
		;;
	cursor_cli)
		if command -v agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1; then
			if command -v agent >/dev/null 2>&1; then
				ver="$(agent --version 2>/dev/null | head -n1 || true)"
			else
				ver="$(cursor --version 2>/dev/null | head -n1 || true)"
			fi
			printf 'installed|%s\n' "${ver:-cursor cli}"
		else
			printf 'missing|cursor/agent not on PATH'
		fi
		;;
	codex_cli)
		if command -v codex >/dev/null 2>&1; then
			printf 'installed|%s\n' "$(codex --version 2>/dev/null | head -n1)"
		else
			printf 'missing|codex not on PATH'
		fi
		;;
	claude_cli)
		if command -v claude >/dev/null 2>&1; then
			printf 'installed|%s\n' "$(claude --version 2>/dev/null | head -n1)"
		else
			printf 'missing|claude not on PATH'
		fi
		;;
	copilot_cli)
		if command -v copilot >/dev/null 2>&1; then
			printf 'installed|%s\n' "$(copilot --version 2>/dev/null | head -n1)"
		elif [[ -x "$HOME/.local/bin/copilot" ]]; then
			printf 'installed|%s\n' "$("$HOME/.local/bin/copilot" --version 2>/dev/null | head -n1)"
		else
			printf 'missing|copilot not on PATH'
		fi
		;;
	monaspace_fonts)
		font_dir="$HOME/.local/share/fonts/monaspace"
		if [[ -d "$font_dir" ]] && compgen -G "${font_dir}/*.otf" >/dev/null 2>&1; then
			count="$(find "$font_dir" -maxdepth 1 -name '*.otf' 2>/dev/null | wc -l | tr -d ' ')"
			ver="installed"
			[[ -f "${font_dir}/.version" ]] && ver="$(cat "${font_dir}/.version")"
			printf 'installed|%s (%s fonts)\n' "$ver" "$count"
		else
			printf 'missing|fonts not in ~/.local/share/fonts/monaspace'
		fi
		;;
	ssh_key)
		if [[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]]; then
			printf 'installed|~/.ssh key present'
		else
			printf 'skipped|no default key found'
		fi
		;;
	dotfiles)
		if [[ -e "$HOME/bin/dotfiles" || -e "$HOME/bin/ex" ]]; then
			printf 'installed|stow bash bin readline'
		else
			printf 'check|~/bin symlinks missing'
		fi
		;;
	wsl_conf)
		if [[ -f /etc/wsl.conf ]] && grep -q '^systemd=true' /etc/wsl.conf 2>/dev/null; then
			printf 'configured|systemd + appendWindowsPath'
		else
			printf 'check|/etc/wsl.conf not as expected'
		fi
		;;
	git_credential)
		gcm="$(git config --global credential.helper 2>/dev/null || true)"
		if [[ -n "$gcm" ]]; then
			printf 'configured|%s\n' "$gcm"
		else
			printf 'skipped|no global credential.helper'
		fi
		;;
	*)
		printf '—|unknown component'
		;;
	esac
}

print_install_summary() {
	local i key label row result detail short_label
	local ok_count=0 miss_count=0

	echo ""
	echo "=== Install summary ==="
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

run_install() {
	echo ""
	echo "=== Installing ==="
	_log_legend_line
	echo ""

	# Default branch name (always safe regardless of identity setup)
	git config --global init.defaultBranch main

	# Git identity (only if selected -- skipped when conditional includes are in use)
	is_on git_identity && apply_git_config

	# apt update once if any apt packages are selected
	if is_on system_packages || is_on python || is_on powershell; then
		log_step "Refresh apt indexes"
		if _run_quiet_command "apt indexes refresh" sudo apt-get update -qq; then
			log_ok "apt indexes refreshed"
		else
			log_warn "apt indexes refresh failed"
			exit 1
		fi
	fi

	# apt packages by tag
	is_on system_packages && apt_install_packages core cli system
	is_on python && apt_install_packages python
	if is_on powershell; then
		install_powershell || echo "  Warning: PowerShell install failed."
	fi
	if is_on go; then
		install_go_via_asdf || echo "  Warning: Go install via asdf failed."
	fi

	# GitHub-installed tools
	if is_on lazygit; then
		if command -v lazygit >/dev/null 2>&1; then
			log_skip "lazygit already installed"
		else
			install_lazygit_from_github || echo "  Warning: lazygit install failed."
		fi
	fi

	if is_on lazydocker; then
		if command -v lazydocker >/dev/null 2>&1; then
			log_skip "lazydocker already installed"
		else
			install_lazydocker_from_github || echo "  Warning: lazydocker install failed."
		fi
	fi

	# WSL config
	is_on wsl_conf && configure_wsl

	# Git credential helper
	is_on git_credential && configure_git_credential_helper

	# Docker
	is_on docker && install_docker

	# Portainer
	is_on portainer && install_portainer

	# Node.js
	is_on nodejs && install_node_via_nvm

	# direnv
	if is_on direnv; then
		install_direnv || echo "  Warning: direnv install failed."
		ensure_direnv_hook_in_bashrc
	fi

	# AI CLI tools
	if is_on cursor_cli; then
		install_cursor_cli || echo "  Warning: Cursor CLI install failed."
	fi
	if is_on codex_cli; then
		install_codex_cli || echo "  Warning: Codex CLI install failed."
	fi
	if is_on claude_cli; then
		install_claude_cli || echo "  Warning: Claude CLI install failed."
	fi
	if is_on copilot_cli; then
		install_copilot_cli || echo "  Warning: Copilot CLI install failed."
	fi

	# Monaspace fonts
	if is_on monaspace_fonts; then
		install_monaspace_fonts || echo "  Warning: Monaspace fonts install failed."
	fi

	# SSH key
	is_on ssh_key && generate_ssh_key

	# Post-install fixes (fd symlink, ~/bin)
	if is_on system_packages; then
		post_install_fixes
		ensure_wslview_browser_in_bashrc
	fi

	# Dotfiles (stow)
	if is_on dotfiles; then
		backup_existing_dotfiles
		stow_dotfiles
		ensure_bash_profile_sources_bashrc
	fi

	print_install_summary

	echo ""
	echo "Done. Log saved to: $LOG_FILE"
	echo "Open a new terminal, or run: source ~/.bashrc"
}

main() {
	if ! command -v apt-get >/dev/null 2>&1; then
		echo "Error: apt-get not found. This installer targets Debian/Ubuntu." >&2
		exit 1
	fi

	local mode=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--initial)
			mode="initial"
			shift
			;;
		--update)
			mode="update"
			shift
			;;
		--extensions)
			mode="extensions"
			shift
			;;
		--agents)
			mode="agents"
			shift
			;;
		--help | -h)
			print_usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			print_usage >&2
			exit 1
			;;
		esac
	done

	if [[ -z "$mode" ]]; then
		if [[ "$DOTFILES_INTERACTIVE_TTY" == true ]]; then
			main_menu_loop
			return 0
		fi
		run_initial_setup_flow
		return 0
	fi

	case "$mode" in
	initial)
		if [[ "$DOTFILES_INTERACTIVE_TTY" == true ]]; then
			initial_setup_menu
		else
			run_initial_setup_flow
		fi
		;;
	update)
		update_menu
		;;
	extensions)
		extensions_menu
		;;
	agents)
		agents_menu
		;;
	*)
		printf 'unknown mode: %s\n' "$mode" >&2
		exit 1
		;;
	esac
}

main "$@"
