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

_dotfiles_install_repo_decision() {
	local _event="$1" prompt="$2"
	ui_confirm_yes_no "$prompt"
}

_dotfiles_install_repo_gate() {
	local repo_rc=0
	local -A result=()

	if ! declare -F repo_update_run >/dev/null || [[ -z "${DOTFILES_DIR:-}" ]]; then
		return 0
	fi

	repo_update_run "$DOTFILES_DIR" 'dotfiles repo' _dotfiles_install_repo_decision result 'PamuduW/dotfiles' || repo_rc=$?
	[[ "$repo_rc" -eq 2 ]] && {
		printf '%sRepository fast-forward succeeded; install stopped. Run setup again when ready.%s\n' \
			"${C_GREEN:-}" "${C_RESET:-}"
		return 2
	}
	[[ "$repo_rc" -eq 0 ]]
}

run_install_action() {
	declare -F start_action_log >/dev/null 2>&1 && start_action_log
	ui_clear
	# A declined or blocked repository check is a handled menu outcome. The
	# shared gate already printed the reason; return to the menu without adding a
	# second generic "Action failed" message.
	local repo_rc=0
	_dotfiles_install_repo_gate || repo_rc=$?
	((repo_rc == 2)) && return 2
	((repo_rc != 0)) && return 0
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
	local tty_out
	declare -F start_action_log >/dev/null 2>&1 && start_action_log
	if [[ "$DOTFILES_INTERACTIVE_TTY" != true ]]; then
		_dotfiles_install_repo_gate || return $?
		apply_dotfiles_components_env
		_apply_noninteractive_git_defaults
		_run_setup_header
		show_plan
		run_install
		return $?
	fi

	tty_out="$(tty_output_path)"
	_run_setup_header >"$tty_out"
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
		show_plan
		read_tty_line answer "$(ui_install_confirm_prompt)"
		tty_printf '%s' "${C_RESET:-}"
		case "$answer" in
		c | C) return 0 ;;
		e | E)
			component_menu || return 1
			need_git_prompt=true
			;;
		q | Q)
			tty_printf '%s\n' "Returning to Dotfiles menu."
			return 1
			;;
		*) tty_printf '%s\n' "    Invalid choice." ;;
		esac
	done
}

print_status_summary_all() {
	local row result detail short_label
	local -a rows=()
	local ok_count=0 check_count=0 miss_count=0
	local cols status_output="${DOTFILES_STATUS_OUTPUT:-$(tty_output_path)}"

	cols="$(menu_tty_cols)"
	collect_component_status_rows rows

	{
		ui_clear
		printf '\n'
		ui_print_header "Check Status" "Dotfiles › Check Status" "$cols"
		ui_print_report_table_columns

		for row in "${rows[@]}"; do
			IFS='|' read -r short_label detail result <<<"$row"
			case "$result" in
			installed | configured) ((++ok_count)) ;;
			missing) ((++miss_count)) ;;
			*) ((++check_count)) ;;
			esac
			ui_print_report_table_row "$short_label" "$detail" "$result"
		done

		if [[ $miss_count -eq 0 && $check_count -eq 0 ]]; then
			ui_print_report_rollup "$ok_count" 0 0
		elif [[ $miss_count -eq 0 ]]; then
			ui_print_report_rollup "$ok_count" "$check_count" 0
		else
			ui_print_report_rollup "$ok_count" "$check_count" "$miss_count"
		fi
	} >"$status_output"
}
