# shellcheck shell=bash
# Component execution-plan rendering. Static row metadata lives in registry.sh;
# comp_plan_row handles the three rows with runtime-dependent details.

show_plan() {
	local cols i key tty_out

	cols="$(menu_tty_cols)"
	tty_out="$(tty_output_path)"

	{
		ui_clear
		# ui_print_header already ends with a blank line; a second one made this
		# the only screen with a two-line gap under its breadcrumb.
		ui_print_header "Execution Plan" "Dotfiles › Install Dotfiles › Execution Plan" "$cols"

		for i in "${!COMP_KEYS[@]}"; do
			key="${COMP_KEYS[$i]}"
			comp_plan_row "$key"
		done

		printf '\n'
	} >"$tty_out"
}
