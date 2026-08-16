# shellcheck shell=bash
# Shared TUI colors, headers, confirms, and semantic word coloring.
# Depends on: menu_render.sh, tty.sh

# Public palette tokens (C_ORANGE, C_YELLOW, C_BLUE, and C_INVERT are
# consumed by menu modules).
# shellcheck disable=SC2034
ui_init_colors() {
	if [[ -z "${NO_COLOR:-}" ]]; then
		C_RESET=$'\e[0m'
		C_BOLD=$'\e[1m'
		C_DIM=$'\e[2m'
		C_MAGENTA=$'\e[35m'
		C_CYAN=$'\e[36m'
		C_GREEN=$'\e[32m'
		C_YELLOW=$'\e[33m'
		C_ORANGE=$'\e[38;5;208m'
		C_RED=$'\e[31m'
		C_BLUE=$'\e[34m'
		C_INVERT=$'\e[7m'
		return 0
	fi

	C_RESET=''
	C_BOLD=''
	C_DIM=''
	C_MAGENTA=''
	C_CYAN=''
	C_GREEN=''
	C_YELLOW=''
	C_ORANGE=''
	C_RED=''
	C_BLUE=''
	C_INVERT=''
}

ui_clear() {
	if [[ -t 0 ]]; then
		tput clear 2>/dev/null || tty_printf '\033[2J\033[H'
	fi
}

ui_pause() {
	local _ui_pause_reply=''
	tty_printf '\n'
	read_tty_line _ui_pause_reply "${C_YELLOW:-}Press Enter to continue:${C_RESET:-} "
}

ui_confirm_yes_no() {
	local prompt="$1"
	local default_no="${2:-true}"
	local answer=''

	if [[ "$default_no" == "true" ]]; then
		read_tty_line answer "${prompt} [y/N]: "
		case "$answer" in
		y | Y | yes | YES) return 0 ;;
		*) return 1 ;;
		esac
	fi

	read_tty_line answer "${prompt} [Y/n]: "
	case "$answer" in
	'' | y | Y | yes | YES) return 0 ;;
	*) return 1 ;;
	esac
}

ui_print_header() {
	local title="$1"
	local breadcrumb="${2:-}"
	local cols="${3:-}"

	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi

	printf '  %s%s%s%s\e[K\n' "$C_BOLD" "$C_ORANGE" "$(menu_fit_indent "=== ${title} ===" "$cols" 2)" "$C_RESET"
	if [[ -n "$breadcrumb" ]]; then
		printf '  %s%s%s\e[K\n' "$C_DIM" "$(menu_fit_indent "$breadcrumb" "$cols" 2)" "$C_RESET"
	fi
	printf '\e[K\n'
}

ui_print_section() {
	local label="$1"
	local cols="${2:-}"

	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi

	printf '  %s%s%s%s\e[K\n' "$C_BOLD" "$C_YELLOW" "$(menu_fit_indent "$label" "$cols" 2)" "$C_RESET"
}

ui_color_input_hint() {
	local hint="$1"
	local cyan="${C_CYAN:-}" reset="${C_RESET:-}" dim="${C_DIM:-}"
	local key_start="${reset}${cyan}" key_end="${reset}${dim}"
	hint="${hint//Up\/Down/${key_start}Up\/Down${key_end}}"
	hint="${hint//Space toggle/${key_start}Space${key_end} toggle}"
	hint="${hint//Enter confirm/${key_start}Enter${key_end} confirm}"
	hint="${hint//Enter system package details/${key_start}Enter${key_end} system package details}"
	hint="${hint//\[c\]onfirm/${key_start}[c]${key_end}onfirm}"
	hint="${hint//\[e\]dit/${key_start}[e]${key_end}dit}"
	hint="${hint//\[q\] back/${key_start}[q]${key_end} back}"
	hint="${hint//\[c\] confirm/${key_start}[c]${key_end} confirm}"
	hint="${hint//\[e\] edit/${key_start}[e]${key_end} edit}"
	hint="${hint//\[q\] back_to_menu/${key_start}[q]${key_end} back_to_menu}"
	hint="${hint//   a all/   ${key_start}a${key_end} all}"
	hint="${hint//   n none/   ${key_start}n${key_end} none}"
	hint="${hint//   q back/   ${key_start}q${key_end} back}"
	printf '%s' "$hint"
}

ui_format_shortcuts() {
	local key label first=true
	(($# > 0 && $# % 2 == 0)) || return 2
	while (($#)); do
		key="$1"
		label="$2"
		shift 2
		[[ "$first" == true ]] || printf '   '
		printf '%s%s%s %s' "${C_CYAN:-}" "$key" "${C_RESET:-}" "$label"
		first=false
	done
}

ui_install_confirm_prompt() {
	printf '  %s : %s' "$(ui_format_shortcuts c confirm e edit q back_to_menu)" "${C_RESET:-}"
}

ui_color_word() {
	local word="$1"
	local context="$2"

	case "$context" in
	ok)
		printf '%s%s%s' "$C_GREEN" "$word" "$C_RESET"
		;;
	warn)
		printf '%s%s%s' "$C_YELLOW" "$word" "$C_RESET"
		;;
	err)
		printf '%s%s%s' "$C_RED" "$word" "$C_RESET"
		;;
	info)
		printf '%s%s%s' "$C_CYAN" "$word" "$C_RESET"
		;;
	dim)
		printf '%s%s%s' "$C_DIM" "$word" "$C_RESET"
		;;
	*)
		printf '%s' "$word"
		;;
	esac
}

# Execution plan row: enabled components in normal text, skipped in dim.
ui_print_plan_row() {
	local label="$1"
	local detail="$2"
	local active="$3"

	printf '  %-18s: ' "$label"
	if [[ "$active" -eq 1 ]]; then
		printf '%s\n' "$detail"
	else
		ui_color_word "$detail" "dim"
		printf '\n'
	fi
}

# Report tables — shared design system (see scripts/lib/report_table.sh).
ui_print_report_header() { rt_print_header "$@"; }
ui_print_report_table_columns() { rt_print_table_columns; }
ui_print_report_table_row() { rt_print_table_row "$@"; }
ui_print_report_rollup() { rt_print_rollup "$@"; }
