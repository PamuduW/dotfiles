#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

source "$REPO_DIR/scripts/lib/menu_render.sh"
source "$REPO_DIR/scripts/lib/tty.sh"
source "$REPO_DIR/scripts/lib/report_table.sh"
source "$REPO_DIR/scripts/lib/ui.sh"
source "$REPO_DIR/scripts/lib/installers/logging.sh"
ui_init_colors

passed=0 failed=0
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
	if "$@"; then pass "$name"; else fail "$name"; fi
}

test_install_legend_uses_status_colors() {
	local output
	NO_COLOR='' FORCE_COLOR=1 ui_init_colors
	output="$(_log_legend_line)"
	[[ "$output" == *"${C_CYAN}STEP=starting${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_GREEN}OK=completed${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_DIM}SKIP=already satisfied${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_YELLOW}WARN=needs attention${C_RESET}"* ]]
}

test_confirm_hint_uses_colored_action_keys() {
	local output
	output="$(ui_color_input_hint '  [c]onfirm  [e]dit  [q] back to menu')"
	[[ "$output" == *"${C_CYAN}[c]${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_CYAN}[e]${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_CYAN}[q]${C_RESET}"* ]]
}

test_install_confirm_prompt_colors_full_action_text() {
	local output
	NO_COLOR='' FORCE_COLOR=1 ui_init_colors
	output="$(ui_install_confirm_prompt)"
	[[ "$output" == "${C_DIM}  ${C_RESET}${C_CYAN}c${C_RESET}${C_DIM} confirm   ${C_RESET}${C_CYAN}e${C_RESET}${C_DIM} edit   ${C_RESET}${C_CYAN}q${C_RESET}${C_DIM} back_to_menu : ${C_RESET}" ]]
}

expect_success 'install legend uses semantic status colors' test_install_legend_uses_status_colors
expect_success 'confirmation hint colors its action keys' test_confirm_hint_uses_colored_action_keys
expect_success 'install confirmation prompt colors full action text' test_install_confirm_prompt_colors_full_action_text
printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
