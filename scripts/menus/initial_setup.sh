# shellcheck shell=bash

_initial_labels=(
	"Check status"
	"Run setup"
	"Back"
)
_initial_keys=(status run back)

_initial_dispatch() {
	case "$1" in
	status)
		print_status_summary_all
		;;
	run)
		ui_clear
		run_initial_setup_flow
		;;
	esac
}

initial_setup_menu() {
	menu_submenu_loop "Initial setup" "Dotfiles › Initial setup" \
		_initial_labels _initial_keys _initial_dispatch
}

run_initial_setup_flow() {
	{
		printf '\n'
		ui_print_header "WSL Dotfiles Setup" ""
		printf 'Log file: %s\n' "$LOG_FILE"
	} >/dev/tty
	component_menu || return 0
	confirm_loop || return 0
	run_install
}

confirm_loop() {
	local need_git_prompt=true
	local answer=""
	while true; do
		if is_on git_identity && [[ "$need_git_prompt" == "true" ]]; then
			prompt_git_identity
			need_git_prompt=false
		fi
		{
			show_plan
			read_tty_line answer "  [c]onfirm  [e]dit  [q] back to menu: "
		} >/dev/tty
		case "$answer" in
		c | C) return 0 ;;
		e | E)
			component_menu || return 1
			need_git_prompt=true
			;;
		q | Q)
			printf '%s\n' "Returning to Initial setup menu." >/dev/tty
			return 1
			;;
		*) printf '%s\n' "    Invalid choice." >/dev/tty ;;
		esac
	done
}

print_status_summary_all() {
	local i key label row result detail short_label
	local ok_count=0 miss_count=0
	local cols

	cols="$(menu_tty_cols)"

	{
		ui_clear
		printf '\n'
		ui_print_header "Status summary" "Dotfiles › Initial setup" "$cols"
		printf '  %s%s%s\e[K\n' "$C_BOLD" "$(menu_fit_indent "component | detail | result" "$cols" 2)" "$C_RESET"
		printf '  %s%s%s\e[K\n' "$C_DIM" \
			"$(menu_fit_indent "----------------------+----------------------------------+-----------" "$cols" 2)" \
			"$C_RESET"

		for i in "${!COMP_KEYS[@]}"; do
			key="${COMP_KEYS[$i]}"
			label="${COMP_LABELS[$i]}"
			row="$(_install_summary_probe "$key")"
			IFS='|' read -r result detail <<<"$row"
			short_label="$(_install_short_label "$label")"
			case "$result" in
			installed | configured) ((++ok_count)) ;;
			missing | check) ((++miss_count)) ;;
			esac
			ui_print_component_table_row "$short_label" "$detail" "$result"
		done

		printf '\n'
		if [[ $miss_count -eq 0 ]]; then
			printf '  %sAll %d component(s) look good.%s\n' "$C_GREEN" "$ok_count" "$C_RESET"
		else
			printf '  %s%d ok%s, %s%d need attention%s.\n' \
				"$C_GREEN" "$ok_count" "$C_RESET" \
				"$C_YELLOW" "$miss_count" "$C_RESET"
		fi
	} >/dev/tty
}
