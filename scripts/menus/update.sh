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
run_full_update_flow() {
	ui_print_header 'Full Update' 'Dotfiles › Full Update'
	printf '  Updates Dotfiles, then installs and updates Agentbot.\n'
	printf '  Application prompts are auto-approved.\n'
	printf '  Replaceable local Git state in both repositories may be backed up and replaced.\n\n'
	if ! ui_confirm_yes_no '  Start the full update?'; then
		printf '  Full update cancelled.\n'
		return 0
	fi

	_run_dotfiles_subcommand full-update
}
