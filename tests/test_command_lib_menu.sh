#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=tests/lib/test_harness.sh
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

NO_COLOR=1
PKG_FILE="$REPO_DIR/packages/packages.txt"
export NO_COLOR PKG_FILE

source "$REPO_DIR/scripts/lib/menu_render.sh"
source "$REPO_DIR/scripts/lib/tty.sh"
source "$REPO_DIR/scripts/lib/report_table.sh"
source "$REPO_DIR/scripts/lib/menu_keys.sh"
source "$REPO_DIR/scripts/lib/ui.sh"
source "$REPO_DIR/scripts/lib/command_metadata.sh"
source "$REPO_DIR/scripts/lib/components/registry.sh"
source "$REPO_DIR/scripts/menus/command_lib.sh"
source "$REPO_DIR/scripts/menus/package_lib.sh"
source "$REPO_DIR/scripts/menus/libraries.sh"
ui_init_colors

test_harness_report_init

test_one_command_detail_uses_only_authoritative_metadata() {
	local output
	output="$(dotfiles_command_print_detail status 80)" || return 1
	[[ "$output" == *'Command: status'* ]] || return 1
	[[ "$output" == *'Usage: status'* ]] || return 1
	[[ "$output" == *'Purpose: Show local component and repository state only.'* ]] || return 1
	[[ "$output" == *'Effects: Reads local command versions and git status;'* ]] || return 1
	[[ "$output" == *'Related: Use update when repository and downstream freshness'* ]] || return 1
	[[ "$output" != *'Command: update'* && "$output" != *'Configuration and environment'* ]]
}

test_one_command_detail_fits_supported_widths() {
	local cols output line stripped
	for cols in 48 80 120; do
		output="$(NO_COLOR=1 dotfiles_command_print_detail update "$cols")" || return 1
		while IFS= read -r line; do
			stripped="$(sed $'s/\033\\[[0-9;]*[A-Za-z]//g' <<<"$line")"
			((${#stripped} <= cols)) || {
				printf 'detail line exceeds %d columns: %s\n' "$cols" "$stripped" >&2
				return 1
			}
		done <<<"$output"
	done
}

test_wait_back_ignores_unrelated_keys_and_accepts_cancel() (
	local queue="$TEST_HARNESS_ROOT/wait-back.queue" prompt=''
	printf 'ignore\ncancel\n' >"$queue"
	tty_printf() { printf -v prompt "$@"; }
	menu_read_key() {
		local action rest="$queue.rest"
		IFS= read -r action <"$queue"
		tail -n +2 "$queue" >"$rest"
		mv -f -- "$rest" "$queue"
		printf '%s\n' "$action"
	}
	ui_wait_back || return 1
	[[ ! -s "$queue" ]] || return 1
	[[ "$prompt" == *q* && "$prompt" == *Enter* ]]
)

test_command_lib_selects_detail_and_returns_to_index() (
	local capture="$TEST_HARNESS_ROOT/command-detail.output"
	local menu_calls=0 waits=0 clears=0 index=''
	DOTFILES_TTY_OUTPUT="$capture"
	export DOTFILES_TTY_OUTPUT
	menu_tty_cols() { printf '80\n'; }
	menu_simple_run() {
		menu_calls=$((menu_calls + 1))
		if [[ "$menu_calls" -eq 1 ]]; then
			index="${MENU_SIMPLE_TITLE}|${MENU_SIMPLE_BREADCRUMB}|${MENU_SIMPLE_KEYS[*]}|${MENU_SIMPLE_LABELS[*]}"
			MENU_SIMPLE_RESULT=status
			return 0
		fi
		return 1
	}
	ui_clear() { clears=$((clears + 1)); }
	ui_wait_back() { waits=$((waits + 1)); }

	command_lib_menu || return 1
	[[ "$menu_calls" -eq 2 && "$waits" -eq 1 && "$clears" -eq 1 ]] || return 1
	[[ "$index" == Command\ Lib\|Dotfiles\ ›\ Command\ Lib\|menu\ update\ status\ commands\ packages\ restow\ help\|* ]] || return 1
	grep -Fq 'Dotfiles › Command Lib › status' "$capture" || return 1
	grep -Fq 'Command: status' "$capture" || return 1
	! grep -Fq 'Command: update' "$capture"
)

test_package_lib_owns_one_back_wait_without_pause() (
	local waits=0 pauses=0
	menu_tty_cols() { printf '80\n'; }
	tty_output_path() { printf '%s\n' "$TEST_HARNESS_ROOT/package.output"; }
	ui_clear() { :; }
	ui_wait_back() { waits=$((waits + 1)); }
	ui_pause() { pauses=$((pauses + 1)); }
	package_lib_menu || return 1
	[[ "$waits" -eq 1 && "$pauses" -eq 0 ]]
)

expect_success 'one command detail uses only authoritative metadata' test_one_command_detail_uses_only_authoritative_metadata
expect_success 'one command detail fits supported widths' test_one_command_detail_fits_supported_widths
expect_success 'back wait ignores unrelated keys and accepts cancel' test_wait_back_ignores_unrelated_keys_and_accepts_cancel
expect_success 'Command Lib selects detail and returns to index' test_command_lib_selects_detail_and_returns_to_index
expect_success 'Package Lib owns one back wait without pause' test_package_lib_owns_one_back_wait_without_pause

finish_tests
