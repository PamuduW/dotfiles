# shellcheck shell=bash

_main_menu_desc_fn() {
	case "$1" in
	0)
		echo "First-time WSL dotfiles install: pick components and run setup."
		echo "Check status first to see what is already installed."
		;;
	1)
		echo "Pull latest dotfiles repo and optionally run package upgrades."
		echo "Prompts before upgrading Node, Go, fonts, and other tools."
		;;
	2)
		echo "Install and maintain agent_bootstrap (skills, links, doctor)."
		echo "Clone repo, run bootstrap, or scaffold a new project."
		;;
	3)
		echo "Exit the dotfiles menu."
		;;
	esac
}

_main_menu_labels=(
	"Initial setup"
	"Update"
	"Agents"
	"Quit"
)
_main_menu_keys=(initial update agents quit)

main_menu_loop() {
	local choice=''

	while true; do
		MENU_SIMPLE_TITLE="Dotfiles"
		MENU_SIMPLE_BREADCRUMB=""
		MENU_SIMPLE_HINT="Up/Down navigate   Enter confirm"
		MENU_SIMPLE_LABELS=("${_main_menu_labels[@]}")
		MENU_SIMPLE_KEYS=("${_main_menu_keys[@]}")
		MENU_SIMPLE_TYPES=()
		MENU_SIMPLE_DESC_FN=_main_menu_desc_fn

		if ! choice="$(menu_simple_run)"; then
			continue
		fi

		case "$choice" in
		initial) initial_setup_menu ;;
		update) update_menu ;;
		agents) agents_menu ;;
		quit) exit 0 ;;
		esac
	done
}
