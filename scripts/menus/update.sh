# shellcheck shell=bash

run_update_flow() {
	local dotfiles_cmd tty_path="${DOTFILES_TTY_PATH:-/dev/tty}"

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	{
		printf '\n'
		ui_print_header "Update" "Dotfiles › Update"
	} >"$tty_path"

	"$dotfiles_cmd" update
}
