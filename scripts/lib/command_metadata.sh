# shellcheck shell=bash
# shellcheck disable=SC2034  # Public metadata arrays are consumed by sourced callers.
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

dotfiles_command_metadata_validate() {
	local -A seen=()
	local key class

	for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
		[[ -n "$key" && -z "${seen[$key]+x}" ]] || return 1
		seen["$key"]=1
		class="${DOTFILES_COMMAND_CLASS[$key]:-}"
		[[ "$class" == read-only || "$class" == mutating ]] || return 1
		[[ -n "${DOTFILES_COMMAND_DESCRIPTION[$key]:-}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_USAGE[$key]+x}" ]] || return 1
		[[ -n "${DOTFILES_COMMAND_NOTE[$key]+x}" ]] || return 1
	done
	[[ "${#seen[@]}" -eq 7 ]]
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

dotfiles_command_print_table() {
	local cols="${1:-100}"
	local usage_w=20 class_w=10 description_w available
	local key usage description usage_fit class_fit description_fit

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
