# shellcheck shell=bash

_update_labels=(
	"Run"
	"Back"
)
_update_keys=(run back)

_update_desc_fn() {
	case "$1" in
	0)
		echo "Run the repo-first update workflow."
		echo "Optionally include Node.js, Go, and Monaspace with --all."
		;;
	1)
		echo "Return to the main Dotfiles menu."
		;;
	esac
}

_update_dispatch() {
	case "$1" in
	run) run_update_flow ;;
	esac
}

update_menu() {
	MENU_SUBMENU_DESC_FN=_update_desc_fn
	menu_submenu_loop "Update" "Dotfiles › Update" \
		_update_labels _update_keys _update_dispatch
}

run_update_flow() {
	local dotfiles_cmd answer tty_path="${DOTFILES_TTY_PATH:-/dev/tty}"

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	{
		printf '\n'
		ui_print_header "Update" "Dotfiles › Update"
		printf '\n'
	} >"$tty_path"

	read_tty_line answer "Include Node.js, Go, and Monaspace fonts (--all)? [y/N]: "
	case "$answer" in
	y | Y | yes | YES)
		"$dotfiles_cmd" update --all
		;;
	*)
		"$dotfiles_cmd" update
		;;
	esac
}
