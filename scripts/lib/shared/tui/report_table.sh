# shellcheck shell=bash
# shellcheck disable=SC2034,SC2178  # Width arrays are populated through namerefs.
if ! declare -F colors_set_palette >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/shared/tui/colors.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/colors.sh"
fi
# Shared report table design system (component | detail | result).
# Safe to source from dotfiles menus (via ui.sh) or bin/dotfiles standalone.

_rt_ensure_colors() {
	if [[ -n "${NO_COLOR:-}" ]]; then
		colors_clear_palette
		return 0
	fi
	# Respect a palette the caller already installed (tests do this), but make
	# sure every token exists so `set -u` callers can read the whole palette.
	if [[ -n "${C_RESET:-}" ]]; then
		colors_complete_palette
		return 0
	fi
	if [[ -z "${NO_COLOR:-}" ]] && { [[ -t 1 ]] || [[ -t 0 ]] || [[ -n "${FORCE_COLOR:-}" ]]; }; then
		colors_set_palette
	else
		colors_clear_palette
	fi
}

_rt_shorten_path() {
	local path="$1"
	local max="${2:-0}"
	local home="${HOME%/}"

	if [[ -z "$path" ]]; then
		return 0
	fi
	if [[ "$path" == "$home" ]]; then
		path='~'
	elif [[ "$path" == "$home"/* ]]; then
		path="~${path#"$home"}"
	fi
	if ((max > 0 && ${#path} > max)); then
		if ((max <= 8)); then
			printf '%s…' "${path:0:$((max - 1))}"
		else
			local head=$((max / 2 - 1))
			local tail=$((max - head - 1))
			printf '%s…%s' "${path:0:head}" "${path: -tail}"
		fi
	else
		printf '%s' "$path"
	fi
}

_rt_fit_line() {
	local text="$1"
	local max="$2"

	if ((${#text} <= max)); then
		printf '%s' "$text"
	elif ((max <= 1)); then
		printf '%s' "${text:0:max}"
	else
		printf '%s…' "${text:0:$((max - 1))}"
	fi
}

rt_report_columns() {
	local cols="${DOTFILES_REPORT_COLS:-}"
	if [[ ! "$cols" =~ ^[0-9]+$ ]] && declare -F menu_tty_cols >/dev/null 2>&1; then
		cols="$(menu_tty_cols)"
	fi
	if [[ ! "$cols" =~ ^[0-9]+$ && "${COLUMNS:-}" =~ ^[0-9]+$ ]]; then
		cols="$COLUMNS"
	fi
	if [[ ! "$cols" =~ ^[0-9]+$ ]] && { [[ -t 1 ]] || [[ -t 0 ]]; }; then
		cols="$(tput cols 2>/dev/null || true)"
	fi
	[[ "$cols" =~ ^[0-9]+$ ]] || cols=80
	((cols < 32)) && cols=32
	printf '%s\n' "$cols"
}

_rt_three_column_widths() {
	local output_name="$1" available label result detail
	local -n widths_ref="$output_name"
	available=$(($(rt_report_columns) - 8))
	label=$((available * 30 / 100))
	result=$((available * 14 / 100))
	((label < 10)) && label=10
	((result < 7)) && result=7
	detail=$((available - label - result))
	widths_ref=("$label" "$detail" "$result")
}

rt_four_column_widths() {
	local output_name="$1" available w1 w2 w3 w4
	local -n widths_ref="$output_name"
	available=$(($(rt_report_columns) - 9))
	if ((available >= 55)); then
		w4=18
	else
		w4=$((available * 25 / 100))
	fi
	w1=$(((available - w4) * 25 / 100))
	w2=$(((available - w4) * 42 / 100))
	w3=$((available - w1 - w2 - w4))
	widths_ref=("$w1" "$w2" "$w3" "$w4")
}

_rt_rule() {
	local width="$1" rule
	printf -v rule '%*s' "$width" ''
	printf '%s' "${rule// /-}"
}

_rt_print_fixed_cell() {
	local text="$1" width="$2" color_fn="${3:-}" fit padding
	fit="$(_rt_fit_line "$text" "$width")"
	if [[ -n "$color_fn" ]]; then
		"$color_fn" "$fit"
	else
		printf '%s' "$fit"
	fi
	padding=$((width - ${#fit}))
	((padding > 0)) && printf '%*s' "$padding" ''
	return 0
}

rt_print_four_column_header() {
	local w1="$1" h1="$2" w2="$3" h2="$4" w3="$5" h3="$6" w4="$7" h4="$8"
	_rt_ensure_colors
	printf '%s' "$C_BOLD"
	_rt_print_fixed_cell "$h1" "$w1"
	printf ' | '
	_rt_print_fixed_cell "$h2" "$w2"
	printf ' | '
	_rt_print_fixed_cell "$h3" "$w3"
	printf ' | '
	_rt_print_fixed_cell "$h4" "$w4"
	printf '%s\n' "$C_RESET"
	printf '%s%s-+-%s-+-%s-+-%s%s\n' "$C_DIM" "$(_rt_rule "$w1")" "$(_rt_rule "$w2")" "$(_rt_rule "$w3")" "$(_rt_rule "$w4")" "$C_RESET"
}

rt_print_four_column_row() {
	local w1="$1" t1="$2" w2="$3" t2="$4" w3="$5" t3="$6" w4="$7" t4="$8"
	local color3="${9:-}" color4="${10:-}"
	_rt_print_fixed_cell "$t1" "$w1"
	printf ' | '
	_rt_print_fixed_cell "$t2" "$w2"
	printf ' | '
	_rt_print_fixed_cell "$t3" "$w3" "$color3"
	printf ' | '
	_rt_print_fixed_cell "$t4" "$w4" "$color4"
	printf '\n'
}

_rt_color_result() {
	_rt_ensure_colors
	status_color_result "$1"
}

# Match ui_print_header when menu_render is unavailable.
rt_print_header() {
	local title="$1"
	local breadcrumb="${2:-}"

	_rt_ensure_colors
	printf '\n'
	printf '  %s%s=== %s ===%s\n' "$C_BOLD" "$C_ORANGE" "$title" "$C_RESET"
	if [[ -n "$breadcrumb" ]]; then
		printf '  %s%s%s\n' "$C_DIM" "$breadcrumb" "$C_RESET"
	fi
	printf '\n'
}

rt_print_section() {
	local label="$1"

	_rt_ensure_colors
	printf '  %s%s%s%s\n' "$C_BOLD" "$C_YELLOW" "$label" "$C_RESET"
}

rt_print_table_columns() {
	local label_rule detail_rule result_rule
	local -a widths=()
	_rt_three_column_widths widths
	local label_width="${widths[0]}" detail_width="${widths[1]}" result_width="${widths[2]}"
	printf -v label_rule '%*s' "$label_width" ''
	printf -v detail_rule '%*s' "$detail_width" ''
	printf -v result_rule '%*s' "$result_width" ''
	label_rule="${label_rule// /-}"
	detail_rule="${detail_rule// /-}"
	result_rule="${result_rule// /-}"

	_rt_ensure_colors
	printf '  %s' "$C_BOLD"
	_rt_print_fixed_cell component "$label_width"
	printf ' | '
	_rt_print_fixed_cell detail "$detail_width"
	printf ' | '
	_rt_print_fixed_cell result "$result_width"
	printf '%s\n' "$C_RESET"
	printf '  %s-+-%s-+-%s\n' "$label_rule" "$detail_rule" "$result_rule"
}

rt_print_table_row() {
	local component="$1"
	local detail="$2"
	local result="$3"
	local detail_fit
	local -a widths=()
	_rt_three_column_widths widths
	local label_width="${widths[0]}" detail_width="${widths[1]}" result_width="${widths[2]}"

	_rt_ensure_colors
	if [[ "$detail" == /* || "$detail" == ~* ]]; then
		detail_fit="$(_rt_shorten_path "$detail" "$detail_width")"
	else
		detail_fit="$(_rt_fit_line "$detail" "$detail_width")"
	fi
	printf '  '
	_rt_print_fixed_cell "$component" "$label_width"
	printf ' | '
	_rt_print_fixed_cell "$detail_fit" "$detail_width"
	printf ' | '
	_rt_print_fixed_cell "$result" "$result_width" _rt_color_result
	printf '\n'
}

rt_print_rollup() {
	local ok_count="${1:-0}"
	local check_count="${2:-0}"
	local miss_count="${3:-0}"

	_rt_ensure_colors
	printf '\n'
	if [[ "$miss_count" -eq 0 && "$check_count" -eq 0 ]]; then
		printf '  %sAll %d component(s) look good.%s\n' "$C_GREEN" "$ok_count" "$C_RESET"
	elif [[ "$miss_count" -eq 0 ]]; then
		printf '  %s%d ok%s, %s%d need attention%s.\n' \
			"$C_GREEN" "$ok_count" "$C_RESET" \
			"$C_YELLOW" "$check_count" "$C_RESET"
	else
		printf '  %s%d ok%s, %s%d missing%s, %s%d need attention%s.\n' \
			"$C_GREEN" "$ok_count" "$C_RESET" \
			"$C_RED" "$miss_count" "$C_RESET" \
			"$C_YELLOW" "$check_count" "$C_RESET"
	fi
}
