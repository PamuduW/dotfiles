# shellcheck shell=bash
# Terminal geometry, line fitting, cursor control, and redraw helpers.

menu_tty_cols() {
	local cols size
	size="$(stty size </dev/tty 2>/dev/null || true)"
	if [[ -n "$size" ]]; then
		cols="${size##* }"
	else
		cols="$(tput cols 2>/dev/null || echo 120)"
	fi
	[[ "$cols" =~ ^[0-9]+$ ]] || cols=120
	((cols < 20)) && cols=20
	printf '%s\n' "$cols"
}

menu_tty_rows() {
	local rows size
	size="$(stty size </dev/tty 2>/dev/null || true)"
	if [[ -n "$size" ]]; then
		rows="${size%% *}"
	else
		rows="$(tput lines 2>/dev/null || echo 30)"
	fi
	[[ "$rows" =~ ^[0-9]+$ ]] || rows=30
	((rows < 12)) && rows=12
	printf '%s\n' "$rows"
}

menu_fit_line() {
	local text="$1"
	local cols="$2"
	local max_cols=$((cols - 1))
	local text_len=${#text}

	((max_cols < 1)) && max_cols=1

	if [[ text_len -gt max_cols ]]; then
		if [[ max_cols -gt 3 ]]; then
			printf '%s' "${text:0:$((max_cols - 3))}..."
		else
			printf '%s' "${text:0:$max_cols}"
		fi
	else
		printf '%s' "$text"
	fi
}

menu_fit_indent() {
	local text="$1"
	local cols="$2"
	local indent="$3"
	local usable_cols=$((cols - indent))

	((usable_cols < 1)) && usable_cols=1
	menu_fit_line "$text" "$usable_cols"
}

menu_cursor_hide() {
	tput civis 2>/dev/null || true
}

menu_cursor_show() {
	tput cnorm 2>/dev/null || true
}

menu_redraw_up() {
	local lines="$1"
	printf '\e[%dA' "$lines"
}

menu_count_lines() {
	local header_rows="$1"
	local item_count="$2"
	local footer_rows="$3"
	echo $((header_rows + item_count + footer_rows))
}
