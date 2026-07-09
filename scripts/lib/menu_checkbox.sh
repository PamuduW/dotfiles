# shellcheck shell=bash
# Checkbox menu with paging, bulk toggle, and colored status column.

_MENU_CB_FIXED_ROWS=7

_menu_cb_fill_dots() {
	local count="$1"
	local i

	for ((i = 0; i < count; i++)); do
		printf '.'
	done
}

_menu_cb_page_size() {
	local rows="$1"
	local page_size=$((rows - _MENU_CB_FIXED_ROWS))

	((page_size < 1)) && page_size=1
	printf '%s\n' "$page_size"
}

_menu_cb_page_for_cursor() {
	local cursor="$1"
	local page_size="$2"

	printf '%s\n' $((cursor / page_size))
}

_menu_cb_page_count() {
	local count="$1"
	local page_size="$2"

	printf '%s\n' $(((count + page_size - 1) / page_size))
}

_menu_cb_page_range() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local start=$((page * page_size))
	local end=$((start + page_size - 1))

	((end >= count)) && end=$((count - 1))
	printf '%s %s\n' "$start" "$end"
}

_menu_cb_visible_count() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local start end

	read -r start end < <(_menu_cb_page_range "$count" "$page_size" "$page")
	printf '%s\n' $((end - start + 1))
}

_menu_cb_render_lines() {
	local count="$1" page_size="$2" page="$3"
	local visible_count
	visible_count="$(_menu_cb_visible_count "$count" "$page_size" "$page")"
	printf '%s\n' $((visible_count + _MENU_CB_FIXED_ROWS))
}

_menu_cb_status_context() {
	local status="$1"

	case "$status" in
	*backed\ up* | *installed* | *configured* | *up\ to\ date* | ok | OK)
		printf '%s\n' 'ok'
		;;
	*not\ backed* | *upgrade* | *delta* | *warn*)
		printf '%s\n' 'warn'
		;;
	*missing* | *failed* | *error* | *drift* | *extra*)
		printf '%s\n' 'err'
		;;
	*skipped* | '—' | '-')
		printf '%s\n' 'dim'
		;;
	*)
		printf '%s\n' 'info'
		;;
	esac
}

_menu_cb_draw_row() {
	local cur="$1"
	local idx="$2"
	local cols="$3"
	local mark status status_ctx prefix head mid_sep label
	local dots_count max_label checked selected

	mark='x'
	[[ "${MENU_CB_CHECKED[$idx]:-0}" -eq 0 ]] && mark=' '

	status="${MENU_CB_STATUS[$idx]:-}"
	status_ctx="$(_menu_cb_status_context "$status")"
	label="${MENU_CB_LABELS[$idx]}"

	prefix=' '
	[[ $idx -eq $cur ]] && prefix='>'

	checked="${MENU_CB_CHECKED[$idx]:-0}"
	selected=0
	[[ $idx -eq $cur ]] && selected=1

	mid_sep=' · '
	head="$(printf '  %s%2d. [%s]%s' "$prefix" "$((idx + 1))" "$mark" "$mid_sep")"

	dots_count=$((cols - ${#head} - ${#status} - ${#mid_sep} - ${#label}))
	if ((dots_count < 0)); then
		max_label=$((cols - ${#head} - ${#status} - ${#mid_sep} - 3))
		((max_label < 1)) && max_label=1
		label="$(menu_fit_line "$label" "$max_label")"
		dots_count=$((cols - ${#head} - ${#status} - ${#mid_sep} - ${#label}))
	fi
	((dots_count < 0)) && dots_count=0

	if [[ "$checked" -eq 1 ]]; then
		if [[ "$selected" -eq 1 ]]; then
			printf '%s%s%s' "$C_BOLD" "$head" "$C_RESET"
		else
			printf '%s' "$head"
		fi
	else
		if [[ "$selected" -eq 1 ]]; then
			printf '%s%s%s%s' "$C_BOLD" "$C_DIM" "$head" "$C_RESET"
		else
			printf '%s%s%s' "$C_DIM" "$head" "$C_RESET"
		fi
	fi

	ui_color_word "$status" "$status_ctx"
	printf '%s' "$mid_sep"

	if [[ "$checked" -eq 1 ]]; then
		if [[ "$selected" -eq 1 ]]; then
			printf '%s%s%s' "$C_BOLD" "$label" "$C_RESET"
		else
			printf '%s' "$label"
		fi
	else
		if [[ "$selected" -eq 1 ]]; then
			printf '%s%s%s%s' "$C_BOLD" "$C_DIM" "$label" "$C_RESET"
		else
			printf '%s%s%s' "$C_DIM" "$label" "$C_RESET"
		fi
	fi

	if [[ "$checked" -eq 1 ]]; then
		[[ "$selected" -eq 1 ]] && printf '%s' "$C_BOLD"
	else
		printf '%s' "$C_DIM"
	fi
	_menu_cb_fill_dots "$dots_count"
	printf '%s\e[K\n' "$C_RESET"
}

_menu_cb_draw() {
	local cur="$1"
	local page_size="$2"
	local status_msg="$3"
	local cols="$4"
	local count="${#MENU_CB_LABELS[@]}"
	local hint="${MENU_CB_HINT:-Up/Down navigate   Space toggle   a all   n none   Enter confirm   q back}"
	local page total_pages start end
	local i

	page="$(_menu_cb_page_for_cursor "$cur" "$page_size")"
	read -r start end < <(_menu_cb_page_range "$count" "$page_size" "$page")
	total_pages="$(_menu_cb_page_count "$count" "$page_size")"

	ui_print_header "${MENU_CB_TITLE}" "${MENU_CB_BREADCRUMB:-}" "$cols"
	printf '  %s%s%s\e[K\n' "$C_DIM" "$(menu_fit_indent "$hint" "$cols" 2)" "$C_RESET"
	printf '  %s%s%s\e[K\n\n' "$C_DIM" \
		"$(menu_fit_indent "Page $((page + 1))/${total_pages}   Showing $((start + 1))-$((end + 1)) of ${count}" "$cols" 2)" \
		"$C_RESET"

	for ((i = start; i <= end; i++)); do
		_menu_cb_draw_row "$cur" "$i" "$cols"
	done

	if [[ -n "$status_msg" ]]; then
		printf '  %s%s%s\e[K\n' "$C_YELLOW" "$(menu_fit_indent "$status_msg" "$cols" 2)" "$C_RESET"
	else
		printf '\e[K\n'
	fi
}

menu_checkbox_run() {
	local count="${#MENU_CB_LABELS[@]}"
	local cursor=0
	local status_msg=''
	local rows cols page_size page menu_lines action
	local i prev_page=-1 prev_lines=0

	if ((count == 0)); then
		return 1
	fi

	rows="$(menu_tty_rows)"
	cols="$(menu_tty_cols)"
	page_size="$(_menu_cb_page_size "$rows")"

	{
		menu_cursor_hide
		ui_clear
		page="$(_menu_cb_page_for_cursor "$cursor" "$page_size")"
		menu_lines="$(_menu_cb_render_lines "$count" "$page_size" "$page")"
		_menu_cb_draw "$cursor" "$page_size" "" "$cols"
		prev_page="$page"
		prev_lines="$menu_lines"

		while true; do
			action="$(menu_read_key)"

			case "$action" in
			up)
				if ((cursor > 0)); then
					cursor=$((cursor - 1))
					status_msg=''
				fi
				;;
			down)
				if ((cursor < count - 1)); then
					cursor=$((cursor + 1))
					status_msg=''
				fi
				;;
			page_up)
				cursor=$((cursor - page_size))
				((cursor < 0)) && cursor=0
				status_msg=''
				;;
			page_down)
				cursor=$((cursor + page_size))
				((cursor >= count)) && cursor=$((count - 1))
				status_msg=''
				;;
			toggle)
				if [[ "${MENU_CB_CHECKED[cursor]:-0}" -eq 1 ]]; then
					MENU_CB_CHECKED[cursor]=0
				else
					MENU_CB_CHECKED[cursor]=1
				fi
				status_msg=''
				;;
			all)
				for ((i = 0; i < count; i++)); do
					MENU_CB_CHECKED[i]=1
				done
				status_msg='All items selected'
				;;
			none)
				for ((i = 0; i < count; i++)); do
					MENU_CB_CHECKED[i]=0
				done
				status_msg='All items cleared'
				;;
			confirm)
				break
				;;
			cancel)
				menu_cursor_show
				return 1
				;;
			left | right | ignore)
				continue
				;;
			esac

			prev_page="$page"
			prev_lines="$menu_lines"
			page="$(_menu_cb_page_for_cursor "$cursor" "$page_size")"
			menu_lines="$(_menu_cb_render_lines "$count" "$page_size" "$page")"
			menu_redraw_prepare "$prev_lines" "$menu_lines" "$prev_page" "$page"
			_menu_cb_draw "$cursor" "$page_size" "$status_msg" "$cols"
		done

		menu_cursor_show
	} >/dev/tty

	return 0
}
