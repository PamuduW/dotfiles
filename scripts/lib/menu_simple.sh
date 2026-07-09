# shellcheck shell=bash
# Simple numbered-list menu with optional non-selectable section headers.

_menu_simple_is_selectable() {
	local idx="$1"
	[[ "${MENU_SIMPLE_TYPES[$idx]:-}" != "header" ]]
}

_menu_simple_first_selectable() {
	local count="$1"
	local i

	for ((i = 0; i < count; i++)); do
		if _menu_simple_is_selectable "$i"; then
			printf '%s\n' "$i"
			return 0
		fi
	done
	return 1
}

_menu_simple_move_cursor() {
	local cur="$1"
	local dir="$2"
	local count="$3"
	local i="$cur"

	while true; do
		i=$((i + dir))
		if ((i < 0 || i >= count)); then
			printf '%s\n' "$cur"
			return 0
		fi
		if _menu_simple_is_selectable "$i"; then
			printf '%s\n' "$i"
			return 0
		fi
	done
}

_menu_simple_menu_lines() {
	local count="$1"
	local desc_rows footer_rows
	# header (title + trailing blank) + hint + spacer + items + footer blank
	local lines=$((count + 5))

	if [[ -n "${MENU_SIMPLE_BREADCRUMB:-}" ]]; then
		lines=$((count + 6))
	fi

	desc_rows="$(menu_desc_footer_rows MENU_SIMPLE)"
	if ((desc_rows > 0)); then
		footer_rows=1
		lines=$((lines - footer_rows + desc_rows))
	fi
	printf '%s\n' "$lines"
}

_menu_simple_draw() {
	local cur="$1"
	local cols="$2"
	local count="${#MENU_SIMPLE_LABELS[@]}"
	local hint="${MENU_SIMPLE_HINT:-Up/Down navigate   Enter confirm}"
	local i prefix row item_num

	ui_print_header "${MENU_SIMPLE_TITLE}" "${MENU_SIMPLE_BREADCRUMB:-}" "$cols"
	printf '  %s%s%s\e[K\n' "$C_DIM" "$(menu_fit_indent "$hint" "$cols" 2)" "$C_RESET"
	printf '\e[K\n'

	item_num=0
	for ((i = 0; i < count; i++)); do
		if [[ "${MENU_SIMPLE_TYPES[$i]:-}" == "header" ]]; then
			ui_print_section "${MENU_SIMPLE_LABELS[$i]}" "$cols"
			continue
		fi

		item_num=$((item_num + 1))
		prefix=' '
		[[ $i -eq $cur ]] && prefix='>'
		row="$(printf '%s %d. %s' "$prefix" "$item_num" "${MENU_SIMPLE_LABELS[$i]}")"

		if [[ $i -eq $cur ]]; then
			printf '  %s%s%s\e[K\n' "$C_BOLD" "$(menu_fit_line "$row" "$((cols - 2))")" "$C_RESET"
		else
			printf '  %s\e[K\n' "$(menu_fit_line "$row" "$((cols - 2))")"
		fi
	done

	if menu_desc_configured MENU_SIMPLE; then
		menu_desc_print_footer MENU_SIMPLE "$cur" "$cols"
	else
		printf '\e[K\n'
	fi
}

menu_simple_run() {
	local count="${#MENU_SIMPLE_LABELS[@]}"
	local cursor cols menu_lines action

	if ((count == 0)); then
		MENU_SIMPLE_RESULT=''
		return 1
	fi

	cursor="$(_menu_simple_first_selectable "$count")" || {
		MENU_SIMPLE_RESULT=''
		return 1
	}

	cols="$(menu_tty_cols)"
	menu_lines="$(_menu_simple_menu_lines "$count")"

	{
		menu_cursor_hide
		ui_clear
		_menu_simple_draw "$cursor" "$cols"

		while true; do
			action="$(menu_read_key)"

			case "$action" in
			up)
				cursor="$(_menu_simple_move_cursor "$cursor" -1 "$count")"
				;;
			down)
				cursor="$(_menu_simple_move_cursor "$cursor" 1 "$count")"
				;;
			confirm)
				break
				;;
			left | right | toggle | all | none | page_up | page_down | ignore)
				continue
				;;
			cancel)
				menu_cursor_show
				MENU_SIMPLE_RESULT=''
				return 1
				;;
			esac

			menu_redraw_up "$menu_lines"
			_menu_simple_draw "$cursor" "$cols"
		done

		menu_cursor_show
	} >/dev/tty

	MENU_SIMPLE_RESULT="${MENU_SIMPLE_KEYS[$cursor]}"
	printf '%s\n' "$MENU_SIMPLE_RESULT"
}
