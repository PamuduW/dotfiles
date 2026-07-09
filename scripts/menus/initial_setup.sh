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
		ui_clear
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
	echo ""
	ui_print_header "WSL Dotfiles Setup" "" 0
	echo "Log file: $LOG_FILE"
	component_menu
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
		show_plan
		read_tty_line answer "  [c]onfirm  [e]dit  [q]uit: "
		case "$answer" in
		c | C) return 0 ;;
		e | E)
			component_menu
			need_git_prompt=true
			;;
		q | Q)
			echo "Aborted."
			return 1
			;;
		*) echo "    Invalid choice." ;;
		esac
	done
}

print_status_summary_all() {
	local i key label row result detail short_label
	local ok_count=0 miss_count=0

	echo ""
	ui_print_header "Status summary" "Dotfiles › Initial setup" 0
	printf '%-22s | %-32s | %s\n' "component" "detail" "result"
	printf '%s\n' "----------------------+----------------------------------+-----------"

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
		printf '%-22s | %-32s | %s\n' "$short_label" "${detail:0:32}" "$result"
	done

	echo ""
	if [[ $miss_count -eq 0 ]]; then
		echo "All ${ok_count} component(s) look good."
	else
		echo "${ok_count} ok, ${miss_count} need attention."
	fi
}
