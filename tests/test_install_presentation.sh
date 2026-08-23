#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init

source "$REPO_DIR/scripts/lib/shared/tui/menu_render.sh"
source "$REPO_DIR/scripts/lib/shared/tui/tty.sh"
source "$REPO_DIR/scripts/lib/shared/tui/report_table.sh"
source "$REPO_DIR/scripts/lib/shared/tui/ui.sh"
source "$REPO_DIR/scripts/lib/installers/logging.sh"
ui_init_colors

test_harness_report_init

test_install_legend_uses_status_colors() {
	local output
	NO_COLOR='' FORCE_COLOR=1 ui_init_colors
	output="$(_log_legend_line)"
	[[ "$output" == *"${C_CYAN}STEP=starting${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_GREEN}OK=completed${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_DIM}SKIP=already satisfied${C_RESET}"* ]] || return 1
	[[ "$output" == *"${C_YELLOW}WARN=needs attention${C_RESET}"* ]]
}

test_install_status_markers_use_semantic_colors() {
	local output
	NO_COLOR='' FORCE_COLOR=1 ui_init_colors
	output="$(log_step 'starting')"
	[[ "$output" == "${C_CYAN}[STEP]${C_RESET} starting" ]] || return 1
	output="$(log_ok 'completed')"
	[[ "$output" == "${C_GREEN}[OK]${C_RESET} completed" ]] || return 1
	output="$(log_skip 'already satisfied')"
	[[ "$output" == "${C_DIM}[SKIP]${C_RESET} already satisfied" ]] || return 1
	output="$(log_warn 'needs attention')"
	[[ "$output" == "${C_YELLOW}[WARN]${C_RESET} needs attention" ]]
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
	[[ "$output" == "  ${C_CYAN}c${C_RESET} confirm   ${C_CYAN}e${C_RESET} edit   ${C_CYAN}q${C_RESET} back_to_menu : ${C_RESET}" ]]
}

test_shortcut_hint_keeps_labels_undimmed() {
	local output
	NO_COLOR='' FORCE_COLOR=1 ui_init_colors
	output="$(ui_format_shortcuts s 'Save or replace' r 'Reveal once' d Remove q Back)${C_RESET:-}"
	[[ "$output" == "${C_CYAN}s${C_RESET} Save or replace   ${C_CYAN}r${C_RESET} Reveal once   ${C_CYAN}d${C_RESET} Remove   ${C_CYAN}q${C_RESET} Back${C_RESET}" ]]
}

expect_success 'install legend uses semantic status colors' test_install_legend_uses_status_colors
expect_success 'install status markers use semantic colors' test_install_status_markers_use_semantic_colors
expect_success 'confirmation hint colors its action keys' test_confirm_hint_uses_colored_action_keys
expect_success 'install confirmation prompt colors full action text' test_install_confirm_prompt_colors_full_action_text
expect_success 'shortcut labels use normal text intensity' test_shortcut_hint_keeps_labels_undimmed
finish_tests
