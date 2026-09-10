# shellcheck shell=bash

# The "Initial setup" submenu was removed on 2026-09-09 along with the --initial
# mode that was its only way in. It offered "Check status" and "Run setup", both
# of which the main menu already has, and nothing else reached it.

run_status_action() {
	print_status_summary_all
}

_dotfiles_install_repo_decision() {
	local _event="$1" prompt="$2"
	# bootstrap.sh already asked whether to proceed and restarts itself once the
	# checkout moves, so a second confirmation for its own update is noise.
	# full_update takes the same position through _dotfiles_approve_repo_update.
	if [[ "${DOTFILES_REPO_UPDATE_ASSUME_YES:-}" == 1 ]]; then
		printf '%s yes (pre-authorized)\n' "$prompt"
		return 0
	fi
	ui_confirm_yes_no "$prompt"
}

_dotfiles_install_repo_gate() {
	local repo_rc=0
	local -A result=()
	DOTFILES_REPOSITORY_UPDATE_DECLINED=false

	if ! declare -F repo_update_run >/dev/null || [[ -z "${DOTFILES_DIR:-}" ]]; then
		return 0
	fi

	repo_update_run "$DOTFILES_DIR" 'dotfiles repo' _dotfiles_install_repo_decision result 'PamuduW/dotfiles' || repo_rc=$?
	if ((repo_rc == 2)); then
		repo_update_print_changed
		return 2
	fi
	if repo_update_is_declined result; then
		DOTFILES_REPOSITORY_UPDATE_DECLINED=true
		return 0
	fi
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
	[[ "${DOTFILES_REPOSITORY_UPDATE_DECLINED:-false}" == true ]] && return 0
	run_initial_setup_flow
}

# shellcheck disable=SC2034  # Consumed by menu_submenu_loop.

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
	printf '  Log file: %s\n' "$LOG_FILE"
}

run_initial_setup_flow() {
	local tty_out
	declare -F start_action_log >/dev/null 2>&1 && start_action_log
	if [[ "$DOTFILES_INTERACTIVE_TTY" != true ]]; then
		_dotfiles_install_repo_gate || return $?
		[[ "${DOTFILES_REPOSITORY_UPDATE_DECLINED:-false}" == true ]] && return 0
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
	_CONFIRM_NOTICE=''
	DOTFILES_FORCE_REINSTALL=0
	export DOTFILES_FORCE_REINSTALL
	while true; do
		if [[ "$need_git_prompt" == "true" ]]; then
			is_on git_identity && prompt_git_identity
			need_git_prompt=false
		fi
		show_plan
		if [[ -n "${_CONFIRM_NOTICE:-}" ]]; then
			tty_printf '%s\n\n' "$_CONFIRM_NOTICE"
			_CONFIRM_NOTICE=''
		fi
		read_tty_line answer "$(ui_install_confirm_prompt)"
		tty_printf '%s' "${C_RESET:-}"
		case "$answer" in
		c | C)
			DOTFILES_FORCE_REINSTALL=0
			return 0
			;;
		# Forced: reinstall what is already present, so a corrupted install can
		# be repaired without deleting things by hand. Git identity is
		# unaffected -- it needs answers this screen already has.
		x | X)
			DOTFILES_FORCE_REINSTALL=1
			tty_printf '\n%s\n' "  Forced reinstall: already-installed components will be reinstalled."
			return 0
			;;
		e | E)
			component_menu || return 1
			need_git_prompt=true
			;;
		q | Q)
			tty_printf '\n%s\n' "  Returning to Dotfiles menu."
			return 1
			;;
		# Carried, not printed: the loop redraws the plan next, and ui_clear
		# would take this with it before it could be read.
		*) _CONFIRM_NOTICE="  Invalid choice." ;;
		esac
	done
}

print_status_summary_all() {
	local row result detail short_label
	local -a rows=()
	local ok_count=0 check_count=0 miss_count=0
	local cols status_output="${DOTFILES_STATUS_OUTPUT:-$(tty_output_path)}"

	# The same width the rows use: rt_print_table_row settles its own through
	# rt_report_columns, which honours DOTFILES_REPORT_COLS, and measuring the
	# header a second way made one screen mean two widths.
	cols="$(rt_report_columns)"
	collect_component_status_rows rows

	{
		ui_clear
		printf '\n'
		ui_print_header "Check Status" "Dotfiles › Check Status" "$cols"
		rt_print_table_columns

		for row in "${rows[@]}"; do
			IFS='|' read -r short_label detail result <<<"$row"
			# The shared vocabulary; see status_result_class.
			case "$(status_result_class "$result")" in
			ok) ((++ok_count)) ;;
			miss) ((++miss_count)) ;;
			*) ((++check_count)) ;;
			esac
			rt_print_table_row "$short_label" "$detail" "$result"
		done

		# One call: each branch passed a zero the variable already held, so all
		# three were the same call written three ways.
		rt_print_rollup "$ok_count" "$check_count" "$miss_count"
	} >"$status_output"
}
