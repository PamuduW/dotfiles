# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_SIMPLE_* globals are consumed by menu_simple_run.

command_lib_render() {
	local cols="${1:-$(menu_tty_cols)}"

	if declare -F ui_print_header >/dev/null; then
		ui_print_header "Command Lib" "Dotfiles › Command Lib" "$cols"
	else
		rt_print_header "Command Lib" "Dotfiles › Command Lib"
	fi
	dotfiles_command_print_table "$cols"
}

command_lib_detail_render() {
	local command="$1" cols="${2:-$(menu_tty_cols)}"
	ui_print_header "$command" "Dotfiles › Command Lib › $command" "$cols"
	dotfiles_command_print_detail "$command" "$cols"
}

_command_lib_index() {
	local key
	MENU_SIMPLE_TITLE='Command Lib'
	MENU_SIMPLE_BREADCRUMB='Dotfiles › Command Lib'
	MENU_SIMPLE_HINT='Up/Down navigate   Enter confirm   q back'
	MENU_SIMPLE_LABELS=()
	MENU_SIMPLE_KEYS=()
	MENU_SIMPLE_TYPES=()
	MENU_SIMPLE_DESCS=()
	for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
		MENU_SIMPLE_LABELS+=("$key [${DOTFILES_COMMAND_CLASS[$key]}] — ${DOTFILES_COMMAND_DESCRIPTION[$key]}")
		MENU_SIMPLE_KEYS+=("$key")
		MENU_SIMPLE_DESCS+=("Usage: dotfiles $(dotfiles_command_display_usage "$key")")
	done
}

command_lib_menu() {
	local tty_out choice
	tty_out="$(tty_output_path)"
	while true; do
		_command_lib_index
		menu_simple_run || return 0
		choice="${MENU_SIMPLE_RESULT:-}"
		ui_clear
		command_lib_detail_render "$choice" "$(menu_tty_cols)" >"$tty_out"
		ui_wait_back
	done
}
