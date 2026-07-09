# shellcheck shell=bash
# Shared TUI colors, headers, confirms, and semantic word coloring.
# Depends on: menu_render.sh, tty.sh

# Public palette tokens (C_BLUE/C_INVERT consumed by menu modules).
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
	C_RED=''
	C_BLUE=''
	C_INVERT=''
}

ui_clear() {
	if [[ -t 0 ]]; then
		tput clear 2>/dev/null || printf '\033[2J\033[H' >/dev/tty
	fi
}

ui_pause() {
	local _ui_pause_reply=''
	read_tty_line _ui_pause_reply "Press Enter to continue: "
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

ui_confirm_destructive() {
	local message="$1"
	local answer=''

	printf '\n' >/dev/tty
	printf '  %s%s%s\n' "$C_RED" "$message" "$C_RESET" >/dev/tty
	printf '\n' >/dev/tty
	read_tty_line answer "  ${C_RED}Proceed? [y/N]:${C_RESET} "
	case "$answer" in
	y | Y | yes | YES) return 0 ;;
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

	printf '  %s%s%s\e[K\n' "$C_BOLD" "$(menu_fit_indent "=== ${title} ===" "$cols" 2)" "$C_RESET"
	if [[ -n "$breadcrumb" ]]; then
		printf '  %s%s%s\e[K\n' "$C_DIM" "$(menu_fit_indent "$breadcrumb" "$cols" 2)" "$C_RESET"
	fi
}

ui_print_section() {
	local label="$1"
	local cols="${2:-}"

	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi

	printf '  %s%s%s\e[K\n' "$C_DIM" "$(menu_fit_indent "$label" "$cols" 2)" "$C_RESET"
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

ui_color_result() {
	local result="$1"

	case "$result" in
	ok | installed | configured)
		printf '%s%s%s' "$C_GREEN" "$result" "$C_RESET"
		;;
	missing | failed)
		printf '%s%s%s' "$C_RED" "$result" "$C_RESET"
		;;
	check | drift | extra)
		printf '%s%s%s' "$C_YELLOW" "$result" "$C_RESET"
		;;
	skipped*)
		printf '%s%s%s' "$C_DIM" "$result" "$C_RESET"
		;;
	*)
		printf '%s' "$result"
		;;
	esac
}

# Replace $HOME prefix with ~/ for display.
ui_shorten_path() {
	local path="$1"
	local max="${2:-0}"
	local home="${HOME%/}"
	local len head tail

	if [[ -z "$path" ]]; then
		return 0
	fi

	if [[ "$path" == "$home" ]]; then
		path='~'
	elif [[ "$path" == "$home"/* ]]; then
		path="~${path#$home}"
	fi

	len=${#path}
	if ((max > 0 && len > max)); then
		if ((max <= 3)); then
			printf '%s' "${path:0:max}"
		elif ((max <= 8)); then
			printf '%s...' "${path:0:$((max - 3))}"
		else
			head=$((max / 2 - 1))
			tail=$((max - head - 1))
			printf '%s…%s' "${path:0:head}" "${path: -tail}"
		fi
	else
		printf '%s' "$path"
	fi
}

_ui_status_table_layout() {
	local cols="$1"
	local -n _out_label_w="$2"
	local -n _out_mid_w="$3"
	local -n _out_path_w="$4"

	_out_label_w=22
	_out_mid_w=10
	_out_path_w=$((cols - _out_label_w - _out_mid_w - 9))
	if (( _out_path_w < 28 )); then
		_out_path_w=28
	fi
}

# Agents / health tables: check | result | path
ui_print_check_result_path_row() {
	local label="$1"
	local result="$2"
	local path="${3:-}"
	local cols="${4:-}"
	local label_w mid_w path_w path_display

	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi
	_ui_status_table_layout "$cols" label_w mid_w path_w

	printf '%-*s | ' "$label_w" "$label"
	ui_color_result "$result"
	if [[ -n "$path" ]]; then
		path_display="$(ui_shorten_path "$path" "$path_w")"
		printf ' | %s' "$path_display"
	fi
	printf '\n'
}

ui_print_check_result_path_header() {
	local cols="${1:-}"
	local label_w mid_w path_w

	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi
	_ui_status_table_layout "$cols" label_w mid_w path_w

	printf '%-*s | %-*s | %s\n' "$label_w" "check" "$mid_w" "result" "path"
	printf '%*s-+-%*s-+' "$label_w" '' "$mid_w" ''
	printf '%*s\n' "$path_w" '' | tr ' ' '-'
}

# Two-column status row: label | detail | colored result.
ui_print_status_row() {
	local label="$1"
	local result="$2"
	local detail="${3:-}"
	local cols="${4:-}"
	local label_w detail_w detail_display

	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi
	label_w=22
	detail_w=$((cols - label_w - 10 - 9))
	if ((detail_w < 28)); then
		detail_w=28
	fi

	if [[ -n "$detail" ]]; then
		if [[ "$detail" == /* || "$detail" == ~* ]]; then
			detail_display="$(ui_shorten_path "$detail" "$detail_w")"
		else
			detail_display="$(menu_fit_line "$detail" "$detail_w")"
		fi
		printf '%-*s | %-s | ' "$label_w" "$label" "$detail_display"
	else
		printf '%-*s | ' "$label_w" "$label"
	fi
	ui_color_result "$result"
	printf '\n'
}

ui_print_component_table_row() {
	local short_label="$1"
	local detail="$2"
	local result="$3"
	local cols="${4:-}"
	local label_w detail_w detail_display

	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi
	label_w=22
	detail_w=$((cols - label_w - 10 - 9))
	if ((detail_w < 28)); then
		detail_w=28
	fi

	if [[ "$detail" == /* || "$detail" == ~* ]]; then
		detail_display="$(ui_shorten_path "$detail" "$detail_w")"
	else
		detail_display="$(menu_fit_line "$detail" "$detail_w")"
	fi

	printf '%-*s | %-s | ' "$label_w" "$short_label" "$detail_display"
	ui_color_result "$result"
	printf '\n'
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
