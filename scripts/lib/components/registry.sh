# shellcheck shell=bash
# shellcheck disable=SC2034  # Registry arrays are public to sourced component modules.
# Component registry: keys, labels, deps, and dispatch helpers.

COMP_KEYS=(
	git_identity
	system_packages
	python
	graphify_cli
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
	"Graphify CLI"
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
	"Git config (credentials + submodules)"
)

declare -A COMP_DESCRIPTIONS=(
	[git_identity]=$'Set global git user.name and user.email.\nSkip this if you use includeIf for per-directory identities.'
	[system_packages]=$'Installs the curated apt package catalog from packages/packages.txt.\nPackage Lib shows every package name, tag, and description.'
	[python]=$'Installs python3, pip, and venv via apt.\nProvides the standard Python runtime and virtual-environment tooling.'
	[graphify_cli]=$'Installs the official graphifyy package with uv, exposing the graphify CLI.\nOptional Agent Skills integration for Codex, Cursor, Claude, and compatible assistants.'
	[powershell]=$'Installs Microsoft PowerShell from packages.microsoft.com.\nAdds the Microsoft apt repository if missing, then installs powershell.'
	[go]=$'Installs latest Go via asdf and sets it for the user.\nThe selected Go version is available to shells and Go-based tools.'
	[nodejs]=$'Installs Node.js v24 via nvm (Node Version Manager).\nAlso provides npm for global packages like Codex CLI.'
	[direnv]=$'Installs or updates direnv to ~/.local/bin via the official installer.\nThe stowed .bashrc provides the direnv Bash hook.'
	[docker]=$'Installs Docker Engine CE and safely merges logging defaults into daemon.json.\nAdds your user to the docker group for non-root access.'
	[portainer]=$'Deploys the Portainer CE container (web UI for Docker).\nThe container is stopped by default; start it with dpot.'
	[lazygit]=$'Terminal UI for Git, downloaded from GitHub releases.\nUse it to review status, stage changes, and manage commits interactively.'
	[lazydocker]=$'Terminal UI for Docker, downloaded from GitHub releases.\nUse it to inspect containers, images, logs, and Compose services.'
	[cursor_cli]=$'Installs the Cursor editor CLI from cursor.com.\nUpdate it later through the Dotfiles update workflow.'
	[codex_cli]=$'Installs OpenAI Codex CLI via npm (requires Node.js).\nUpdate it later through the Dotfiles update workflow.'
	[claude_cli]=$'Installs Anthropic Claude CLI from claude.ai.\nUpdate it later through the Dotfiles update workflow.'
	[copilot_cli]=$'Installs GitHub Copilot CLI via the official installer script.\nDownloads and validates the vendor script before executing it.'
	[monaspace_fonts]=$'Downloads GitHub Monaspace Nerd Fonts to ~/.local/share/fonts/.\nIncludes all five variants with Powerline glyphs and development icons.'
	[ssh_key]=$'Generates an Ed25519 SSH key and adds it to ssh-agent.\nSaves the public key and GitHub setup steps to ~/.ssh/github-setup.txt.'
	[dotfiles]=$'Uses GNU Stow to link bash, bin, and readline configuration into $HOME.\nBacks up an existing .bashrc, .bash_aliases, and .inputrc first.'
	[wsl_conf]=$'Sets systemd=true and appendWindowsPath=true in /etc/wsl.conf.\nRequires wsl --shutdown from Windows to take effect.'
	[git_credential]=$'Sets credential.helper to Windows GCM for HTTPS when available.\nSets submodule.recurse, fetch.recurseSubmodules, push.recurseSubmodules=check, and status.submoduleSummary.'
)

declare -A COMP_PLAN_LABELS=(
	[git_identity]='Git identity' [system_packages]='System packages' [python]='Python'
	[graphify_cli]='Graphify CLI' [powershell]='PowerShell' [go]='Go' [nodejs]='Node.js'
	[direnv]='direnv' [docker]='Docker' [portainer]='Portainer' [lazygit]='lazygit'
	[lazydocker]='lazydocker' [cursor_cli]='Cursor CLI' [codex_cli]='Codex CLI'
	[claude_cli]='Claude CLI' [copilot_cli]='Copilot CLI' [monaspace_fonts]='Monaspace fonts'
	[ssh_key]='SSH key' [dotfiles]='Dotfiles' [wsl_conf]='WSL config' [git_credential]='Git config'
)

declare -A COMP_PLAN_DETAILS=(
	[python]='python3, pip, venv' [graphify_cli]='uv tool install graphifyy (optional)'
	[powershell]='Microsoft repo + powershell' [go]='asdf golang latest' [nodejs]='v24 via nvm'
	[direnv]='install/update + bash hook' [docker]='Docker Engine CE + docker group'
	[portainer]='Portainer CE (stopped by default)' [lazygit]='latest from GitHub'
	[lazydocker]='latest from GitHub' [cursor_cli]='cursor.com installer'
	[codex_cli]='npm @openai/codex' [claude_cli]='claude.ai installer'
	[copilot_cli]='gh.io/copilot-install'
	[monaspace_fonts]='Monaspace Nerd Fonts -> ~/.local/share/fonts/'
	[dotfiles]='stow bash, bin, readline' [wsl_conf]='systemd=true, appendWindowsPath=true'
	[git_credential]='GCM + recursive submodule defaults'
)

# Dependencies use stable component keys so display-order changes cannot silently
# change their meaning.
declare -A COMP_DEPENDS_ON=(
	[graphify_cli]=python
	[portainer]=docker
	[lazydocker]=docker
	[codex_cli]=nodejs
	[dotfiles]=system_packages
)

# Package groups owned by components. Installation and completion probes must
# use this same metadata so one component cannot report another as missing.
declare -A COMP_PACKAGE_TAGS=(
	[system_packages]='core cli system'
	[python]='python'
)

# Install execution order (differs from menu display order).
COMP_INSTALL_ORDER=(
	git_identity
	system_packages
	python
	graphify_cli
	powershell
	go
	lazygit
	wsl_conf
	git_credential
	docker
	portainer
	lazydocker
	nodejs
	direnv
	cursor_cli
	codex_cli
	claude_cli
	copilot_cli
	monaspace_fonts
	ssh_key
	dotfiles
)

declare -A COMP_ON

comp_dependency() {
	printf '%s\n' "${COMP_DEPENDS_ON[$1]:-}"
}

comp_package_tags() {
	printf '%s\n' "${COMP_PACKAGE_TAGS[$1]:-}"
}

comp_index_of() {
	local wanted="$1" i
	for i in "${!COMP_KEYS[@]}"; do
		[[ "${COMP_KEYS[$i]}" == "$wanted" ]] && {
			printf '%s\n' "$i"
			return 0
		}
	done
	return 1
}

comp_registry_validate() {
	local key dependency previous_index current_index
	local -A known=() ordered=()
	for key in "${COMP_KEYS[@]}"; do
		[[ -z "${known[$key]+x}" ]] || {
			printf 'duplicate component key: %s\n' "$key" >&2
			return 1
		}
		known[$key]=1
	done
	[[ "${#COMP_KEYS[@]}" -eq "${#COMP_LABELS[@]}" ]] || {
		printf 'component key/label count mismatch\n' >&2
		return 1
	}
	for key in "${!COMP_DEPENDS_ON[@]}"; do
		dependency="${COMP_DEPENDS_ON[$key]}"
		[[ -n "${known[$key]+x}" && -n "${known[$dependency]+x}" ]] || {
			printf 'invalid dependency: %s -> %s\n' "$key" "$dependency" >&2
			return 1
		}
	done
	for key in "${COMP_INSTALL_ORDER[@]}"; do
		[[ -n "${known[$key]+x}" && -z "${ordered[$key]+x}" ]] || {
			printf 'invalid or duplicate install-order key: %s\n' "$key" >&2
			return 1
		}
		ordered[$key]="${#ordered[@]}"
	done
	[[ "${#ordered[@]}" -eq "${#known[@]}" ]] || {
		printf 'install order does not contain every component\n' >&2
		return 1
	}
	for key in "${!COMP_DEPENDS_ON[@]}"; do
		dependency="${COMP_DEPENDS_ON[$key]}"
		current_index="${ordered[$key]}"
		previous_index="${ordered[$dependency]}"
		((previous_index < current_index)) || {
			printf 'dependency must be installed first: %s -> %s\n' "$key" "$dependency" >&2
			return 1
		}
	done
}

comp_registry_validate_contract() {
	local key operation function_name
	comp_registry_validate || return 1
	for key in "${COMP_KEYS[@]}"; do
		[[ -n "${COMP_DESCRIPTIONS[$key]:-}" && -n "${COMP_PLAN_LABELS[$key]:-}" ]] || {
			printf 'component metadata missing: %s\n' "$key" >&2
			return 1
		}
		for operation in probe install; do
			function_name="_comp_${operation}_${key}"
			declare -F "$function_name" >/dev/null 2>&1 || {
				printf 'component contract missing: %s\n' "$function_name" >&2
				return 1
			}
		done
	done
}

comp_registry_init() {
	local _key
	for _key in "${COMP_KEYS[@]}"; do
		COMP_ON["$_key"]=1
	done

	# Safe defaults: identity and key generation are user-specific decisions;
	# all other setup components, including optional Graphify, start selected.
	COMP_ON[git_identity]=0
	COMP_ON[ssh_key]=0
}

# Non-interactive: honor DOTFILES_COMPONENTS (comma-separated COMP_KEYS); default = all on.
apply_dotfiles_components_env() {
	local _key part

	comp_registry_init

	[[ -n "${DOTFILES_COMPONENTS:-}" ]] || return 0

	for _key in "${COMP_KEYS[@]}"; do
		COMP_ON["$_key"]=0
	done

	IFS=',' read -r -a _parts <<<"$DOTFILES_COMPONENTS"
	for part in "${_parts[@]}"; do
		part="${part// /}"
		[[ -n "$part" ]] || continue
		if [[ -n "${COMP_ON[$part]+x}" ]]; then
			COMP_ON["$part"]=1
		else
			printf 'warn: unknown DOTFILES_COMPONENTS key: %s\n' "$part" >&2
		fi
	done
}

comp_call_fn() {
	local prefix="$1"
	local key="$2"
	local fn="${prefix}${key}"

	if declare -f "$fn" >/dev/null 2>&1; then
		"$fn"
	else
		return 1
	fi
}

comp_description() {
	local description="${COMP_DESCRIPTIONS[$1]:-}"
	[[ -n "$description" ]] || return 1
	printf '%s\n' "$description"
}

comp_plan_row() {
	local key="$1" label="${COMP_PLAN_LABELS[$1]:-}" detail
	[[ -n "$label" ]] || return 1
	if ! is_on "$key"; then
		if [[ "$key" == git_identity ]] && git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
			ui_print_plan_row "$label" 'skip (conditional includes detected)' 0
		else
			ui_print_plan_row "$label" 'skip' 0
		fi
		return
	fi
	case "$key" in
	git_identity) detail="$SETUP_GIT_NAME <$SETUP_GIT_EMAIL>" ;;
	system_packages)
		local tags count
		tags="$(comp_package_tags "$key")"
		# shellcheck disable=SC2086 # Component package tags are an internal word list.
		count="$(read_packages_by_tags $tags | wc -l)"
		detail="${count} packages (@${tags// / @})"
		;;
	ssh_key)
		if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
			detail='already exists, will skip'
		else
			detail='generate ed25519 -> ~/.ssh/github-setup.txt'
		fi
		;;
	*) detail="${COMP_PLAN_DETAILS[$key]:-}" ;;
	esac
	ui_print_plan_row "$label" "$detail" 1
}

comp_probe() {
	if comp_call_fn '_comp_probe_' "$1"; then
		return 0
	fi
	printf '—|unknown component\n'
}

comp_install() {
	comp_call_fn '_comp_install_' "$1"
}
