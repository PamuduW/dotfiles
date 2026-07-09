# shellcheck shell=bash

_main_menu_labels=(
	"Initial setup"
	"Update"
	"Extensions"
	"Agents"
	"Quit"
)
_main_menu_keys=(initial update extensions agents quit)

main_menu_loop() {
	local choice=''

	while true; do
		MENU_SIMPLE_TITLE="Dotfiles"
		MENU_SIMPLE_BREADCRUMB=""
		MENU_SIMPLE_HINT="Up/Down navigate   Enter confirm"
		MENU_SIMPLE_LABELS=("${_main_menu_labels[@]}")
		MENU_SIMPLE_KEYS=("${_main_menu_keys[@]}")
		MENU_SIMPLE_TYPES=()

		if ! choice="$(menu_simple_run)"; then
			continue
		fi

		case "$choice" in
		initial) initial_setup_menu ;;
		update) update_menu ;;
		extensions) extensions_menu ;;
		agents) agents_menu ;;
		quit) exit 0 ;;
		esac
	done
}
