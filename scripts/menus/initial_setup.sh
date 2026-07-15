# shellcheck shell=bash

_initial_labels=(
	"Check status"
	"Run setup"
	"Back"
)
_initial_keys=(status run back)

_initial_desc_fn() {
	case "$1" in
	0)
		echo "Show install status for every setup component (installed / missing / check)."
		echo "Read-only summary table with rollup counts."
		;;
	1)
		echo "Open the component picker, confirm plan, then run the install."
		echo "Prompts for git identity when that component is enabled."
		;;
	2)
		echo "Return to the main Dotfiles menu."
		;;
	esac
}

_initial_dispatch() {
	case "$1" in
	status)
		run_status_action
		;;
	run)
		run_install_action
		;;
	esac
}

run_status_action() {
	print_status_summary_all
}

run_install_action() {
	ui_clear
	run_initial_setup_flow
}

# shellcheck disable=SC2034  # Consumed by menu_submenu_loop.
initial_setup_menu() {
	MENU_SUBMENU_DESC_FN=_initial_desc_fn
	menu_submenu_loop "Initial setup" "Dotfiles › Initial setup" \
		_initial_labels _initial_keys _initial_dispatch
}

_apply_noninteractive_git_defaults() {
	if ! is_on git_identity; then
		return 0
	fi
	SETUP_GIT_NAME="${SETUP_GIT_NAME:-$(git config --global user.name 2>/dev/null || true)}"
	SETUP_GIT_EMAIL="${SETUP_GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
}

_run_setup_header() {
	printf '\n'
	ui_print_header "WSL Dotfiles Setup" ""
	printf 'Log file: %s\n' "$LOG_FILE"
}

run_initial_setup_flow() {
	if [[ "$DOTFILES_INTERACTIVE_TTY" != true ]]; then
		apply_dotfiles_components_env
		_apply_noninteractive_git_defaults
		_run_setup_header
		show_plan
		run_install
		return 0
	fi

	{
		_run_setup_header
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
			printf '%s\n' "Returning to Dotfiles menu." >/dev/tty
			return 1
			;;
		*) printf '%s\n' "    Invalid choice." >/dev/tty ;;
		esac
	done
}

print_status_summary_all() {
	local i key label row result detail short_label
	local ok_count=0 check_count=0 miss_count=0
	local cols status_output="${DOTFILES_STATUS_OUTPUT:-/dev/tty}"

	cols="$(menu_tty_cols)"

	{
		ui_clear
		printf '\n'
		ui_print_header "Check Status" "Dotfiles › Check Status" "$cols"
		ui_print_report_table_columns

		for i in "${!COMP_KEYS[@]}"; do
			key="${COMP_KEYS[$i]}"
			label="${COMP_LABELS[$i]}"
			row="$(_install_summary_probe "$key")"
			IFS='|' read -r result detail <<<"$row"
			short_label="$(_install_short_label "$label")"
			case "$result" in
			installed | configured) ((++ok_count)) ;;
			missing) ((++miss_count)) ;;
			check) ((++check_count)) ;;
			esac
			ui_print_report_table_row "$short_label" "$detail" "$result"
		done

		printf '\n'
		if [[ $miss_count -eq 0 && $check_count -eq 0 ]]; then
			ui_print_report_rollup "$ok_count" 0 0
		elif [[ $miss_count -eq 0 ]]; then
			ui_print_report_rollup "$ok_count" "$check_count" 0
		else
			ui_print_report_rollup "$ok_count" "$check_count" "$miss_count"
		fi
		printf '\nApt/package freshness: unchecked (run dotfiles update)\n'
		printf 'Repository freshness: unchecked (run dotfiles update)\n'
	} >"$status_output"
}
