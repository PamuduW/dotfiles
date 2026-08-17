# shellcheck shell=bash

run_update_flow() {
	local dotfiles_cmd
	local rc=0
	declare -F start_action_log >/dev/null 2>&1 && start_action_log

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	"$dotfiles_cmd" update || rc=$?
	return "$rc"
}
