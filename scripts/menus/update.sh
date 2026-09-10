# shellcheck shell=bash

# The update workflow lives in the `dotfiles` CLI, which owns its own library
# set (update_workflow.sh, full_update.sh). The menu process does not load
# those, so both menu actions delegate to the CLI through one helper.
_run_dotfiles_subcommand() {
	local dotfiles_cmd rc=0
	declare -F start_action_log >/dev/null 2>&1 && start_action_log

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	"$dotfiles_cmd" "$@" || rc=$?
	return "$rc"
}

run_update_flow() {
	_run_dotfiles_subcommand update
}

# Typing `dotfiles full-update` is the authorization on the CLI, so the menu
# asks once before starting the unattended flow.
#
# c/x rather than y/n: the execution plan already spends those two keys on
# "confirm" and "confirm forced", and a forced full update is the same request
# as a forced install. One key, one meaning, in both places.
run_full_update_flow() {
	local answer='' notice=''
	while true; do
		ui_print_header 'Full Update' 'Dotfiles › Full Update'
		printf '  Updates Dotfiles, then installs and updates Agentbot.\n'
		printf '  Application prompts are auto-approved.\n'
		printf '  Replaceable local Git state in both repositories may be backed up and replaced.\n\n'
		printf '  x reinstalls components that are already present.\n\n'
		if [[ -n "$notice" ]]; then
			printf '%s\n\n' "$notice"
			notice=''
		fi
		# A failed read is EOF or a closed terminal, not an answer. Without
		# this the loop redraws and asks again forever, printing "Invalid
		# choice." at whatever speed the terminal can take it.
		if ! read_tty_line answer "$(ui_full_update_confirm_prompt)"; then
			printf '\n  Full update cancelled.\n'
			return 0
		fi
		printf '%s' "${C_RESET:-}"
		case "$answer" in
		c | C)
			return_full_update_run
			return $?
			;;
		x | X)
			printf '\n  Forced reinstall: already-installed components will be reinstalled.\n'
			return_full_update_run --force
			return $?
			;;
		q | Q)
			printf '\n  Full update cancelled.\n'
			return 0
			;;
		# Carried, not printed: the loop redraws the screen next, and ui_clear
		# would take this with it before it could be read.
		*) notice='  Invalid choice.' ;;
		esac
	done
}

return_full_update_run() {
	_run_dotfiles_subcommand full-update "$@"
}

# The Dotfiles command the menu has no entry for otherwise. Read-only, so it
# runs straight through; the CLI owns the report.
run_doctor_flow() {
	_run_dotfiles_subcommand doctor
}

# --list is what the operator wants first; --last is one key away rather than a
# second menu entry, because it is the same command with a different argument.
run_logs_flow() {
	local answer='' rc=0
	_run_dotfiles_subcommand logs --list || return $?
	printf '\n'
	read_tty_line answer "  $(ui_format_shortcuts l 'show newest in full' q back_to_menu) : ${C_RESET:-}"
	case "$answer" in
	l | L)
		printf '\n'
		_run_dotfiles_subcommand logs --last || rc=$?
		;;
	esac
	return "$rc"
}

# Mutating, and it rewrites links in the operator's home directory, so it asks
# first -- typing `dotfiles restow` is the authorization on the CLI side.
run_restow_flow() {
	ui_print_header 'Restow' 'Dotfiles › Restow'
	printf '  Re-applies the bash, bin, and readline stow packages.\n'
	printf '  Replaces the matching links in %s; installs nothing.\n\n' "$HOME"
	if ! ui_confirm_yes_no '  Re-apply the stow links?'; then
		printf '  Restow cancelled.\n'
		return 0
	fi
	printf '\n'
	_run_dotfiles_subcommand restow
}
