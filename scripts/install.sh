#!/usr/bin/env bash
# shellcheck disable=SC1091  # Runtime sources are rooted beneath DOTFILES_DIR.
set -euo pipefail

# --------------------------------------------
# WSL/Debian/Ubuntu interactive bootstrap
# - Prompts for git identity
# - Toggle menu to select components
# - Shows execution plan for review
# - Installs only selected components
# --------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" ]]; then
	DOTFILES_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
fi
# shellcheck disable=SC2034  # Consumed by sourced component/install modules.
PKG_FILE="$DOTFILES_DIR/packages/packages.txt"

DOTFILES_INTERACTIVE_TTY=false
if [[ -t 0 ]]; then
	DOTFILES_INTERACTIVE_TTY=true
fi

_clean_log_stream() {
	perl -pe '
		s/\r/\n/g;
		s/\e\[[0-9;?]*[ -\/]*[@-~]//g;
		s/\e\][^\a]*(?:\a|\e\\)//g;
	' | sed -u 's/[[:space:]]*$//'
}

LOG_DIR="$DOTFILES_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d_%H-%M-%S').log"
RAW_LOG_FILE="${LOG_FILE}.raw"

finalize_log_file() {
	[[ -f "$RAW_LOG_FILE" ]] || return 0
	_clean_log_stream <"$RAW_LOG_FILE" >"$LOG_FILE"
	rm -f "$RAW_LOG_FILE"
}

trap finalize_log_file EXIT
exec > >(tee -a "$RAW_LOG_FILE") 2>&1

# shellcheck source=scripts/lib/load.sh
source "$DOTFILES_DIR/scripts/lib/load.sh"
# shellcheck source=scripts/lib/installers/load.sh
source "$DOTFILES_DIR/scripts/lib/installers/load.sh"
# shellcheck source=scripts/lib/components/load.sh
source "$DOTFILES_DIR/scripts/lib/components/load.sh"
# shellcheck source=scripts/menus/helpers.sh
source "$DOTFILES_DIR/scripts/menus/helpers.sh"
# shellcheck source=scripts/menus/main.sh
source "$DOTFILES_DIR/scripts/menus/main.sh"
# shellcheck source=scripts/menus/initial_setup.sh
source "$DOTFILES_DIR/scripts/menus/initial_setup.sh"
# shellcheck source=scripts/menus/update.sh
source "$DOTFILES_DIR/scripts/menus/update.sh"
# shellcheck source=scripts/menus/github_token.sh
source "$DOTFILES_DIR/scripts/menus/github_token.sh"
# shellcheck source=scripts/menus/command_lib.sh
source "$DOTFILES_DIR/scripts/menus/command_lib.sh"
# shellcheck source=scripts/menus/package_lib.sh
source "$DOTFILES_DIR/scripts/menus/package_lib.sh"
# shellcheck source=scripts/menus/agentbot.sh
source "$DOTFILES_DIR/scripts/menus/agentbot.sh"

SETUP_GIT_NAME=""
SETUP_GIT_EMAIL=""
TOGGLE_MSG=""

is_on() { [[ "${COMP_ON[$1]}" -eq 1 ]]; }

prompt_git_identity() {
	local current_name current_email
	current_name="$(git config --global user.name 2>/dev/null || true)"
	current_email="$(git config --global user.email 2>/dev/null || true)"

	echo ""
	echo "Git identity (press Enter to keep default):"
	read_tty_line SETUP_GIT_NAME "  Name [${current_name:-}]: "
	SETUP_GIT_NAME="${SETUP_GIT_NAME:-$current_name}"

	read_tty_line SETUP_GIT_EMAIL "  Email [${current_email:-}]: "
	SETUP_GIT_EMAIL="${SETUP_GIT_EMAIL:-$current_email}"
}

toggle_component() {
	local idx="$1"
	local key="${COMP_KEYS[$idx]}"
	TOGGLE_MSG=""

	if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
		COMP_ON["$key"]=0
		local i
		for i in "${!COMP_DEPS[@]}"; do
			if [[ "${COMP_DEPS[$i]}" -eq "$idx" ]]; then
				local dep_key="${COMP_KEYS[$i]}"
				if [[ "${COMP_ON[$dep_key]}" -eq 1 ]]; then
					COMP_ON["$dep_key"]=0
					TOGGLE_MSG+="auto-disabled: ${COMP_LABELS[$i]}  "
				fi
			fi
		done
	else
		COMP_ON["$key"]=1
		local req="${COMP_DEPS[$idx]}"
		if [[ "$req" -ne -1 ]]; then
			local req_key="${COMP_KEYS[$req]}"
			if [[ "${COMP_ON[$req_key]}" -eq 0 ]]; then
				COMP_ON["$req_key"]=1
				TOGGLE_MSG+="auto-enabled: ${COMP_LABELS[$req]}"
			fi
		fi
	fi
}

print_usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --initial     Open initial setup submenu (or run setup non-interactively)
  --update      Open update submenu
  --agents      Open agents bootstrap submenu
  --help        Show this help and exit

Without options on an interactive terminal, shows the main menu (loops until Quit).
Non-interactive runs (no TTY stdin, CI, piped) default to initial setup.
EOF
}

main() {
	if ! command -v apt-get >/dev/null 2>&1; then
		echo "Error: apt-get not found. This installer targets Debian/Ubuntu." >&2
		exit 1
	fi

	local mode=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--initial)
			mode="initial"
			shift
			;;
		--update)
			mode="update"
			shift
			;;
		--agents)
			mode="agents"
			shift
			;;
		--help | -h)
			print_usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			print_usage >&2
			exit 1
			;;
		esac
	done

	if [[ -z "$mode" ]]; then
		if [[ "$DOTFILES_INTERACTIVE_TTY" == true ]]; then
			main_menu_loop
			return 0
		fi
		run_initial_setup_flow
		return 0
	fi

	case "$mode" in
	initial)
		if [[ "$DOTFILES_INTERACTIVE_TTY" == true ]]; then
			initial_setup_menu
		else
			run_initial_setup_flow
		fi
		;;
	update)
		run_update_flow
		;;
	agents)
		dotfiles_launch_agentbot
		;;
	*)
		printf 'unknown mode: %s\n' "$mode" >&2
		exit 1
		;;
	esac
}

main "$@"
