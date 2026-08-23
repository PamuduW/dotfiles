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
	full_update)
		echo "Update Dotfiles, then install and update Agentbot, without prompts."
		echo "Auto-approves application prompts and may replace replaceable local Git state."
		;;
	github_token)
		echo "Configure the optional shared GitHub API token."
		echo "Missing or malformed state falls back to anonymous access."
		;;
	libraries)
		echo "Open the Dotfiles command and package libraries."
		echo "Read-only references for commands and supported packages."
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
	"Full Update (Dotfiles + Agentbot)"
	"GitHub Token Config"
	"Libraries"
	"Quit"
)
_main_menu_keys=(status install update full_update github_token libraries quit)

_main_menu_unavailable() {
	local message="$1"
	printf '%s\n' "$message"
	ui_pause
}

_main_menu_run_direct_action() {
	local action_fn="$1" rc=0 skip_pause=false
	ui_clear
	"$action_fn" || rc=$?
	if ((rc != 0)); then
		if ((rc == 2)); then
			DOTFILES_EXIT_AFTER_REPOSITORY_UPDATE=true
			rc=0
		else
			printf '%sAction failed (exit %d).%s\n' "${C_RED:-}" "$rc" "${C_RESET:-}" >&2
		fi
	fi
	if [[ "${DOTFILES_EXIT_AFTER_REPOSITORY_UPDATE:-false}" == true ]]; then
		skip_pause=true
	fi
	[[ "$skip_pause" == true ]] || ui_pause
	return "$rc"
}

_main_menu_run_child_menu() {
	local menu_fn="$1" rc=0
	"$menu_fn" || rc=$?
	if ((rc != 0)); then
		printf '%sAction failed (exit %d).%s\n' "${C_RED:-}" "$rc" "${C_RESET:-}" >&2
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
	full_update)
		_main_menu_run_direct_action run_full_update_flow
		;;
	github_token)
		_main_menu_dispatch_optional github_token_menu \
			"GitHub Token Config is not available in this phase."
		;;
	libraries)
		_main_menu_dispatch_optional libraries_menu \
			"Libraries are not available in this phase."
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
	DOTFILES_EXIT_AFTER_REPOSITORY_UPDATE=false
	labels=("${_main_menu_labels[@]}")
	keys=("${_main_menu_keys[@]}")

	while true; do
		MENU_SIMPLE_TITLE="Dotfiles"
		MENU_SIMPLE_BREADCRUMB="Dotfiles"
		MENU_SIMPLE_HINT="Up/Down navigate   Enter confirm"
		MENU_SIMPLE_LABELS=("${labels[@]}")
		MENU_SIMPLE_KEYS=("${keys[@]}")
		MENU_SIMPLE_TYPES=()
		MENU_SIMPLE_DESC_FN=_main_menu_desc_fn

		if ! menu_simple_run; then
			continue
		fi
		choice="${MENU_SIMPLE_RESULT:-}"

		if [[ "$choice" == "quit" ]]; then
			return 0
		fi

		_main_menu_dispatch "$choice" || true
		[[ "${DOTFILES_EXIT_AFTER_REPOSITORY_UPDATE:-false}" == true ]] && return 0
	done
}
