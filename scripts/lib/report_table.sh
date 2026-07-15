# shellcheck shell=bash
# Shared report table design system (component | detail | result).
# Safe to source from dotfiles menus (via ui.sh) or bin/dotfiles standalone.

_RT_LABEL_W=22
_RT_DETAIL_W=40
_RT_RESULT_W=10

_rt_ensure_colors() {
	if [[ -n "${C_RESET:-}" ]]; then
		return 0
	fi
	if [[ -z "${NO_COLOR:-}" ]] && { [[ -t 1 ]] || [[ -t 0 ]] || [[ -n "${FORCE_COLOR:-}" ]]; }; then
		C_RESET=$'\033[0m'
		C_BOLD=$'\033[1m'
		C_DIM=$'\033[2m'
		C_GREEN=$'\033[32m'
		C_YELLOW=$'\033[33m'
		C_ORANGE=$'\033[38;5;208m'
		C_RED=$'\033[31m'
		C_CYAN=$'\033[36m'
	else
		C_RESET=''
		C_BOLD=''
		C_DIM=''
		C_GREEN=''
		C_YELLOW=''
		C_ORANGE=''
		C_RED=''
		C_CYAN=''
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
		path="~${path#$home}"
	fi
	if ((max > 0 && ${#path} > max)); then
		if ((max <= 8)); then
			printf '%s...' "${path:0:$((max - 3))}"
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
	elif ((max <= 3)); then
		printf '%s' "${text:0:max}"
	else
		printf '%s...' "${text:0:$((max - 3))}"
	fi
}

_rt_color_result() {
	local result="$1"

	_rt_ensure_colors
	case "$result" in
	ok | installed | configured | linked | up\ to\ date | current)
		printf '%s%s%s' "$C_GREEN" "$result" "$C_RESET"
		;;
	missing | failed | error)
		printf '%s%s%s' "$C_RED" "$result" "$C_RESET"
		;;
	check | drift | extra | warn | warning | partial)
		printf '%s%s%s' "$C_YELLOW" "$result" "$C_RESET"
		;;
	skipped*)
		printf '%s%s%s' "$C_DIM" "$result" "$C_RESET"
		;;
	info | dry-run)
		printf '%s%s%s' "$C_CYAN" "$result" "$C_RESET"
		;;
	*)
		printf '%s' "$result"
		;;
	esac
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

# Blank line, section title, blank line, then column header — easier to scan than one long table.
rt_print_section_block() {
	local label="$1"

	printf '\n'
	rt_print_section "$label"
	printf '\n'
	rt_print_table_columns
}

rt_print_table_columns() {
	local label_rule detail_rule result_rule
	printf -v label_rule '%*s' "$_RT_LABEL_W" ''
	printf -v detail_rule '%*s' "$_RT_DETAIL_W" ''
	printf -v result_rule '%*s' "$_RT_RESULT_W" ''
	label_rule="${label_rule// /-}"
	detail_rule="${detail_rule// /-}"
	result_rule="${result_rule// /-}"

	_rt_ensure_colors
	printf '  %s%-*s | %-*s | %s%s\n' \
		"$C_BOLD" "$_RT_LABEL_W" "component" "$_RT_DETAIL_W" "detail" "result" "$C_RESET"
	printf '  %s-+-%s-+-%s\n' "$label_rule" "$detail_rule" "$result_rule"
}

rt_print_table_row() {
	local component="$1"
	local detail="$2"
	local result="$3"
	local detail_fit

	_rt_ensure_colors
	if [[ "$detail" == /* || "$detail" == ~* ]]; then
		detail_fit="$(_rt_shorten_path "$detail" "$_RT_DETAIL_W")"
	else
		detail_fit="$(_rt_fit_line "$detail" "$_RT_DETAIL_W")"
	fi
	printf '  %-*s | %-*s | ' "$_RT_LABEL_W" "$component" "$_RT_DETAIL_W" "$detail_fit"
	_rt_color_result "$result"
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
