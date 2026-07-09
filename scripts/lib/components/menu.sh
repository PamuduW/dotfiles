# shellcheck shell=bash
# Interactive component selection menu (dependency-aware toggles).

# Non-item rows: ui_print_header(2) + nav hint(1) + page line(2) + status(1) + descriptions.
_COMP_MENU_FIXED_ROWS=$((6 + _COMP_DESC_LINES))

_draw_component_menu() {
	local cur=$1
	local page_size=$2
	local status=$3
	local cols=$4
	local count="${#COMP_KEYS[@]}"
	local page total_pages start end
	local i key mark note row

	page="$(menu_page_for_cursor "$cur" "$page_size")"
	total_pages="$(menu_page_count "$count" "$page_size")"
	read -r start end < <(menu_page_range "$count" "$page_size" "$page")

	ui_print_header "Select Components" "" "$cols"
	printf '  %s%s%s\e[K\n' "$C_DIM" "$(_fit_menu_line_with_indent "Up/Down navigate   Space toggle   a all   n none   Enter confirm   q back" "$cols" 2)" "$C_RESET"
	printf '  %s%s%s\e[K\n\n' "$C_DIM" "$(_fit_menu_line_with_indent "Page $((page + 1))/$total_pages   Showing $((start + 1))-$((end + 1)) of $count" "$cols" 2)" "$C_RESET"

	for ((i = start; i <= end; i++)); do
		key="${COMP_KEYS[$i]}"
		mark="x"
		[[ "${COMP_ON[$key]}" -eq 0 ]] && mark=" "
		note=""
		[[ "${COMP_DEPS[$i]}" -ne -1 ]] && note="  (requires #$((COMP_DEPS[i] + 1)))"
		prefix=' '
		[[ $i -eq $cur ]] && prefix='>'
		row="$(printf '%s%2d. [%s] %s%s' "$prefix" "$((i + 1))" "$mark" "${COMP_LABELS[$i]}" "$note")"

		if [[ $i -eq $cur ]]; then
			if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
				printf '  %s%s%s\e[K\n' "$C_BOLD" "$(_fit_menu_line "$row" "$((cols - 2))")" "$C_RESET"
			else
				printf '  %s%s%s%s\e[K\n' "$C_BOLD" "$C_DIM" "$(_fit_menu_line "$row" "$((cols - 2))")" "$C_RESET"
			fi
		else
			if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
				printf '  %s\e[K\n' "$(_fit_menu_line "$row" "$((cols - 2))")"
			else
				printf '  %s%s%s\e[K\n' "$C_DIM" "$(_fit_menu_line "$row" "$((cols - 2))")" "$C_RESET"
			fi
		fi
	done

	if [[ -n "$status" ]]; then
		printf '  %s%s%s\e[K\n' "$C_YELLOW" "$(_fit_menu_line_with_indent "$status" "$cols" 2)" "$C_RESET"
	else
		printf '\e[K\n'
	fi

	local desc_idx
	for ((desc_idx = 0; desc_idx < _COMP_DESC_LINES; desc_idx++)); do
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(_fit_menu_line_with_indent "$(_comp_description_line "$cur" "$desc_idx")" "$cols" 2)" "$C_RESET"
	done
}

component_menu() {
	local count="${#COMP_KEYS[@]}"
	local cursor=0
	local status_msg=""
	local rows cols page_size menu_lines action page
	local cancelled=false
	local prev_page=-1 prev_lines=0

	rows="$(_menu_tty_rows)"
	cols="$(_menu_tty_cols)"
	page_size="$(menu_page_size "$rows" "$_COMP_MENU_FIXED_ROWS")"
	page="$(menu_page_for_cursor "$cursor" "$page_size")"
	menu_lines="$(menu_page_render_lines "$count" "$page_size" "$page" "$_COMP_MENU_FIXED_ROWS")"

	{
		tput civis 2>/dev/null || true
		_menu_clear_screen
		_draw_component_menu "$cursor" "$page_size" "" "$cols"
		prev_page="$page"
		prev_lines="$menu_lines"

		while true; do
			action="$(_read_component_menu_key)"

			case "$action" in
			up)
				[[ $cursor -gt 0 ]] && cursor=$((cursor - 1))
				status_msg=""
				;;
			down)
				[[ $cursor -lt $((count - 1)) ]] && cursor=$((cursor + 1))
				status_msg=""
				;;
			toggle)
				toggle_component "$cursor"
				status_msg="$TOGGLE_MSG"
				;;
			confirm)
				break
				;;
			cancel)
				cancelled=true
				break
				;;
			all)
				for k in "${COMP_KEYS[@]}"; do COMP_ON["$k"]=1; done
				status_msg="All components enabled"
				;;
			none)
				for k in "${COMP_KEYS[@]}"; do COMP_ON["$k"]=0; done
				status_msg="All components disabled"
				;;
			ignore)
				continue
				;;
			esac

			prev_page="$page"
			prev_lines="$menu_lines"
			page="$(menu_page_for_cursor "$cursor" "$page_size")"
			menu_lines="$(menu_page_render_lines "$count" "$page_size" "$page" "$_COMP_MENU_FIXED_ROWS")"
			menu_redraw_prepare "$prev_lines" "$menu_lines" "$prev_page" "$page"
			_draw_component_menu "$cursor" "$page_size" "$status_msg" "$cols"
		done
		tput cnorm 2>/dev/null || true
	} >/dev/tty

	[[ "$cancelled" == true ]] && return 1
	return 0
}
