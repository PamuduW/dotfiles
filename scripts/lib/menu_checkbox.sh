# shellcheck shell=bash
# Checkbox menu with paging, bulk toggle, and colored status column.

_MENU_CB_STATUS_WIDTH=16
_MENU_CB_FIXED_ROWS=7

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
	local count="$1"
	local page_size="$2"
	local page="$3"
	local visible_count

	visible_count="$(_menu_cb_visible_count "$count" "$page_size" "$page")"
	menu_count_lines 4 "$visible_count" 1
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
	*missing* | *failed* | *error* | *drift*)
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

_menu_cb_draw() {
	local cur="$1"
	local page_size="$2"
	local status_msg="$3"
	local cols="$4"
	local count="${#MENU_CB_LABELS[@]}"
	local hint="${MENU_CB_HINT:-Up/Down navigate   Space toggle   a all   n none   Enter confirm}"
	local page total_pages start end
	local i prefix mark label_part status status_ctx
	local label_width fitted_label fitted_status

	page="$(_menu_cb_page_for_cursor "$cur" "$page_size")"
	read -r start end < <(_menu_cb_page_range "$count" "$page_size" "$page")
	total_pages="$(_menu_cb_page_count "$count" "$page_size")"

	ui_print_header "${MENU_CB_TITLE}" "${MENU_CB_BREADCRUMB:-}" "$cols"
	printf '  %s%s%s\e[K\n' "$C_DIM" "$(menu_fit_indent "$hint" "$cols" 2)" "$C_RESET"
	printf '  %s%s%s\e[K\n\n' "$C_DIM" \
		"$(menu_fit_indent "Page $((page + 1))/${total_pages}   Showing $((start + 1))-$((end + 1)) of ${count}" "$cols" 2)" \
		"$C_RESET"

	label_width=$((cols - _MENU_CB_STATUS_WIDTH - 1))
	((label_width < 1)) && label_width=1

	for ((i = start; i <= end; i++)); do
		prefix=' '
		[[ $i -eq $cur ]] && prefix='>'
		mark='x'
		[[ "${MENU_CB_CHECKED[$i]:-0}" -eq 0 ]] && mark=' '

		label_part="$(printf '%s %2d. [%s] %s' "$prefix" "$((i + 1))" "$mark" "${MENU_CB_LABELS[$i]}")"
		status="${MENU_CB_STATUS[$i]:-}"
		status_ctx="$(_menu_cb_status_context "$status")"
		fitted_label="$(menu_fit_line "$label_part" "$label_width")"
		fitted_status="$(menu_fit_line "$status" "$_MENU_CB_STATUS_WIDTH")"

		if [[ $i -eq $cur ]]; then
			printf '%s%-*s%s' "$C_INVERT" "$label_width" "$fitted_label" "$C_RESET"
			printf ' '
			ui_color_word "$fitted_status" "$status_ctx"
			printf '\e[K\n'
		else
			printf '%-*s ' "$label_width" "$fitted_label"
			ui_color_word "$fitted_status" "$status_ctx"
			printf '\e[K\n'
		fi
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
	local i

	if ((count == 0)); then
		return 1
	fi

	rows="$(menu_tty_rows)"
	cols="$(menu_tty_cols)"
	page_size="$(_menu_cb_page_size "$rows")"
	page="$(_menu_cb_page_for_cursor "$cursor" "$page_size")"
	menu_lines="$(_menu_cb_render_lines "$count" "$page_size" "$page")"

	{
		menu_cursor_hide
		ui_clear
		_menu_cb_draw "$cursor" "$page_size" "" "$cols"

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
				menu_cursor_show
				return 0
				;;
			cancel)
				menu_cursor_show
				return 1
				;;
			left | right | ignore)
				continue
				;;
			esac

			menu_redraw_up "$menu_lines"
			_menu_cb_draw "$cursor" "$page_size" "$status_msg" "$cols"
			page="$(_menu_cb_page_for_cursor "$cursor" "$page_size")"
			menu_lines="$(_menu_cb_render_lines "$count" "$page_size" "$page")"
		done
	} >/dev/tty
}
