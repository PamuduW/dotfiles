# shellcheck shell=bash

command_lib_render() {
	local cols="${1:-$(menu_tty_cols)}"

	if declare -F ui_print_header >/dev/null; then
		ui_print_header "Command Lib" "Dotfiles › Command Lib" "$cols"
	else
		rt_print_header "Command Lib" "Dotfiles › Command Lib"
	fi
	dotfiles_command_print_table "$cols"
}

command_lib_menu() {
	local tty_out
	tty_out="$(tty_output_path)"
	ui_clear
	command_lib_render "$(menu_tty_cols)" >"$tty_out"
	ui_pause
}
