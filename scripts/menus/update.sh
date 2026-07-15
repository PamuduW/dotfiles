# shellcheck shell=bash

run_update_flow() {
	local dotfiles_cmd tty_path="${DOTFILES_TTY_PATH:-/dev/tty}"
	local relaunch_marker="${DOTFILES_UPDATE_RELAUNCH_MARKER:-${TMPDIR:-/tmp}/dotfiles-update-relaunch-${BASHPID}}"
	local rc=0
	DOTFILES_UPDATE_RELAUNCHED=false
	rm -f -- "$relaunch_marker"

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	{
		printf '\n'
		ui_print_header "Update" "Dotfiles › Update"
	} >"$tty_path"

	DOTFILES_RELAUNCH_MARKER="$relaunch_marker" "$dotfiles_cmd" update || rc=$?
	if [[ -e "$relaunch_marker" ]]; then
		DOTFILES_UPDATE_RELAUNCHED=true
		rm -f -- "$relaunch_marker"
	fi
	return "$rc"
}
