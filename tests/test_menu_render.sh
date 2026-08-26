#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

# shellcheck source=scripts/lib/shared/tui/menu_render.sh
source "$ROOT/scripts/lib/shared/tui/menu_render.sh"
# shellcheck source=scripts/lib/shared/tui/ui.sh
source "$ROOT/scripts/lib/shared/tui/ui.sh"
# shellcheck source=scripts/lib/shared/tui/report_table.sh
source "$ROOT/scripts/lib/shared/tui/report_table.sh"
# shellcheck source=scripts/lib/shared/tui/menu_descriptions.sh
source "$ROOT/scripts/lib/shared/tui/menu_descriptions.sh"
# shellcheck source=scripts/lib/shared/tui/menu_simple.sh
source "$ROOT/scripts/lib/shared/tui/menu_simple.sh"
# shellcheck source=scripts/lib/shared/tui/menu_keys.sh
source "$ROOT/scripts/lib/shared/tui/menu_keys.sh"
# shellcheck source=scripts/lib/shared/tui/menu_checkbox.sh
source "$ROOT/scripts/lib/shared/tui/menu_checkbox.sh"
# shellcheck source=scripts/lib/shared/tui/menu_paging.sh
source "$ROOT/scripts/lib/shared/tui/menu_paging.sh"
# shellcheck source=scripts/lib/components/registry.sh
source "$ROOT/scripts/lib/components/registry.sh"
# shellcheck source=scripts/lib/components/menu.sh
source "$ROOT/scripts/lib/components/menu.sh"

_fit_menu_line() { menu_fit_line "$@"; }
_fit_menu_line_with_indent() { menu_fit_indent "$@"; }

test_harness_report_init

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

test_component_menu_adapter_preserves_dependency_toggles() {
	COMP_KEYS=(alpha beta)
	COMP_LABELS=('Alpha' 'Beta')
	declare -gA COMP_DEPENDS_ON=([beta]=alpha)
	declare -gA COMP_ON=()
	COMP_ON=([alpha]=1 [beta]=1)
	toggle_component() {
		COMP_ON[alpha]=0
		COMP_ON[beta]=0
		TOGGLE_MSG='auto-disabled: Beta'
	}
	declare -ga MENU_CB_CHECKED=([0]=1 [1]=1)
	_component_menu_toggle 0
	[[ "${MENU_CB_CHECKED[0]}" -eq 0 && "${MENU_CB_CHECKED[1]}" -eq 0 ]] || return 1
	[[ "$MENU_CB_STATUS_MESSAGE" == 'auto-disabled: Beta' ]]
}

test_report_rows_fit_long_cells_at_supported_widths() (
	local cols output line
	for cols in 48 80 120; do
		output="$(DOTFILES_REPORT_COLS="$cols" NO_COLOR=1 rt_print_table_row \
			'Git config (credentials + submodules)' \
			'/home/pamudu/a/very/long/path/to/a/configuration/file' \
			'refresh-required')"
		line="${output//$'\033'/}"
		((${#line} == cols)) || return 1
		[[ "$(grep -o '|' <<<"$line" | wc -l)" -eq 2 ]] || return 1
		[[ "$line" == *'…'* && "$line" != *'...'* ]] || return 1
	done
)

test_no_color_clears_a_preloaded_report_palette() (
	colors_set_palette
	local output
	output="$(NO_COLOR=1 rt_print_table_row Component Detail warning)"
	[[ "$output" != *$'\033['* ]]
)

TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-menu-render.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
NO_COLOR=1
export NO_COLOR
ui_init_colors

test_terminal_geometry_is_quiet_without_a_tty() (
	local scratch errors cols
	scratch="$(mktemp -d)"
	DOTFILES_TTY_INPUT="$scratch/missing-geometry-input"
	DOTFILES_TTY_OUTPUT="$scratch/missing-geometry-output"
	errors="$scratch/geometry-errors"
	menu_tty_invalidate_size
	cols="$(menu_tty_cols 2>"$errors")"
	local quiet=1
	[[ -s "$errors" ]] && quiet=0
	rm -rf -- "$scratch"
	[[ "$cols" =~ ^[0-9]+$ && "$quiet" -eq 1 ]]
)

test_output_only_headless_tty_is_unavailable_without_a_shell_diagnostic() (
	# Break caught: tty_output_available reports success for an unavailable
	# controlling terminal, leaving the later write to fail noisily.
	local errors="$TEST_TMP/output-only-headless.errors" rc=0
	unset DOTFILES_TTY_IN_FD DOTFILES_TTY_OUT_FD
	DOTFILES_TTY_INPUT="$TEST_TMP/valid-input"
	DOTFILES_TTY_OUTPUT=/dev/tty
	: >"$DOTFILES_TTY_INPUT"
	set +e
	tty_output_available 2>"$errors"
	rc=$?
	set -e
	[[ "$rc" -eq 1 && ! -s "$errors" ]]
)

test_terminal_geometry_prefers_input_fd_with_path_backed_output() (
	local input="$TEST_TMP/geometry-fd-input" output="$TEST_TMP/geometry-path-output"
	printf '\n' >"$input"
	: >"$output"
	exec {DOTFILES_TTY_IN_FD}<"$input"
	unset DOTFILES_TTY_OUT_FD
	DOTFILES_TTY_INPUT="$TEST_TMP/missing-geometry-path"
	DOTFILES_TTY_OUTPUT="$output"
	stty() { printf '31 101\n'; }
	menu_tty_invalidate_size
	_menu_tty_read_size
	exec {DOTFILES_TTY_IN_FD}<&-
	[[ "$_MENU_TTY_ROWS" == 31 && "$_MENU_TTY_COLS" == 101 ]]
)

test_terminal_geometry_uses_input_path_with_fd_backed_output() (
	local input="$TEST_TMP/geometry-path-input" output="$TEST_TMP/geometry-fd-output"
	printf '\n' >"$input"
	: >"$output"
	unset DOTFILES_TTY_IN_FD
	exec {DOTFILES_TTY_OUT_FD}>>"$output"
	DOTFILES_TTY_INPUT="$input"
	DOTFILES_TTY_OUTPUT="$TEST_TMP/missing-geometry-output"
	stty() { printf '32 102\n'; }
	menu_tty_invalidate_size
	_menu_tty_read_size
	exec {DOTFILES_TTY_OUT_FD}>&-
	[[ "$_MENU_TTY_ROWS" == 32 && "$_MENU_TTY_COLS" == 102 ]]
)

test_fd_key_stream_overrides_path_for_navigation_cancel_confirm_and_pagination() (
	# Break caught: menu_read_key reopens DOTFILES_TTY_INPUT instead of consuming
	# the caller-owned descriptor, restarting multi-key input at the wrong stream.
	local path_input="$TEST_TMP/path-keys.input" fd_output="$TEST_TMP/fd-keys.output"
	local action expected bytes case_id=0
	printf 'x' >"$path_input"
	while IFS='|' read -r expected bytes; do
		case_id=$((case_id + 1))
		local fd_input="$TEST_TMP/fd-key-${case_id}.input"
		printf '%b' "$bytes" >"$fd_input"
		exec {DOTFILES_TTY_IN_FD}<"$fd_input"
		exec {DOTFILES_TTY_OUT_FD}>>"$fd_output"
		DOTFILES_TTY_INPUT="$path_input"
		DOTFILES_TTY_OUTPUT="$fd_output"
		export DOTFILES_TTY_INPUT DOTFILES_TTY_OUTPUT DOTFILES_TTY_IN_FD DOTFILES_TTY_OUT_FD
		action="$(menu_read_key)"
		exec {DOTFILES_TTY_IN_FD}<&-
		exec {DOTFILES_TTY_OUT_FD}>&-
		[[ "$action" == "$expected" ]] || return 1
	done <<'EOF'
up|\e[A
cancel|q
confirm|\n
page_down|\e[6~
EOF
)

expect_success 'simple menu has exactly one spacer before descriptions' test_simple_menu_has_one_spacer_before_descriptions
expect_success 'down/up frames match redraw count without stale content' test_down_up_frames_match_redraw_count_without_stale_content
expect_success 'no-description menu keeps its existing blank footer' test_no_description_keeps_existing_blank_footer
expect_success 'checkbox fixed-row accounting is unchanged' test_checkbox_fixed_rows_are_unchanged
test_terminal_geometry_is_cached_and_invalidatable() (
	local calls reads
	calls="$(mktemp)"
	# Count how often geometry is actually read from the terminal. Only
	# in-process calls are measured: a $(...) subshell gets its own cache copy.
	tty_available() {
		printf 'read\n' >>"$calls"
		return 1
	}
	tput() { printf '77\n'; }

	menu_tty_invalidate_size
	_menu_tty_read_size
	_menu_tty_read_size
	_menu_tty_read_size
	reads="$(wc -l <"$calls")"
	[[ "$reads" -eq 1 ]] || {
		rm -f -- "$calls"
		printf 'expected 1 cached geometry read, got %s\n' "$reads" >&2
		return 1
	}
	[[ "$_MENU_TTY_COLS" == 77 && "$_MENU_TTY_ROWS" == 77 ]] || {
		rm -f -- "$calls"
		return 1
	}

	# SIGWINCH and the explicit hook both force a fresh read.
	menu_tty_invalidate_size
	_menu_tty_read_size
	reads="$(wc -l <"$calls")"
	rm -f -- "$calls"
	[[ "$reads" -eq 2 ]]
)

expect_success 'component menu adapter preserves dependency-aware toggles' test_component_menu_adapter_preserves_dependency_toggles
expect_success 'report rows fit long cells at 48, 80, and 120 columns' test_report_rows_fit_long_cells_at_supported_widths
expect_success 'NO_COLOR clears a preloaded report palette' test_no_color_clears_a_preloaded_report_palette
expect_success 'terminal geometry is cached and invalidatable' test_terminal_geometry_is_cached_and_invalidatable
expect_success 'terminal geometry falls back quietly without a controlling TTY' test_terminal_geometry_is_quiet_without_a_tty
expect_success 'output-only headless TTY is unavailable without a shell diagnostic' test_output_only_headless_tty_is_unavailable_without_a_shell_diagnostic
expect_success 'terminal geometry prefers input FD with path-backed output' test_terminal_geometry_prefers_input_fd_with_path_backed_output
expect_success 'terminal geometry uses input path with FD-backed output' test_terminal_geometry_uses_input_path_with_fd_backed_output
expect_success 'FD key streams override paths for navigation cancel confirm and pagination' test_fd_key_stream_overrides_path_for_navigation_cancel_confirm_and_pagination

finish_tests
