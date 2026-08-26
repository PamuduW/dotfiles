# shellcheck shell=bash
# Terminal geometry, line fitting, cursor control, and redraw helpers.

if ! declare -F tty_input_path >/dev/null 2>&1; then
	_MENU_RENDER_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
	# shellcheck source=scripts/lib/shared/tui/tty.sh
	source "$_MENU_RENDER_LIB_DIR/tty.sh"
fi

# Terminal geometry is read once and cached: menu_tty_cols is called on every
# header, table, and redraw, and each uncached call cost a terminal open plus an
# `stty size` process. SIGWINCH invalidates the cache; so does an explicit
# menu_tty_invalidate_size for tests and for callers that change the TTY seam.
_MENU_TTY_COLS=''
_MENU_TTY_ROWS=''

menu_tty_invalidate_size() {
	_MENU_TTY_COLS=''
	_MENU_TTY_ROWS=''
}

trap menu_tty_invalidate_size WINCH 2>/dev/null || true

_menu_tty_read_size() {
	local size='' tty_in
	[[ -n "$_MENU_TTY_COLS" && -n "$_MENU_TTY_ROWS" ]] && return 0

	# Ask whichever seam is active. The redirection itself has to be guarded:
	# `2>/dev/null` silences stty, not bash's own "no such device" for a path
	# that cannot be opened.
	if tty_use_input_fd; then
		size="$(stty size <&"$DOTFILES_TTY_IN_FD" 2>/dev/null || true)"
	elif tty_available; then
		tty_in="$(tty_input_path)"
		size="$(stty size <"$tty_in" 2>/dev/null || true)"
	fi

	if [[ -n "$size" ]]; then
		_MENU_TTY_ROWS="${size%% *}"
		_MENU_TTY_COLS="${size##* }"
	else
		_MENU_TTY_COLS="$(tput cols 2>/dev/null || echo 120)"
		_MENU_TTY_ROWS="$(tput lines 2>/dev/null || echo 30)"
	fi

	[[ "$_MENU_TTY_COLS" =~ ^[0-9]+$ ]] || _MENU_TTY_COLS=120
	[[ "$_MENU_TTY_ROWS" =~ ^[0-9]+$ ]] || _MENU_TTY_ROWS=30
	((_MENU_TTY_COLS < 20)) && _MENU_TTY_COLS=20
	((_MENU_TTY_ROWS < 12)) && _MENU_TTY_ROWS=12
	return 0
}

menu_tty_cols() {
	_menu_tty_read_size
	printf '%s\n' "$_MENU_TTY_COLS"
}

menu_tty_rows() {
	_menu_tty_read_size
	printf '%s\n' "$_MENU_TTY_ROWS"
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

# Full clear when layout changes (page/line count); otherwise cursor-up in-place redraw.
menu_redraw_prepare() {
	local prev_lines="$1"
	local new_lines="$2"
	local prev_page="${3:--1}"
	local new_page="${4:-0}"

	if [[ "$prev_lines" != "$new_lines" || "$prev_page" != "$new_page" ]]; then
		ui_clear
	else
		menu_redraw_up "$prev_lines"
	fi
}
