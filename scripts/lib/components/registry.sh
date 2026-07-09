# shellcheck shell=bash
# Component registry: keys, labels, deps, and dispatch helpers.

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

# Install execution order (differs from menu display order).
COMP_INSTALL_ORDER=(
	git_identity
	system_packages
	python
	powershell
	go
	lazygit
	lazydocker
	wsl_conf
	git_credential
	docker
	portainer
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

comp_registry_init() {
	local _key
	for _key in "${COMP_KEYS[@]}"; do
		COMP_ON["$_key"]=1
	done

	if git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
		COMP_ON[git_identity]=0
	fi
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

comp_key_index() {
	local want="$1"
	local i
	for i in "${!COMP_KEYS[@]}"; do
		[[ "${COMP_KEYS[$i]}" == "$want" ]] && {
			printf '%s\n' "$i"
			return 0
		}
	done
	return 1
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
	comp_call_fn '_comp_desc_' "$1"
}

comp_plan_row() {
	comp_call_fn '_comp_plan_' "$1"
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
