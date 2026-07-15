# shellcheck shell=bash

_main_menu_desc_fn() {
	local key="${MENU_SIMPLE_KEYS[$1]:-${_main_menu_keys[$1]:-}}"
	case "$key" in
	status)
		echo "Show install status for every setup component."
		echo "Read-only summary with installed, missing, and check counts."
		;;
	install)
		echo "Choose setup components, review the plan, and install."
		echo "Prompts before applying the selected changes."
		;;
	update)
		echo "Run the repo-first update workflow."
		echo "Fetch/classify first; downstream changes require confirmation."
		;;
	github_token)
		echo "Configure the optional shared GitHub API token."
		echo "Missing or malformed state falls back to anonymous access."
		;;
	command_lib)
		echo "Show Dotfiles commands and their usage."
		echo "Read-only command and mutation matrix."
		;;
	package_lib)
		echo "Browse setup components and package descriptions."
		echo "Read-only catalog; no probes or installers run."
		;;
	agentbot)
		echo "Open the standalone Agentbot setup."
		echo "The sibling is validated before launch and cannot recurse here."
		;;
	quit)
		echo "Exit the Dotfiles menu."
		;;
	esac
}

_main_menu_labels=(
	"Check Status"
	"Install Dotfiles"
	"Update"
	"GitHub Token Config"
	"Command Lib"
	"Package Lib"
	"Agentbot"
	"Quit"
)
_main_menu_keys=(status install update github_token command_lib package_lib agentbot quit)

_main_menu_unavailable() {
	local message="$1"
	printf '%s\n' "$message"
	ui_pause
}

_main_menu_run_direct_action() {
	local action_fn="$1" rc=0
	"$action_fn" || rc=$?
	if ((rc != 0)); then
		printf 'Action failed (exit %d).\n' "$rc" >&2
	fi
	ui_pause
	return "$rc"
}

_main_menu_run_child_menu() {
	local menu_fn="$1" rc=0
	"$menu_fn" || rc=$?
	if ((rc != 0)); then
		printf 'Action failed (exit %d).\n' "$rc" >&2
		ui_pause
	fi
	return "$rc"
}

_main_menu_dispatch_optional() {
	local function_name="$1" unavailable_message="$2"
	if declare -F "$function_name" >/dev/null; then
		_main_menu_run_child_menu "$function_name"
	else
		_main_menu_unavailable "$unavailable_message"
	fi
}

_main_menu_dispatch() {
	case "$1" in
	status)
		_main_menu_run_direct_action run_status_action
		;;
	install)
		_main_menu_run_direct_action run_install_action
		;;
	update)
		_main_menu_run_direct_action run_update_flow
		;;
	github_token)
		_main_menu_dispatch_optional github_token_menu \
			"GitHub Token Config is not available in this phase."
		;;
	command_lib)
		_main_menu_dispatch_optional command_lib_menu \
			"Command Lib is not available in this phase."
		;;
	package_lib)
		_main_menu_dispatch_optional package_lib_menu \
			"Package Lib is not available in this phase."
		;;
	agentbot)
		if declare -F dotfiles_launch_agentbot >/dev/null; then
			dotfiles_launch_agentbot
		else
			_main_menu_unavailable \
				"Agentbot is unavailable until the sibling bridge is installed."
		fi
		;;
	*)
		printf 'Unknown Dotfiles menu action: %s\n' "$1" >&2
		ui_pause
		return 2
		;;
	esac
}

# shellcheck disable=SC2034  # MENU_SIMPLE_* globals are consumed by menu_simple_run.
main_menu_loop() {
	local choice=''
	local -a labels keys
	labels=("${_main_menu_labels[@]}")
	keys=("${_main_menu_keys[@]}")
	if [[ "${SETUP_CALLER:-}" == agentbot ]]; then
		labels=("Check Status" "Install Dotfiles" "Update" "GitHub Token Config" "Command Lib" "Package Lib" "Quit")
		keys=(status install update github_token command_lib package_lib quit)
	fi

	while true; do
		MENU_SIMPLE_TITLE="Dotfiles"
		MENU_SIMPLE_BREADCRUMB="Dotfiles"
		MENU_SIMPLE_HINT="Up/Down navigate   Enter confirm"
		MENU_SIMPLE_LABELS=("${labels[@]}")
		MENU_SIMPLE_KEYS=("${keys[@]}")
		MENU_SIMPLE_TYPES=()
		MENU_SIMPLE_DESC_FN=_main_menu_desc_fn

		if ! choice="$(menu_simple_run)"; then
			continue
		fi

		if [[ "$choice" == "quit" ]]; then
			return 0
		fi

		_main_menu_dispatch "$choice" || true
	done
}
