# shellcheck shell=bash
# Matrix checkbox: rows = extensions, columns = IDE targets; Tab switches column.

MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
MENU_MX_COL_LABELS=(vscode-wsl vscode-win cursor-wsl cursor-win)

_MENU_MX_COL_COUNT=4
_MENU_MX_COL_WIDTH=18
_MENU_MX_HDR_SEP=$'   ·   '
_MENU_MX_ROW_GAP=$'       '
_MENU_MX_FIXED_ROWS=11

_menu_mx_row_lead_width() {
	local count="$1"
	local index_w

	index_w="$(_menu_mx_index_width "$count")"
	printf '%s\n' $((4 + index_w))
}

_menu_mx_matrix_width() {
	printf '%s\n' $(( _MENU_MX_COL_COUNT * _MENU_MX_COL_WIDTH + (_MENU_MX_COL_COUNT - 1) * ${#_MENU_MX_ROW_GAP} + ${#_MENU_MX_HDR_SEP} ))
}

_menu_mx_ext_column_start() {
	local lead_w="$1"
	printf '%s\n' $((2 + lead_w + _MENU_MX_COL_COUNT * _MENU_MX_COL_WIDTH + (_MENU_MX_COL_COUNT - 1) * ${#_MENU_MX_ROW_GAP} + ${#_MENU_MX_HDR_SEP}))
}

_menu_mx_idx() {
	printf '%s\n' $(( $1 * _MENU_MX_COL_COUNT + $2 ))
}

_menu_mx_index_width() {
	local count="$1"
	local width=2

	((count >= 100)) && width=3
	((count >= 1000)) && width=4
	printf '%s\n' "$width"
}

_menu_mx_page_size() {
	local rows="$1"
	local page_size=$((rows - _MENU_MX_FIXED_ROWS))

	((page_size < 1)) && page_size=1
	printf '%s\n' "$page_size"
}

_menu_mx_page_for_cursor() {
	local cursor="$1"
	local page_size="$2"

	printf '%s\n' $((cursor / page_size))
}

_menu_mx_page_count() {
	local count="$1"
	local page_size="$2"

	printf '%s\n' $(((count + page_size - 1) / page_size))
}

_menu_mx_page_range() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local start=$((page * page_size))
	local end=$((start + page_size - 1))

	((end >= count)) && end=$((count - 1))
	printf '%s %s\n' "$start" "$end"
}

_menu_mx_render_lines() {
	local count="$1" page_size="$2" page="$3"
	local start end

	read -r start end < <(_menu_mx_page_range "$count" "$page_size" "$page")
	printf '%s\n' $((end - start + 1 + _MENU_MX_FIXED_ROWS))
}

_menu_mx_cell_yn() {
	local mode="$1" m="$2" i="$3"

	case "$mode" in
	edit)
		if [[ "$m" -eq 1 ]]; then
			printf 'Y'
		elif [[ "$i" -eq 1 ]]; then
			printf 'N'
		else
			printf '—'
		fi
		;;
	restore | remove)
		if [[ "$i" -eq 1 ]]; then
			printf 'Y'
		elif [[ "$m" -eq 1 || "$mode" == restore ]]; then
			printf 'N'
		else
			printf '—'
		fi
		;;
	*)
		printf '—'
		;;
	esac
}

_menu_mx_cell_glyph() {
	local mode="$1" m="$2" i="$3" chk="$4" store_ok="$5"

	if [[ "$store_ok" -eq 0 ]]; then
		printf '×'
		return
	fi
	if [[ "$mode" == edit && "$m" -eq 0 && "$i" -eq 0 && "$chk" -eq 1 ]]; then
		printf '?'
		return
	fi
	_menu_mx_cell_yn "$mode" "$m" "$i"
}

_menu_mx_cell_color() {
	local mode="$1" glyph="$2" focused="$3"

	case "$glyph" in
	×)
		if [[ "$focused" -eq 1 ]]; then
			ui_color_word "$glyph" err
		else
			ui_color_word "$glyph" dim
		fi
		;;
	?)
		ui_color_word "$glyph" warn
		;;
	Y)
		ui_color_word "$glyph" ok
		;;
	N)
		if [[ "$mode" == edit ]]; then
			ui_color_word "$glyph" warn
		else
			ui_color_word "$glyph" dim
		fi
		;;
	*)
		ui_color_word "$glyph" dim
		;;
	esac
}

_menu_mx_draw_cell() {
	local row="$1" col="$2" cur_row="$3" cur_col="$4" row_inverted="$5"
	local idx m i chk store_ok glyph mark mode="${MENU_MX_MODE:-edit}"
	local cell_body

	idx="$(_menu_mx_idx "$row" "$col")"
	m="${MENU_MX_MANIFEST[$idx]:-0}"
	i="${MENU_MX_INSTALLED[$idx]:-0}"
	chk="${MENU_MX_CHECKED[$idx]:-0}"
	store_ok="${MENU_MX_STORE_OK[$idx]:-1}"
	glyph="$(_menu_mx_cell_glyph "$mode" "$m" "$i" "$chk" "$store_ok")"
	mark=' '
	[[ "$chk" -eq 1 && "$store_ok" -eq 1 ]] && mark='x'

	cell_body="$(printf '%s  [%s]' "$glyph" "$mark")"
	if [[ "$row_inverted" -eq 1 ]]; then
		printf '%-*s' "$_MENU_MX_COL_WIDTH" "$cell_body"
	else
		_menu_mx_cell_color "$mode" "$glyph" 0
		printf '  [%s]' "$mark"
		printf '%*s' $((_MENU_MX_COL_WIDTH - 6)) ''
	fi
	[[ "$col" -lt $((_MENU_MX_COL_COUNT - 1)) ]] && printf '%s' "$_MENU_MX_ROW_GAP"
}

_menu_mx_print_glyph_key() {
	local cols="$1"
	local mode="${MENU_MX_MODE:-edit}"

	case "$mode" in
	edit)
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(menu_fit_indent "Y in manifest   N installed, not backed up   — not present" "$cols" 2)" \
			"$C_RESET"
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(menu_fit_indent "? add to manifest (may fail on restore)   × wrong IDE store" "$cols" 2)" \
			"$C_RESET"
		;;
	restore)
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(menu_fit_indent "Y installed   N missing (in manifest, will install)   — n/a   × wrong IDE store (skipped)" "$cols" 2)" \
			"$C_RESET"
		;;
	remove)
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(menu_fit_indent "Y extra installed (not in manifest)   — not an extra here   × wrong IDE store" "$cols" 2)" \
			"$C_RESET"
		;;
	esac
}

_menu_mx_draw_col_header() {
	local c="$1" cur_col="$2"
	local label

	label="${MENU_MX_COL_LABELS[$c]:-${MENU_MX_COL_KEYS[$c]}}"
	if [[ "$c" -eq "$cur_col" ]]; then
		printf '%s%s%-*s%s' "$C_INVERT" "$C_BLUE" "$_MENU_MX_COL_WIDTH" "$label" "$C_RESET"
	else
		printf '%s%-*s%s' "$C_BLUE" "$_MENU_MX_COL_WIDTH" "$label" "$C_RESET"
	fi
	[[ "$c" -lt $((_MENU_MX_COL_COUNT - 1)) ]] && printf '%s' "$_MENU_MX_HDR_SEP"
}

_menu_mx_draw_headers() {
	local cur_col="$1" cols="$2" c lead_w

	lead_w="$(_menu_mx_row_lead_width "${#MENU_MX_ROWS[@]}")"
	printf '  %*s' "$lead_w" ''
	for ((c = 0; c < _MENU_MX_COL_COUNT; c++)); do
		_menu_mx_draw_col_header "$c" "$cur_col"
	done
	printf '%s' "$_MENU_MX_HDR_SEP"
	printf '%s%sextension%s' "$C_BLUE" '' "$C_RESET"
	printf '\e[K\n'
}

_menu_mx_draw_row() {
	local cur_row="$1" cur_col="$2" idx="$3" cols="$4"
	local prefix index_w label max_label c lead_w ext_start row_inverted=0
	local row_prefix_len printed_len

	prefix='  '
	[[ "$idx" -eq "$cur_row" ]] && prefix='> '
	[[ "$idx" -eq "$cur_row" ]] && row_inverted=1

	index_w="$(_menu_mx_index_width "${#MENU_MX_ROWS[@]}")"
	lead_w="$(_menu_mx_row_lead_width "${#MENU_MX_ROWS[@]}")"
	ext_start="$(_menu_mx_ext_column_start "$lead_w")"

	if [[ "$row_inverted" -eq 1 ]]; then
		printf '%s' "$C_INVERT"
	fi

	printf '  '
	printf '%s%*d. ' "$prefix" "$index_w" "$((idx + 1))"

	for ((c = 0; c < _MENU_MX_COL_COUNT; c++)); do
		_menu_mx_draw_cell "$idx" "$c" "$cur_row" "$cur_col" "$row_inverted"
	done

	label="${MENU_MX_LABELS[$idx]}"
	row_prefix_len=$((2 + ${#prefix} + index_w + 2 + _MENU_MX_COL_COUNT * _MENU_MX_COL_WIDTH + (_MENU_MX_COL_COUNT - 1) * ${#_MENU_MX_ROW_GAP}))
	max_label=$((cols - ext_start - 2))
	((max_label < 12)) && max_label=12
	if ((${#label} > max_label)); then
		label="$(menu_fit_line "$label" "$max_label")"
	fi

	printed_len=$row_prefix_len
	if ((printed_len < ext_start)); then
		printf '%*s' $((ext_start - printed_len)) ''
	fi
	printf '%s' "$label"

	if [[ "$row_inverted" -eq 1 ]]; then
		printf '%s' "$C_RESET"
	fi
	printf '\e[K\n'
}

_menu_mx_draw() {
	local cur_row="$1"
	local cur_col="$2"
	local page_size="$3"
	local status_msg="$4"
	local cols="$5"
	local count="${#MENU_MX_ROWS[@]}"
	local hint="${MENU_MX_HINT:-↑↓ row   Tab column   Space toggle   Enter confirm   q back}"
	local page total_pages start end i

	page="$(_menu_mx_page_for_cursor "$cur_row" "$page_size")"
	read -r start end < <(_menu_mx_page_range "$count" "$page_size" "$page")
	total_pages="$(_menu_mx_page_count "$count" "$page_size")"

	ui_print_header "${MENU_MX_TITLE}" "${MENU_MX_BREADCRUMB:-}" "$cols"
	printf '  %s%s%s\e[K\n' "$C_DIM" "$(menu_fit_indent "$hint" "$cols" 2)" "$C_RESET"
	_menu_mx_print_glyph_key "$cols"
	printf '  %s%s%s\e[K\n\n' "$C_DIM" \
		"$(menu_fit_indent "Page $((page + 1))/${total_pages}   Showing $((start + 1))-$((end + 1)) of ${count}" "$cols" 2)" \
		"$C_RESET"
	_menu_mx_draw_headers "$cur_col" "$cols"

	for ((i = start; i <= end; i++)); do
		_menu_mx_draw_row "$cur_row" "$cur_col" "$i" "$cols"
	done

	if [[ -n "$status_msg" ]]; then
		printf '  %s%s%s\e[K\n' "$C_YELLOW" "$(menu_fit_indent "$status_msg" "$cols" 2)" "$C_RESET"
	else
		printf '\e[K\n'
	fi
}

menu_matrix_run() {
	local count="${#MENU_MX_ROWS[@]}"
	local row=0 col=0
	local status_msg=''
	local rows cols page_size page menu_lines action
	local i prev_page=-1 prev_lines=0 idx

	((count == 0)) && return 1

	rows="$(menu_tty_rows)"
	cols="$(menu_tty_cols)"
	page_size="$(_menu_mx_page_size "$rows")"

	{
		menu_cursor_hide
		ui_clear
		page="$(_menu_mx_page_for_cursor "$row" "$page_size")"
		menu_lines="$(_menu_mx_render_lines "$count" "$page_size" "$page")"
		_menu_mx_draw "$row" "$col" "$page_size" "" "$cols"
		prev_page="$page"
		prev_lines="$menu_lines"

		while true; do
			action="$(menu_read_key)"

			case "$action" in
			up)
				if ((row > 0)); then
					row=$((row - 1))
					status_msg=''
				fi
				;;
			down)
				if ((row < count - 1)); then
					row=$((row + 1))
					status_msg=''
				fi
				;;
			tab | right)
				col=$(( (col + 1) % _MENU_MX_COL_COUNT ))
				status_msg=''
				;;
			shift_tab | left)
				col=$(( (col + _MENU_MX_COL_COUNT - 1) % _MENU_MX_COL_COUNT ))
				status_msg=''
				;;
			toggle)
				idx="$(_menu_mx_idx "$row" "$col")"
				if [[ "${MENU_MX_STORE_OK[$idx]:-0}" -eq 0 ]]; then
					status_msg='× incompatible with this IDE store'
				elif ext_matrix_toggle_cell "$row" "$col"; then
					status_msg=''
				else
					status_msg='Cell not toggleable'
				fi
				;;
			all | none)
				status_msg=''
				;;
			page_up)
				row=$((row - page_size))
				((row < 0)) && row=0
				status_msg=''
				;;
			page_down)
				row=$((row + page_size))
				((row >= count)) && row=$((count - 1))
				status_msg=''
				;;
			confirm)
				break
				;;
			cancel)
				menu_cursor_show
				return 1
				;;
			*)
				continue
				;;
			esac

			prev_page="$page"
			prev_lines="$menu_lines"
			page="$(_menu_mx_page_for_cursor "$row" "$page_size")"
			menu_lines="$(_menu_mx_render_lines "$count" "$page_size" "$page")"
			menu_redraw_prepare "$prev_lines" "$menu_lines" "$prev_page" "$page"
			_menu_mx_draw "$row" "$col" "$page_size" "$status_msg" "$cols"
		done

		menu_cursor_show
	} >/dev/tty

	return 0
}
