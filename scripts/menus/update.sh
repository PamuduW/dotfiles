# shellcheck shell=bash

_update_labels=(
	"Update & upgrade"
	"Back"
)
_update_keys=(run back)

_update_dispatch() {
	case "$1" in
	run) run_update_flow ;;
	esac
}

update_menu() {
	menu_submenu_loop "Update" "Dotfiles › Update" \
		_update_labels _update_keys _update_dispatch
}

run_update_flow() {
	local dotfiles_cmd answer

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	"$dotfiles_cmd" update

	echo ""
	read_tty_line answer "Proceed with upgrades? [y/N]: "
	case "$answer" in
	y | Y | yes | YES)
		read_tty_line answer "Include Node.js, Go, and Monaspace fonts (--all)? [y/N]: "
		case "$answer" in
		y | Y | yes | YES)
			"$dotfiles_cmd" upgrade --all
			;;
		*)
			"$dotfiles_cmd" upgrade
			;;
		esac
		;;
	*)
		echo "Skipped upgrades."
		;;
	esac
}
