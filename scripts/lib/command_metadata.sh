# shellcheck shell=bash
# shellcheck disable=SC2034  # Public metadata arrays are consumed by sourced callers.
# shellcheck disable=SC2016  # Literal variable expressions are documentation values.
# Authoritative public Dotfiles command metadata.
#
# One dotfiles_command_define call per command. This used to be eleven parallel
# associative arrays that had to be kept in step by hand, which is why the
# validator below existed mostly to prove they still were. Declaring each
# command once removes that whole class of mistake; the validator now only
# checks that each record is complete and well formed.

DOTFILES_COMMAND_KEYS=()
declare -A DOTFILES_COMMAND_HANDLERS=()
declare -A DOTFILES_COMMAND_USAGE=()
declare -A DOTFILES_COMMAND_CLASS=()
declare -A DOTFILES_COMMAND_DESCRIPTION=()
declare -A DOTFILES_COMMAND_NOTE=()
declare -A DOTFILES_COMMAND_OPTIONS=()
declare -A DOTFILES_COMMAND_DEFAULTS=()
declare -A DOTFILES_COMMAND_EFFECTS=()
declare -A DOTFILES_COMMAND_EXAMPLES=()
declare -A DOTFILES_COMMAND_RELATED=()

# dotfiles_command_define <key> --handler FN --class read-only|mutating
#     --description D --options ROWS --defaults D --effects E
#     --example E --related R [--usage U] [--note N]
#
# --options rows are "option|description|default", one per line.
dotfiles_command_define() {
	local key="$1"
	shift
	local handler='' usage='' class='' description='' note=''
	local options='' defaults='' effects='' example='' related=''

	while (($#)); do
		case "$1" in
		--handler)
			handler="$2"
			shift 2
			;;
		--usage)
			usage="$2"
			shift 2
			;;
		--class)
			class="$2"
			shift 2
			;;
		--description)
			description="$2"
			shift 2
			;;
		--note)
			note="$2"
			shift 2
			;;
		--options)
			options="$2"
			shift 2
			;;
		--defaults)
			defaults="$2"
			shift 2
			;;
		--effects)
			effects="$2"
			shift 2
			;;
		--example)
			example="$2"
			shift 2
			;;
		--related)
			related="$2"
			shift 2
			;;
		*)
			printf 'dotfiles_command_define %s: unknown option %s\n' "$key" "$1" >&2
			return 2
			;;
		esac
	done

	DOTFILES_COMMAND_KEYS+=("$key")
	DOTFILES_COMMAND_HANDLERS["$key"]="$handler"
	DOTFILES_COMMAND_USAGE["$key"]="$usage"
	DOTFILES_COMMAND_CLASS["$key"]="$class"
	DOTFILES_COMMAND_DESCRIPTION["$key"]="$description"
	DOTFILES_COMMAND_NOTE["$key"]="$note"
	DOTFILES_COMMAND_OPTIONS["$key"]="$options"
	DOTFILES_COMMAND_DEFAULTS["$key"]="$defaults"
	DOTFILES_COMMAND_EFFECTS["$key"]="$effects"
	DOTFILES_COMMAND_EXAMPLES["$key"]="$example"
	DOTFILES_COMMAND_RELATED["$key"]="$related"
	return 0
}

dotfiles_command_define 'menu' \
	--handler 'cmd_menu' \
	--class 'mutating' \
	--description 'Open interactive install and update workflows.' \
	--options $'--initial|Run the initial setup flow through install.sh --initial.|menu default\n--update|Open the update workflow through install.sh --update.|menu default\n--help|Show installer menu help and exit.|off' \
	--defaults 'No flags opens the interactive installer menu.' \
	--effects 'Delegates to scripts/install.sh; selected workflows may install, update, or configure components.' \
	--example 'dotfiles menu' \
	--related 'Use dotfiles commands for a read-only reference.'

dotfiles_command_define 'update' \
	--handler 'cmd_update' \
	--usage '[--all] [--dry-run]' \
	--class 'mutating' \
	--description 'Safely update the repo, then packages and tools.' \
	--note 'One approval updates every managed component; --all is accepted but selects nothing extra.' \
	--options $'--all|Accepted for compatibility; every managed update already runs without it.|no-op\n--dry-run|Show the update report, then stop before any downstream change.|off\n-h|Show command help and exit.|off\n--help|Show command help and exit.|off' \
	--defaults 'One approval runs every managed update, including Node.js, npm, Go, and Monaspace.' \
	--effects 'May pull the repository, refresh apt, and update all managed CLIs, runtimes, and fonts.' \
	--example 'dotfiles update' \
	--related 'Use status for local inspection and restow for link-only repair.'

dotfiles_command_define 'full-update' \
	--handler 'cmd_full_update' \
	--class 'mutating' \
	--description 'Update Dotfiles and Agentbot without application prompts.' \
	--note 'Backs up replaceable local Git state before syncing upstream.' \
	--options '(none)|Run the complete unattended Dotfiles and Agentbot maintenance flow.|always' \
	--defaults 'Running the command authorizes application prompts and recoverable repository replacement.' \
	--effects 'May stash local changes, create recovery branches, sync both repositories, and update the system.' \
	--example 'dotfiles full-update' \
	--related 'Use update for an interactive Dotfiles-only run.'

dotfiles_command_define 'doctor' \
	--handler 'cmd_doctor' \
	--class 'read-only' \
	--description 'Show only components that need attention.' \
	--note 'Exits nonzero when anything needs attention, so scripts can gate on it.' \
	--options $'(none)|Report components whose probe is not installed or configured.|always' \
	--defaults 'Reads the same component probes as status; performs no installation.' \
	--effects 'Reads local component state only; changes nothing.' \
	--example 'dotfiles doctor' \
	--related 'Use status for the full component list and update to refresh tools.'

dotfiles_command_define 'status' \
	--handler 'cmd_status' \
	--class 'read-only' \
	--description 'Show local component and repository state only.' \
	--note 'Remote and apt freshness remain unchecked.' \
	--options '(none)|Show local versions and repository state without command options.|always' \
	--defaults 'Reads local installed versions; remote freshness remains unchecked.' \
	--effects 'Reads local command versions and git status; it does not run remote freshness checks.' \
	--example 'dotfiles status' \
	--related 'Use update when repository and downstream freshness should be checked.'

dotfiles_command_define 'commands' \
	--handler 'cmd_commands' \
	--class 'read-only' \
	--description 'Show this authoritative command library.' \
	--options '(none)|Show this full read-only command/configuration catalog.|always' \
	--defaults 'Prints the complete catalog without changing state.' \
	--effects 'Performs no installer, git, network, stow, package, or component action.' \
	--example 'dotfiles commands' \
	--related 'The interactive Command Lib renders this same catalog.'

dotfiles_command_define 'packages' \
	--handler 'cmd_packages' \
	--class 'read-only' \
	--description 'Show component and package metadata.' \
	--options '(none)|Show component and package metadata without probing the system.|always' \
	--defaults 'Reads packages/packages.txt and component metadata only.' \
	--effects 'Performs no package installation or system probe.' \
	--example 'dotfiles packages' \
	--related 'Use the component menu for interactive selection.'

dotfiles_command_define 'logs' \
	--handler 'cmd_logs' \
	--usage '[--list|--last]' \
	--class 'read-only' \
	--description 'List retained action logs or print the newest.' \
	--options $'--list|List retained logs, newest first, with sizes.|default\n--last|Print the newest log in full.|off' \
	--defaults 'Lists the retained logs in log/ without options.' \
	--effects 'Reads log/ only; writes nothing and starts no log of its own.' \
	--example 'dotfiles logs --last' \
	--related 'DOTFILES_LOG_RETAIN controls how many logs are kept.'

dotfiles_command_define 'restow' \
	--handler 'cmd_restow' \
	--class 'mutating' \
	--description 'Re-apply bash, bin, and readline stow links.' \
	--options '(none)|Re-apply the bash, bin, and readline stow packages.|always' \
	--defaults 'Targets $HOME using the bash, bin, and readline Stow packages.' \
	--effects 'Runs stow --restow for bash, bin, and readline and changes home-directory links.' \
	--example 'dotfiles restow' \
	--related 'Use update for repository/downstream updates; restow does not install packages.'

dotfiles_command_define 'help' \
	--handler 'cmd_help' \
	--class 'read-only' \
	--description 'Show command usage and behavior classes.' \
	--options '(none)|Show the same full catalog as dotfiles commands, with the repository path.|always' \
	--defaults 'Prints the catalog and the resolved Dotfiles repository path.' \
	--effects 'Performs no installer, git, network, stow, package, or component action.' \
	--example 'dotfiles help' \
	--related 'The commands subcommand prints the catalog without the trailing repository line.'

DOTFILES_CONFIG_KEYS=(
	DOTFILES_COMPONENTS XDG_CONFIG_HOME GITHUB_TOKEN NO_COLOR FORCE_COLOR DOTFILES_TUI
	DOTFILES_LOG_RETAIN
)

declare -A DOTFILES_CONFIG_DESCRIPTION=(
	[DOTFILES_COMPONENTS]='Comma-separated component IDs for non-interactive component selection.'
	[XDG_CONFIG_HOME]='Base directory for shared private Agentbot configuration.'
	[GITHUB_TOKEN]='Optional GitHub API credential; its value is never rendered by Command Lib.'
	[NO_COLOR]='Disables ANSI styling when set.'
	[FORCE_COLOR]='Requests ANSI styling for non-TTY output when set.'
	[DOTFILES_TUI]='Marks TUI execution for presentation/bridge behavior.'
	[DOTFILES_LOG_RETAIN]='How many timestamped action logs to keep in log/.'
)

declare -A DOTFILES_CONFIG_DEFAULT=(
	[DOTFILES_COMPONENTS]='Unset; interactive selection or all enabled components apply.'
	[XDG_CONFIG_HOME]='$HOME/.config when unset.'
	[GITHUB_TOKEN]='Unset; GitHub API calls remain unauthenticated.'
	[NO_COLOR]='Unset; colors follow TTY/TUI detection.'
	[FORCE_COLOR]='Unset.'
	[DOTFILES_TUI]='Unset for direct commands; set by menu callers when needed.'
	[DOTFILES_LOG_RETAIN]='20 when unset.'
)

declare -A DOTFILES_CONFIG_LOCATION=(
	[DOTFILES_COMPONENTS]='Process environment; comma-separated component IDs.'
	[XDG_CONFIG_HOME]='Process environment; ${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/.'
	[GITHUB_TOKEN]='Process environment or ${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/github.env.'
	[NO_COLOR]='Process environment only.'
	[FORCE_COLOR]='Process environment only.'
	[DOTFILES_TUI]='Process environment only.'
	[DOTFILES_LOG_RETAIN]='Process environment; applied when an action log starts.'
)

DOTFILES_SURFACE_KEYS=(repo links components)
declare -A DOTFILES_SURFACE_DESCRIPTION=(
	[repo]='The Dotfiles repository, package manifests, installers, and logs.'
	[links]='Stow-managed bash, bin, and readline links in the home directory.'
	[components]='Component catalog, package metadata, probes, and selected installers.'
)
declare -A DOTFILES_SURFACE_LOCATION=(
	[repo]='DOTFILES_DIR and its packages/, scripts/, bin/, and log/ directories.'
	[links]='$HOME via GNU Stow packages bash, bin, and readline.'
	[components]='scripts/lib/components/ and packages/packages.txt.'
)

# Validates record content: a known behavior class, non-empty required fields,
# a handler that looks like a command function, and well-formed option rows.
# It no longer has to prove eleven arrays are in step -- dotfiles_command_define
# fills them together -- but it still catches a damaged or incomplete record.
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
		[[ "${DOTFILES_COMMAND_HANDLERS[$key]:-}" =~ ^cmd_[a-z_]+$ ]] || return 1
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
			[[ -n "$line" ]] && {
				printf '%s\n' "$line"
				line=''
			}
			printf '\n'
			continue
		fi
		for word in $paragraph; do
			if [[ -n "$line" && $((${#line} + 1 + ${#word})) -le $width ]]; then
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
	printf '\n  %s%s=== %s ===%s\n' "$C_BOLD" "$C_ORANGE" "$label" "$C_RESET"
}

_dotfiles_command_print_options() {
	local rows="$1" cols="$2"
	local option description default
	while IFS='|' read -r option description default; do
		[[ -n "$option" ]] || continue
		_dotfiles_command_print_token_field "$option" "$description (default: $default)" "$cols"
	done <<<"$rows"
}

_dotfiles_command_print_one() {
	local key="$1" cols="$2"
	_rt_ensure_colors
	printf '  %s%sCommand: %s%s\n' "$C_BOLD" "$C_YELLOW" "$key" "$C_RESET"
	_dotfiles_command_print_field 'Usage' "$(dotfiles_command_display_usage "$key")" "$cols"
	_dotfiles_command_print_field 'Behavior' "${DOTFILES_COMMAND_CLASS[$key]}" "$cols"
	_dotfiles_command_print_field 'Purpose' "${DOTFILES_COMMAND_DESCRIPTION[$key]}" "$cols"
	printf '  %sOptions%s\n' "$C_BOLD" "$C_RESET"
	_dotfiles_command_print_options "${DOTFILES_COMMAND_OPTIONS[$key]}" "$cols"
	_dotfiles_command_print_field 'Defaults' "${DOTFILES_COMMAND_DEFAULTS[$key]}" "$cols"
	_dotfiles_command_print_field 'Effects' "${DOTFILES_COMMAND_EFFECTS[$key]}" "$cols"
	_dotfiles_command_print_field 'Example' "${DOTFILES_COMMAND_EXAMPLES[$key]}" "$cols"
	_dotfiles_command_print_field 'Related' "${DOTFILES_COMMAND_RELATED[$key]}" "$cols"
	[[ -n "${DOTFILES_COMMAND_NOTE[$key]}" ]] &&
		_dotfiles_command_print_field 'Note' "${DOTFILES_COMMAND_NOTE[$key]}" "$cols"
	return 0
}

dotfiles_command_print_detail() {
	local key="$1" cols="${2:-100}"
	dotfiles_command_metadata_validate || return 1
	[[ -n "${DOTFILES_COMMAND_CLASS[$key]+x}" ]] || return 2
	_dotfiles_command_print_section 'Command detail'
	_dotfiles_command_print_one "$key" "$cols"
}

dotfiles_command_print_details() {
	local cols="${1:-100}" key first_command=true
	dotfiles_command_metadata_validate || return 1
	_dotfiles_command_print_section 'Command details'
	for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
		if [[ "$first_command" == true ]]; then
			first_command=false
		else
			printf '\n'
		fi
		_dotfiles_command_print_one "$key" "$cols"
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
	usage_rule="$(printf '%*s' "$usage_w" '')"
	usage_rule="${usage_rule// /-}"
	class_rule="$(printf '%*s' "$class_w" '')"
	class_rule="${class_rule// /-}"
	description_rule="$(printf '%*s' "$description_w" '')"
	description_rule="${description_rule// /-}"
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
