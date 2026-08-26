# shellcheck shell=bash
# shellcheck disable=SC2034  # Registry arrays are public to sourced component modules.
# Component registry.
#
# One comp_define call per component. Previously the same 21 components were
# spread across eight arrays, one of which (COMP_LABELS) was positional against
# COMP_KEYS while the rest were keyed: inserting a component and forgetting one
# array silently shifted every label below it, with no test failure because the
# lengths still matched. Declaring each component once makes that impossible.

COMP_KEYS=()
COMP_LABELS=()
COMP_INSTALL_ORDER=()
declare -gA COMP_DESCRIPTIONS=()
declare -gA COMP_PLAN_LABELS=()
declare -gA COMP_PLAN_DETAILS=()
declare -gA COMP_DEPENDS_ON=()
declare -gA COMP_PACKAGE_TAGS=()
declare -gA COMP_ON=()
declare -gA _COMP_ORDER_RANK=()

# comp_define <key> [--label L] [--plan L] [--detail D] [--desc D]
#             [--depends KEY] [--tags "t1 t2"] [--order N]
#
# --order is the install rank (menu display order is declaration order); the
# ranks are sorted into COMP_INSTALL_ORDER by comp_registry_finalize.
comp_define() {
	local key="$1"
	shift
	local label='' plan='' detail='' desc='' depends='' tags='' order=''

	while (($#)); do
		case "$1" in
		--label)
			label="$2"
			shift 2
			;;
		--plan)
			plan="$2"
			shift 2
			;;
		--detail)
			detail="$2"
			shift 2
			;;
		--desc)
			desc="$2"
			shift 2
			;;
		--depends)
			depends="$2"
			shift 2
			;;
		--tags)
			tags="$2"
			shift 2
			;;
		--order)
			order="$2"
			shift 2
			;;
		*)
			printf 'comp_define %s: unknown option %s\n' "$key" "$1" >&2
			return 2
			;;
		esac
	done

	[[ -n "$key" && -n "$label" && -n "$order" ]] || {
		printf 'comp_define %s: key, --label, and --order are required\n' "$key" >&2
		return 2
	}

	COMP_KEYS+=("$key")
	COMP_LABELS+=("$label")
	COMP_PLAN_LABELS["$key"]="${plan:-$label}"
	COMP_DESCRIPTIONS["$key"]="$desc"
	[[ -n "$detail" ]] && COMP_PLAN_DETAILS["$key"]="$detail"
	[[ -n "$depends" ]] && COMP_DEPENDS_ON["$key"]="$depends"
	[[ -n "$tags" ]] && COMP_PACKAGE_TAGS["$key"]="$tags"
	_COMP_ORDER_RANK["$key"]="$order"
	return 0
}

# Build COMP_INSTALL_ORDER from the declared ranks.
comp_registry_finalize() {
	local key
	COMP_INSTALL_ORDER=()
	while IFS=$'\t' read -r _ key; do
		COMP_INSTALL_ORDER+=("$key")
	done < <(
		for key in "${!_COMP_ORDER_RANK[@]}"; do
			printf '%s\t%s\n' "${_COMP_ORDER_RANK[$key]}" "$key"
		done | sort -n -k1,1
	)
}

comp_define git_identity \
	--label 'Git identity (global user.name / email)' \
	--plan 'Git identity' \
	--order 0 \
	--desc $'Set global git user.name and user.email.\nSkip this if you use includeIf for per-directory identities.'

comp_define system_packages \
	--label 'System packages' \
	--plan 'System packages' \
	--tags 'core cli system' \
	--order 1 \
	--desc $'Installs the curated apt package catalog from packages/packages.txt.\nPackage Lib shows every package name, tag, and description.'

comp_define python \
	--label 'Python (python3, pip, venv)' \
	--plan 'Python' \
	--detail 'python3, pip, venv' \
	--tags 'python' \
	--order 2 \
	--desc $'Installs python3, pip, and venv via apt.\nProvides the standard Python runtime and virtual-environment tooling.'

comp_define graphify_cli \
	--label 'Graphify CLI' \
	--plan 'Graphify CLI' \
	--detail 'uv tool install graphifyy (optional)' \
	--depends 'python' \
	--order 3 \
	--desc $'Installs the official graphifyy package with uv, exposing the graphify CLI.\nOptional Agent Skills integration for Codex, Cursor, Claude, and compatible assistants.'

comp_define boost_cli \
	--label 'Boost CLI (preview)' \
	--plan 'Boost CLI' \
	--detail 'latest verified release (opt-in)' \
	--order 4 \
	--desc $'Installs the latest JFrog Boost CLI release to ~/.local/bin, after verifying\nits published SHA-256 digest. Preview software; disabled by default.\nAgentbot owns Claude/Codex integration.'

comp_define powershell \
	--label 'PowerShell (pwsh)' \
	--plan 'PowerShell' \
	--detail 'Microsoft repo + powershell' \
	--order 4 \
	--desc $'Installs Microsoft PowerShell from packages.microsoft.com.\nAdds the Microsoft apt repository if missing, then installs powershell.'

comp_define go \
	--label 'Go (asdf)' \
	--plan 'Go' \
	--detail 'asdf golang latest' \
	--order 5 \
	--desc $'Installs latest Go via asdf and sets it for the user.\nThe selected Go version is available to shells and Go-based tools.'

comp_define nodejs \
	--label 'Node.js 24 LTS (nvm)' \
	--plan 'Node.js' \
	--detail 'v24 via nvm' \
	--order 12 \
	--desc $'Installs Node.js v24 via nvm (Node Version Manager).\nAlso provides npm for global packages like Codex CLI.'

comp_define direnv \
	--label 'direnv (env loader + shell hook)' \
	--plan 'direnv' \
	--detail 'install/update + bash hook' \
	--order 13 \
	--desc $'Installs or updates direnv to ~/.local/bin via the official installer.\nThe stowed .bashrc provides the direnv Bash hook.'

comp_define docker \
	--label 'Docker Engine' \
	--plan 'Docker' \
	--detail 'Docker Engine CE + docker group' \
	--order 9 \
	--desc $'Installs Docker Engine CE and safely merges logging defaults into daemon.json.\nAdds your user to the docker group for non-root access.'

comp_define portainer \
	--label 'Portainer CE' \
	--plan 'Portainer' \
	--detail 'Portainer CE (stopped by default)' \
	--depends 'docker' \
	--order 10 \
	--desc $'Deploys the Portainer CE container (web UI for Docker).\nThe container is stopped by default; start it with dpot.'

comp_define lazygit \
	--label 'lazygit (git TUI)' \
	--plan 'lazygit' \
	--detail 'latest from GitHub' \
	--order 6 \
	--desc $'Terminal UI for Git, downloaded from GitHub releases.\nUse it to review status, stage changes, and manage commits interactively.'

comp_define lazydocker \
	--label 'lazydocker (docker TUI)' \
	--plan 'lazydocker' \
	--detail 'latest from GitHub' \
	--depends 'docker' \
	--order 11 \
	--desc $'Terminal UI for Docker, downloaded from GitHub releases.\nUse it to inspect containers, images, logs, and Compose services.'

comp_define cursor_cli \
	--label 'Cursor CLI' \
	--plan 'Cursor CLI' \
	--detail 'cursor.com installer' \
	--order 14 \
	--desc $'Installs the Cursor editor CLI from cursor.com.\nUpdate it later through the Dotfiles update workflow.'

comp_define codex_cli \
	--label 'Codex CLI' \
	--plan 'Codex CLI' \
	--detail 'npm @openai/codex' \
	--depends 'nodejs' \
	--order 15 \
	--desc $'Installs OpenAI Codex CLI via npm (requires Node.js).\nUpdate it later through the Dotfiles update workflow.'

comp_define claude_cli \
	--label 'Claude CLI' \
	--plan 'Claude CLI' \
	--detail 'claude.ai installer' \
	--order 16 \
	--desc $'Installs Anthropic Claude CLI from claude.ai.\nUpdate it later through the Dotfiles update workflow.'

comp_define copilot_cli \
	--label 'Copilot CLI' \
	--plan 'Copilot CLI' \
	--detail 'gh.io/copilot-install' \
	--order 17 \
	--desc $'Installs GitHub Copilot CLI via the official installer script.\nDownloads and validates the vendor script before executing it.'

comp_define monaspace_fonts \
	--label 'Monaspace fonts (Nerd Fonts)' \
	--plan 'Monaspace fonts' \
	--detail 'Monaspace Nerd Fonts -> ~/.local/share/fonts/' \
	--order 18 \
	--desc $'Downloads GitHub Monaspace Nerd Fonts to ~/.local/share/fonts/.\nIncludes all five variants with Powerline glyphs and development icons.'

comp_define ssh_key \
	--label 'Generate SSH key' \
	--plan 'SSH key' \
	--order 19 \
	--desc $'Generates an Ed25519 SSH key and adds it to ssh-agent.\nSaves the public key and GitHub setup steps to ~/.ssh/github-setup.txt.'

comp_define dotfiles \
	--label 'Apply dotfiles (stow)' \
	--plan 'Dotfiles' \
	--detail 'stow bash, bin, readline' \
	--depends 'system_packages' \
	--order 20 \
	--desc $'Uses GNU Stow to link bash, bin, and readline configuration into $HOME.\nBacks up an existing .bashrc, .bash_aliases, and .inputrc first.'

comp_define wsl_conf \
	--label 'WSL config (systemd, appendWindowsPath)' \
	--plan 'WSL config' \
	--detail 'systemd=true, appendWindowsPath=true' \
	--order 7 \
	--desc $'Sets systemd=true and appendWindowsPath=true in /etc/wsl.conf.\nRequires wsl --shutdown from Windows to take effect.'

comp_define git_credential \
	--label 'Git config (credentials + submodules)' \
	--plan 'Git config' \
	--detail 'GCM + recursive submodule defaults' \
	--order 8 \
	--desc $'Sets credential.helper to Windows GCM for HTTPS when available.\nSets submodule.recurse, fetch.recurseSubmodules, push.recurseSubmodules=check, and status.submoduleSummary.'

comp_registry_finalize

# Selection predicate. Lives beside COMP_ON so the component modules that use it
# (probes, install_dispatch, menus) do not depend on scripts/install.sh.
is_on() { [[ "${COMP_ON[$1]}" -eq 1 ]]; }

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
	# comp_define appends to both, so this can only trip if something wrote to
	# the arrays directly.
	[[ "${#COMP_KEYS[@]}" -eq "${#COMP_LABELS[@]}" ]] || {
		printf 'component key/label count mismatch\n' >&2
		return 1
	}
	# Every component needs a status probe and an install action, or it will
	# silently report "probe failed" / do nothing when selected.
	for key in "${COMP_KEYS[@]}"; do
		if declare -F "_comp_probe_${key}" >/dev/null 2>&1 ||
			declare -F comp_probe >/dev/null 2>&1; then
			:
		else
			printf 'component without a probe: %s\n' "$key" >&2
			return 1
		fi
	done
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

	# Safe defaults: identity/key generation and preview Boost installation are
	# explicit user decisions. Other setup components start selected.
	COMP_ON[git_identity]=0
	COMP_ON[ssh_key]=0
	COMP_ON[boost_cli]=0
}

# Non-interactive: honor DOTFILES_COMPONENTS (comma-separated COMP_KEYS);
# otherwise use the same safe defaults as the interactive menu.
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
