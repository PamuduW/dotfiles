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

# Dependencies use stable component keys so display-order changes cannot silently
# change their meaning.
declare -A COMP_DEPENDS_ON=(
	[graphify_cli]=python
	[portainer]=docker
	[lazydocker]=docker
	[codex_cli]=nodejs
	[dotfiles]=system_packages
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
		for operation in desc plan probe install; do
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

	if git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
		COMP_ON[git_identity]=0
	fi
	# Graphify is intentionally opt-in; selecting all components remains an
	# explicit action in the interactive picker.
	COMP_ON[graphify_cli]=0
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
