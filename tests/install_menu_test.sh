#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

load_install_functions() {
	local tmp
	tmp="$(mktemp)"
	sed '/^main "\$@"$/d' "$ROOT_DIR/install.sh" >"$tmp"
	# shellcheck disable=SC1090
	source "$tmp"
	rm -f "$tmp"
}

assert_eq() {
	local actual="$1"
	local expected="$2"
	local message="$3"

	if [[ "$actual" != "$expected" ]]; then
		printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
		exit 1
	fi
}

load_install_functions

assert_eq "$(_component_menu_page_size 12)" "5" "small terminals still show a minimal page"
assert_eq "$(_component_menu_page_size 20)" "13" "page size leaves room for chrome"
assert_eq "$(printf '\033[32mhello\033[0m\rworld\n' | _clean_log_stream)" $'hello\nworld' "log cleaner strips ANSI escapes and normalizes carriage returns"
assert_eq "$(_component_menu_page_for_cursor 0 5)" "0" "first item stays on first page"
assert_eq "$(_component_menu_page_for_cursor 7 5)" "1" "cursor crossing page size advances page"
assert_eq "$(_component_menu_page_count 20 5)" "4" "page count rounds up"
assert_eq "$(_component_menu_page_range 20 5 3)" "15 19" "last page range is bounded"
assert_eq "$(_component_menu_visible_count 20 13 1)" "7" "visible count shrinks on the last page"
assert_eq "$(_component_menu_render_lines 20 13 1)" "14" "render line count follows actual rows on the page"
assert_eq "$(_menu_decode_escape_sequence '[A')" "up" "up arrow is decoded"
assert_eq "$(_menu_decode_escape_sequence '[B')" "down" "down arrow is decoded"
assert_eq "$(_menu_decode_escape_sequence '[<64;10;5M')" "ignore" "mouse wheel escapes are ignored"
assert_eq "$(_fit_menu_line_with_indent '1234567890' 10 2)" "1234..." "indented lines account for their visible prefix width"
assert_eq "$(_component_menu_description_line 0 0)" "Set global git user.name and user.email." "selected item description uses the first help line"
assert_eq "$(_component_menu_description_line 0 1)" "Skip this if you use includeIf for per-directory identities." "selected item description uses the second help line"
command -v _run_quiet_command >/dev/null
assert_eq "$(_run_quiet_command 'true output' bash -lc 'printf hidden')" "" "quiet command helper suppresses successful command output"

printf 'ok\n'
