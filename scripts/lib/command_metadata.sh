# shellcheck shell=bash
# shellcheck disable=SC2034  # Public metadata arrays are consumed by sourced callers.
# shellcheck disable=SC2016  # Literal variable expressions are documentation values.
# Authoritative public Dotfiles command metadata.

DOTFILES_COMMAND_KEYS=(
	menu
	update
	status
	commands
	packages
	restow
	help
)

declare -A DOTFILES_COMMAND_USAGE=(
	[menu]=''
	[update]='[--all]'
	[status]=''
	[commands]=''
	[packages]=''
	[restow]=''
	[help]=''
)

declare -A DOTFILES_COMMAND_CLASS=(
	[menu]='mutating'
	[update]='mutating'
	[status]='read-only'
	[commands]='read-only'
	[packages]='read-only'
	[restow]='mutating'
	[help]='read-only'
)

declare -A DOTFILES_COMMAND_DESCRIPTION=(
	[menu]='Open interactive install and update workflows.'
	[update]='Safely update the repo, then packages and tools.'
	[status]='Show local versions and repository state only.'
	[commands]='Show this authoritative command library.'
	[packages]='Show component and package metadata.'
	[restow]='Re-apply bash, bin, and readline stow links.'
	[help]='Show command usage and behavior classes.'
)

declare -A DOTFILES_COMMAND_NOTE=(
	[menu]=''
	[update]='Use --all to include Node.js, Go, and Monaspace.'
	[status]='Remote and apt freshness remain unchecked.'
	[commands]=''
	[packages]=''
	[restow]=''
	[help]=''
)

declare -A DOTFILES_COMMAND_OPTIONS=(
	[menu]=$'--initial|Run the initial setup flow through install.sh --initial.|menu default\n--update|Open the update workflow through install.sh --update.|menu default\n--agents|Open the Agentbot workflow through install.sh --agents.|menu default\n--help|Show installer menu help and exit.|off'
	[update]=$'--all|Include Node.js, Go, and Monaspace font updates.|off\n-h|Show command help and exit.|off\n--help|Show command help and exit.|off'
	[status]=$'(none)|Show local versions and repository state without command options.|always'
	[commands]=$'(none)|Show this full read-only command/configuration catalog.|always'
	[packages]=$'(none)|Show component and package metadata without probing the system.|always'
	[restow]=$'(none)|Re-apply the bash, bin, and readline stow packages.|always'
	[help]=$'(none)|Show the same full catalog as dotfiles commands, with the repository path.|always'
)

declare -A DOTFILES_COMMAND_DEFAULTS=(
	[menu]='No flags opens the interactive installer menu.'
	[update]='Without --all, opt-in Node.js, Go, and Monaspace updates are skipped.'
	[status]='Reads local installed versions; remote freshness remains unchecked.'
	[commands]='Prints the complete catalog without changing state.'
	[packages]='Reads packages/packages.txt and component metadata only.'
	[restow]='Targets $HOME using the bash, bin, and readline Stow packages.'
	[help]='Prints the catalog and the resolved Dotfiles repository path.'
)

declare -A DOTFILES_COMMAND_EFFECTS=(
	[menu]='Delegates to scripts/install.sh; selected workflows may install, update, or configure components.'
	[update]='May pull the repository, refresh apt, update CLIs, and optionally update Node.js, Go, and Monaspace.'
	[status]='Reads local command versions and git status; it does not run remote freshness checks.'
	[commands]='Performs no installer, git, network, stow, package, or component action.'
	[packages]='Performs no package installation or system probe.'
	[restow]='Runs stow --restow for bash, bin, and readline and changes home-directory links.'
	[help]='Performs no installer, git, network, stow, package, or component action.'
)

declare -A DOTFILES_COMMAND_EXAMPLES=(
	[menu]='dotfiles menu --agents'
	[update]='dotfiles update --all'
	[status]='dotfiles status'
	[commands]='dotfiles commands'
	[packages]='dotfiles packages'
	[restow]='dotfiles restow'
	[help]='dotfiles help'
)

declare -A DOTFILES_COMMAND_RELATED=(
	[menu]='Use dotfiles commands for a read-only reference; use dotfiles agentbot through the Agents menu when the bridge is installed.'
	[update]='Use status for local inspection and restow for link-only repair.'
	[status]='Use update when repository and downstream freshness should be checked.'
	[commands]='The interactive Command Lib renders this same catalog.'
	[packages]='Use the component menu for interactive selection.'
	[restow]='Use update for repository/downstream updates; restow does not install packages.'
	[help]='The commands subcommand prints the catalog without the trailing repository line.'
)

DOTFILES_CONFIG_KEYS=(
	DOTFILES_COMPONENTS AGENT_BOOTSTRAP_HOME AGENT_BOOTSTRAP_CLONE_HOME
	AGENT_BOOTSTRAP_ALLOW_OVERRIDE XDG_CONFIG_HOME GITHUB_TOKEN NO_COLOR FORCE_COLOR DOTFILES_TUI
)

declare -A DOTFILES_CONFIG_DESCRIPTION=(
	[DOTFILES_COMPONENTS]='Comma-separated component IDs for non-interactive component selection.'
	[AGENT_BOOTSTRAP_HOME]='Explicit Agentbot sibling path considered when resolving the integration.'
	[AGENT_BOOTSTRAP_CLONE_HOME]='Clone target used when the Agentbot sibling needs to be installed.'
	[AGENT_BOOTSTRAP_ALLOW_OVERRIDE]='Allows a non-canonical AGENT_BOOTSTRAP_HOME override when set to 1.'
	[XDG_CONFIG_HOME]='Base directory for shared private Agentbot configuration.'
	[GITHUB_TOKEN]='Optional GitHub API credential; its value is never rendered by Command Lib.'
	[NO_COLOR]='Disables ANSI styling when set.'
	[FORCE_COLOR]='Requests ANSI styling for non-TTY output when set.'
	[DOTFILES_TUI]='Marks TUI execution for presentation/bridge behavior.'
)

declare -A DOTFILES_CONFIG_DEFAULT=(
	[DOTFILES_COMPONENTS]='Unset; interactive selection or all enabled components apply.'
	[AGENT_BOOTSTRAP_HOME]='Unset; canonical sibling resolution wins unless override is allowed.'
	[AGENT_BOOTSTRAP_CLONE_HOME]='Unset; the sibling path next to Dotfiles is used.'
	[AGENT_BOOTSTRAP_ALLOW_OVERRIDE]='Unset/0; non-canonical overrides are rejected.'
	[XDG_CONFIG_HOME]='$HOME/.config when unset.'
	[GITHUB_TOKEN]='Unset; GitHub API calls remain unauthenticated.'
	[NO_COLOR]='Unset; colors follow TTY/TUI detection.'
	[FORCE_COLOR]='Unset.'
	[DOTFILES_TUI]='Unset for direct commands; set by menu callers when needed.'
)

declare -A DOTFILES_CONFIG_LOCATION=(
	[DOTFILES_COMPONENTS]='Process environment; comma-separated component IDs.'
	[AGENT_BOOTSTRAP_HOME]='Process environment; validated sibling repository path.'
	[AGENT_BOOTSTRAP_CLONE_HOME]='Process environment; clone destination path.'
	[AGENT_BOOTSTRAP_ALLOW_OVERRIDE]='Process environment; value 1 enables the override.'
	[XDG_CONFIG_HOME]='Process environment; ${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/.'
	[GITHUB_TOKEN]='Process environment or ${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/github.env.'
	[NO_COLOR]='Process environment only.'
	[FORCE_COLOR]='Process environment only.'
	[DOTFILES_TUI]='Process environment only.'
)

DOTFILES_SURFACE_KEYS=(repo links components agentbot)
declare -A DOTFILES_SURFACE_DESCRIPTION=(
	[repo]='The Dotfiles repository, package manifests, installers, and logs.'
	[links]='Stow-managed bash, bin, and readline links in the home directory.'
	[components]='Component registry, descriptions, package metadata, and selected installers.'
	[agentbot]='Sibling Agentbot clone, bridge menu, canonical policy sources, and rendered outputs.'
)
declare -A DOTFILES_SURFACE_LOCATION=(
	[repo]='DOTFILES_DIR and its packages/, scripts/, bin/, and log/ directories.'
	[links]='$HOME via GNU Stow packages bash, bin, and readline.'
	[components]='scripts/lib/components/ and packages/packages.txt.'
	[agentbot]='AGENT_BOOTSTRAP_HOME or the canonical sibling repository; global outputs under ~/.codex and ~/.claude.'
)

dotfiles_command_metadata_validate() {
	local -A seen=()
	local key class option description default

	for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
		[[ -n "$key" && -z "${seen[$key]+x}" ]] || return 1
		seen["$key"]=1
		class="${DOTFILES_COMMAND_CLASS[$key]:-}"
		[[ "$class" == read-only || "$class" == mutating ]] || return 1
		[[ -n "${DOTFILES_COMMAND_DESCRIPTION[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_USAGE[$key]+x}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_NOTE[$key]+x}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_OPTIONS[$key]+x}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_DEFAULTS[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_EFFECTS[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_EXAMPLES[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_RELATED[$key]:-}" ]] || return 1
		while IFS='|' read -r option description default; do
			[[ -z "$option" && -z "$description" && -z "$default" ]] && continue
			[[ -n "$option" && -n "$description" && -n "$default" ]] || return 1
		done <<<"${DOTFILES_COMMAND_OPTIONS[$key]}"
	done
	for key in "${DOTFILES_CONFIG_KEYS[@]}"; do
		[[ -n "${DOTFILES_CONFIG_DESCRIPTION[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_CONFIG_DEFAULT[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_CONFIG_LOCATION[$key]:-}" ]] || return 1
	done
	for key in "${DOTFILES_SURFACE_KEYS[@]}"; do
		[[ -n "${DOTFILES_SURFACE_DESCRIPTION[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_SURFACE_LOCATION[$key]:-}" ]] || return 1
	done
	[[ "${#seen[@]}" -eq "${#DOTFILES_COMMAND_KEYS[@]}" ]]
}

dotfiles_command_display_usage() {
	local key="$1"
	local suffix="${DOTFILES_COMMAND_USAGE[$key]:-}"
	if [[ -n "$suffix" ]]; then
		printf '%s %s' "$key" "$suffix"
	else
		printf '%s' "$key"
	fi
}

_dotfiles_command_fit() {
	local value="$1" width="$2"
	if ((width <= 0)); then
		return 0
	fi
	if ((${#value} <= width)); then
		printf '%s' "$value"
	elif ((width <= 3)); then
		printf '%s' "${value:0:width}"
	else
		printf '%s...' "${value:0:$((width - 3))}"
	fi
}

_dotfiles_command_print_cell() {
	local value="$1" width="$2" context="${3:-}" color='' reset=''
	if declare -F _rt_ensure_colors >/dev/null; then
		_rt_ensure_colors
		reset="$C_RESET"
		case "$context" in
		mutating) color="$C_YELLOW" ;;
		read-only) color="$C_GREEN" ;;
		esac
	fi
	printf '%s%s%s' "$color" "$value" "$reset"
	if ((width > ${#value})); then
		printf '%*s' "$((width - ${#value}))" ''
	fi
}

_dotfiles_command_wrap_words() {
	local text="$1" width="$2"
	local paragraph word line='' chunk
	((width < 1)) && width=1

	while IFS= read -r paragraph || [[ -n "$paragraph" ]]; do
		if [[ -z "$paragraph" ]]; then
			[[ -n "$line" ]] && { printf '%s\n' "$line"; line=''; }
			printf '\n'
			continue
		fi
		for word in $paragraph; do
			if [[ -n "$line" && $(( ${#line} + 1 + ${#word} )) -le $width ]]; then
				line+=" $word"
				continue
			fi
			if [[ -n "$line" ]]; then
				printf '%s\n' "$line"
				line=''
			fi
			while ((${#word} > width)); do
				chunk="${word:0:width}"
				printf '%s\n' "$chunk"
				word="${word:width}"
			done
			line="$word"
		done
	done <<<"$text"
	[[ -n "$line" ]] && printf '%s\n' "$line"
}

_dotfiles_command_print_field() {
	local label="$1" value="$2" cols="$3"
	local prefix_width=$((2 + ${#label} + 2)) continuation line
	local -a lines=()
	mapfile -t lines < <(_dotfiles_command_wrap_words "$value" "$((cols - prefix_width))")
	((${#lines[@]} > 0)) || lines=('')
	_rt_ensure_colors
	printf '  %s%s%s: %s\n' "$C_BOLD" "$label" "$C_RESET" "${lines[0]}"
	continuation="$(printf '%*s' "$prefix_width" '')"
	for line in "${lines[@]:1}"; do
		printf '%s%s\n' "$continuation" "$line"
	done
}

_dotfiles_command_print_token_field() {
	local token="$1" value="$2" cols="$3"
	local prefix_width=$((2 + ${#token} + 2)) continuation line
	local -a lines=()
	mapfile -t lines < <(_dotfiles_command_wrap_words "$value" "$((cols - prefix_width))")
	((${#lines[@]} > 0)) || lines=('')
	_rt_ensure_colors
	printf '  %s%s%s: %s\n' "$C_CYAN" "$token" "$C_RESET" "${lines[0]}"
	continuation="$(printf '%*s' "$prefix_width" '')"
	for line in "${lines[@]:1}"; do
		printf '%s%s\n' "$continuation" "$line"
	done
}

_dotfiles_command_print_section() {
	local label="$1"
	_rt_ensure_colors
	if declare -F rt_print_section >/dev/null; then
		rt_print_section "$label"
	else
		printf '\n  %s%s%s\n' "$C_BOLD$C_YELLOW" "$label" "$C_RESET"
	fi
}

_dotfiles_command_print_options() {
	local rows="$1" cols="$2"
	local option description default
	while IFS='|' read -r option description default; do
		[[ -n "$option" ]] || continue
		_dotfiles_command_print_token_field "$option" "$description (default: $default)" "$cols"
	done <<<"$rows"
}

dotfiles_command_print_details() {
	local cols="${1:-100}" key
	dotfiles_command_metadata_validate || return 1
	_dotfiles_command_print_section 'Command details'
	for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
		_rt_ensure_colors
		printf '\n  %sCommand: %s%s\n' "$C_BOLD$C_ORANGE" "$key" "$C_RESET"
		_dotfiles_command_print_field 'Usage' "$(dotfiles_command_display_usage "$key")" "$cols"
		_dotfiles_command_print_field 'Behavior' "${DOTFILES_COMMAND_CLASS[$key]}" "$cols"
		_dotfiles_command_print_field 'Purpose' "${DOTFILES_COMMAND_DESCRIPTION[$key]}" "$cols"
		printf '  %sOptions%s\n' "$C_BOLD" "$C_RESET"
		_dotfiles_command_print_options "${DOTFILES_COMMAND_OPTIONS[$key]}" "$cols"
		_dotfiles_command_print_field 'Defaults' "${DOTFILES_COMMAND_DEFAULTS[$key]}" "$cols"
		_dotfiles_command_print_field 'Effects' "${DOTFILES_COMMAND_EFFECTS[$key]}" "$cols"
		_dotfiles_command_print_field 'Example' "${DOTFILES_COMMAND_EXAMPLES[$key]}" "$cols"
		_dotfiles_command_print_field 'Related' "${DOTFILES_COMMAND_RELATED[$key]}" "$cols"
		[[ -n "${DOTFILES_COMMAND_NOTE[$key]}" ]] && \
			_dotfiles_command_print_field 'Note' "${DOTFILES_COMMAND_NOTE[$key]}" "$cols"
	done

	_dotfiles_command_print_section 'Configuration and environment'
	for key in "${DOTFILES_CONFIG_KEYS[@]}"; do
		_dotfiles_command_print_token_field "$key" \
			"${DOTFILES_CONFIG_DESCRIPTION[$key]} Default: ${DOTFILES_CONFIG_DEFAULT[$key]} Location: ${DOTFILES_CONFIG_LOCATION[$key]}" "$cols"
	done

	_dotfiles_command_print_section 'System surfaces'
	for key in "${DOTFILES_SURFACE_KEYS[@]}"; do
		_dotfiles_command_print_token_field "$key" \
			"${DOTFILES_SURFACE_DESCRIPTION[$key]} Location: ${DOTFILES_SURFACE_LOCATION[$key]}" "$cols"
	done

	_dotfiles_command_print_section 'Integrations'
	_dotfiles_command_print_field 'Agentbot integration' \
		'Dotfiles resolves the sibling Agentbot repository through AGENT_BOOTSTRAP_HOME or the canonical sibling path, then exposes Agentbot setup from the Agents menu. Agentbot renders canonical policy files into global Codex/Claude locations and selected repository surfaces.' "$cols"
}

dotfiles_command_print_table() {
	local cols="${1:-100}"
	local usage_w=20 class_w=10 description_w available
	local key usage description usage_fit class_fit description_fit
	dotfiles_command_metadata_validate || return 1

	# Two leading spaces and two " | " separators consume eight columns.
	available=$((cols - 8))
	if ((available < usage_w + class_w + 1)); then
		class_w=9
		usage_w=15
	fi
	if ((available < usage_w + class_w + 1)); then
		class_w=$((available / 3))
		((class_w < 1)) && class_w=1
		usage_w=$((available / 2))
		((usage_w < 1)) && usage_w=1
	fi
	description_w=$((available - usage_w - class_w))
	((description_w < 1)) && description_w=1

	if declare -F _rt_ensure_colors >/dev/null; then
		_rt_ensure_colors
	else
		C_BOLD=''
		C_RESET=''
	fi
	usage_fit="$(_dotfiles_command_fit command "$usage_w")"
	class_fit="$(_dotfiles_command_fit behavior "$class_w")"
	description_fit="$(_dotfiles_command_fit description "$description_w")"
	printf '  %s%-*s%s | %s%-*s%s | %-*s\n' \
		"$C_BOLD" "$usage_w" "$usage_fit" "$C_RESET" \
		"$C_BOLD" "$class_w" "$class_fit" "$C_RESET" \
		"$description_w" "$description_fit"
	local usage_rule class_rule description_rule
	usage_rule="$(printf '%*s' "$usage_w" '')"; usage_rule="${usage_rule// /-}"
	class_rule="$(printf '%*s' "$class_w" '')"; class_rule="${class_rule// /-}"
	description_rule="$(printf '%*s' "$description_w" '')"; description_rule="${description_rule// /-}"
	printf '  %s-+-%s-+-%s\n' "$usage_rule" "$class_rule" "$description_rule"
	for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
		usage="$(dotfiles_command_display_usage "$key")"
		description="${DOTFILES_COMMAND_DESCRIPTION[$key]}"
		usage_fit="$(_dotfiles_command_fit "$usage" "$usage_w")"
		class_fit="$(_dotfiles_command_fit "${DOTFILES_COMMAND_CLASS[$key]}" "$class_w")"
		description_fit="$(_dotfiles_command_fit "$description" "$description_w")"
		printf '  %-*s | ' "$usage_w" "$usage_fit"
		_dotfiles_command_print_cell "$class_fit" "$class_w" "${DOTFILES_COMMAND_CLASS[$key]}"
		printf ' | %-*s\n' "$description_w" "$description_fit"
	done
	dotfiles_command_print_details "$cols"
}

dotfiles_command_dispatch_keys() {
	local file="${1:?dispatcher file is required}"
	local line pattern part key
	local in_main=false in_case=false
	local -a parts=()

	[[ -f "$file" ]] || return 1
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" == 'main() {' ]]; then
			in_main=true
			continue
		fi
		[[ "$in_main" == true ]] || continue
		if [[ "$in_case" == false && "$line" =~ ^[[:space:]]*case[[:space:]].*[[:space:]]in[[:space:]]*$ ]]; then
			in_case=true
			continue
		fi
		[[ "$in_case" == true ]] || continue
		[[ "$line" =~ ^[[:space:]]*esac ]] && return 0
		if [[ "$line" =~ ^[[:space:]]*([^\)]*)\) ]]; then
			pattern="${BASH_REMATCH[1]}"
			IFS='|' read -r -a parts <<<"$pattern"
			for part in "${parts[@]}"; do
				key="${part#"${part%%[![:space:]]*}"}"
				key="${key%"${key##*[![:space:]]}"}"
				key="${key//\'/}"
				key="${key//\"/}"
				case "$key" in
				'' | '*' | -h | --help) continue ;;
				esac
				printf '%s\n' "$key"
			done
		fi
	done <"$file"
	return 1
}

dotfiles_command_metadata_validate_dispatch() {
	local file="${1:?dispatcher file is required}"
	local -a dispatch_keys=()
	local -A seen=()
	local i key

	dotfiles_command_metadata_validate || return 1
	mapfile -t dispatch_keys < <(dotfiles_command_dispatch_keys "$file") || return 1
	[[ "${#dispatch_keys[@]}" -eq "${#DOTFILES_COMMAND_KEYS[@]}" ]] || return 1
	for i in "${!dispatch_keys[@]}"; do
		key="${dispatch_keys[$i]}"
		[[ -z "${seen[$key]+x}" ]] || return 1
		seen["$key"]=1
		[[ "$key" == "${DOTFILES_COMMAND_KEYS[$i]}" ]] || return 1
	done
}
