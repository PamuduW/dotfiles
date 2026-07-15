#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/menu_render.sh
source "$ROOT/scripts/lib/menu_render.sh"
# shellcheck source=scripts/lib/ui.sh
source "$ROOT/scripts/lib/ui.sh"
# shellcheck source=scripts/lib/menu_descriptions.sh
source "$ROOT/scripts/lib/menu_descriptions.sh"
# shellcheck source=scripts/lib/menu_simple.sh
source "$ROOT/scripts/lib/menu_simple.sh"
# shellcheck source=scripts/lib/menu_checkbox.sh
source "$ROOT/scripts/lib/menu_checkbox.sh"

passed=0
failed=0

pass() {
	printf 'ok - %s\n' "$1"
	passed=$((passed + 1))
}

fail() {
	printf 'not ok - %s\n' "$1" >&2
	failed=$((failed + 1))
}

expect_success() {
	local name="$1"
	shift
	if "$@"; then
		pass "$name"
	else
		fail "$name"
	fi
}

configure_simple_menu_with_descriptions() {
	MENU_SIMPLE_TITLE='Test menu'
	MENU_SIMPLE_BREADCRUMB=''
	MENU_SIMPLE_HINT='Navigate'
	MENU_SIMPLE_LABELS=('One' 'Two' 'Three')
	MENU_SIMPLE_KEYS=(one two three)
	MENU_SIMPLE_TYPES=('item' 'item' 'item')
	MENU_SIMPLE_DESCS=(
		$'Description one\nDetail one'
		$'Description two\nDetail two'
		$'Description three\nDetail three'
	)
	unset MENU_SIMPLE_DESC_FN
}

render_simple_frame() {
	local cursor="$1"
	local output_file="$2"
	local -a rendered=()
	local line

	_menu_simple_draw "$cursor" 80 >"$output_file"
	mapfile -t rendered <"$output_file"
	: >"$output_file"
	for line in "${rendered[@]}"; do
		printf '%s\n' "${line//$'\e[K'/}" >>"$output_file"
	done
}

count_matching_lines() {
	local pattern="$1"
	local file="$2"
	local line count=0
	while IFS= read -r line; do
		[[ "$line" == *"$pattern"* ]] && count=$((count + 1))
	done <"$file"
	printf '%s\n' "$count"
}

test_simple_menu_has_one_spacer_before_descriptions() {
	local output_file="$TEST_TMP/simple-with-description"
	local -a lines=()

	configure_simple_menu_with_descriptions
	render_simple_frame 2 "$output_file"
	mapfile -t lines <"$output_file"

	[[ "${#lines[@]}" -eq 10 ]] || return 1
	[[ "${lines[6]}" == *'3. Three'* ]] || return 1
	[[ -z "${lines[7]}" ]] || return 1
	[[ "${lines[8]}" == *'Description three'* ]] || return 1
	[[ "${lines[9]}" == *'Detail three'* ]]
}

test_down_up_frames_match_redraw_count_without_stale_content() {
	local expected_lines cursor output_file expected_description stale_description
	local -a lines=()

	configure_simple_menu_with_descriptions
	expected_lines="$(_menu_simple_menu_lines 3)"
	[[ "$expected_lines" -eq 10 ]] || return 1

	for cursor in 0 1 0; do
		output_file="$TEST_TMP/frame-$cursor-$RANDOM"
		render_simple_frame "$cursor" "$output_file"
		mapfile -t lines <"$output_file"
		[[ "${#lines[@]}" -eq "$expected_lines" ]] || return 1

		if ((cursor == 0)); then
			expected_description='Description one'
			stale_description='Description two'
		else
			expected_description='Description two'
			stale_description='Description one'
		fi
		[[ "$(count_matching_lines "$expected_description" "$output_file")" -eq 1 ]] || return 1
		[[ "$(count_matching_lines "$stale_description" "$output_file")" -eq 0 ]] || return 1
	done
}

test_no_description_keeps_existing_blank_footer() {
	local output_file="$TEST_TMP/simple-without-description"
	local -a lines=()

	configure_simple_menu_with_descriptions
	unset MENU_SIMPLE_DESCS MENU_SIMPLE_DESC_FN
	render_simple_frame 0 "$output_file"
	mapfile -t lines <"$output_file"

	[[ "$(_menu_simple_menu_lines 3)" -eq 8 ]] || return 1
	[[ "${#lines[@]}" -eq 8 ]] || return 1
	[[ "${lines[6]}" == *'3. Three'* ]] || return 1
	[[ -z "${lines[7]}" ]]
}

test_checkbox_fixed_rows_are_unchanged() {
	unset MENU_CB_DESCS MENU_CB_DESC_FN
	[[ "$(_menu_cb_fixed_rows)" -eq 8 ]] || return 1
	MENU_CB_DESCS=($'Checkbox description\nCheckbox detail')
	[[ "$(_menu_cb_fixed_rows)" -eq 10 ]]
}

TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-menu-render.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
NO_COLOR=1
export NO_COLOR
ui_init_colors

expect_success 'simple menu has exactly one spacer before descriptions' test_simple_menu_has_one_spacer_before_descriptions
expect_success 'down/up frames match redraw count without stale content' test_down_up_frames_match_redraw_count_without_stale_content
expect_success 'no-description menu keeps its existing blank footer' test_no_description_keeps_existing_blank_footer
expect_success 'checkbox fixed-row accounting is unchanged' test_checkbox_fixed_rows_are_unchanged

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
