# shellcheck shell=bash
# Cursor-following description footer (2 dim lines) for TUI menus.

_MENU_DESC_LINES=2

menu_desc_lines_count() {
	printf '%s\n' "$_MENU_DESC_LINES"
}

menu_desc_configured() {
	local prefix="$1"
	local descs_var="${prefix}_DESCS"
	local fn_var="${prefix}_DESC_FN"
	local -n _descs="${descs_var}" 2>/dev/null || true

	if [[ -n "${!fn_var:-}" ]] && declare -f "${!fn_var}" >/dev/null 2>&1; then
		return 0
	fi
	if [[ -v "$descs_var" ]] && ((${#_descs[@]} > 0)); then
		return 0
	fi
	return 1
}

menu_desc_footer_rows() {
	if menu_desc_configured "$1"; then
		menu_desc_lines_count
	else
		printf '0\n'
	fi
}

menu_desc_nth_line_fn() {
	local fn="$1"
	local arg="$2"
	local line_index="$3"
	local line=''
	local -a lines=()

	[[ -n "$fn" ]] && declare -f "$fn" >/dev/null 2>&1 || {
		printf '\n'
		return 0
	}

	mapfile -t lines < <("$fn" "$arg")
	if ((line_index < ${#lines[@]})); then
		line="${lines[line_index]}"
	fi
	printf '%s\n' "$line"
}

menu_desc_line() {
	local prefix="$1"
	local idx="$2"
	local line_index="$3"
	local descs_var="${prefix}_DESCS"
	local fn_var="${prefix}_DESC_FN"
	local text=''
	local -a lines=()

	if [[ -n "${!fn_var:-}" ]] && declare -f "${!fn_var}" >/dev/null 2>&1; then
		menu_desc_nth_line_fn "${!fn_var}" "$idx" "$line_index"
		return 0
	fi

	if [[ -v "$descs_var" ]]; then
		local -n _descs="$descs_var"
		text="${_descs[$idx]:-}"
		if [[ -n "$text" ]]; then
			mapfile -t lines <<<"$text"
			if ((line_index < ${#lines[@]})); then
				printf '%s\n' "${lines[line_index]}"
				return 0
			fi
		fi
	fi

	printf '\n'
}

menu_desc_print_footer() {
	local prefix="$1"
	local cursor_idx="$2"
	local cols="$3"
	local desc_idx line_count

	menu_desc_configured "$prefix" || return 0

	line_count="$(menu_desc_lines_count)"
	for ((desc_idx = 0; desc_idx < line_count; desc_idx++)); do
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(menu_fit_indent "$(menu_desc_line "$prefix" "$cursor_idx" "$desc_idx")" "$cols" 2)" \
			"$C_RESET"
	done
}
