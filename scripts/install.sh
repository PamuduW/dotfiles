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

print_usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --install     Go straight to component selection and install
  --update      Open update workflow
  --force       Reinstall components that are already present
  --help        Show this help and exit

Without options on an interactive terminal, shows the main menu (loops until Quit).
Non-interactive runs (no TTY stdin, CI, piped) default to initial setup.
EOF
}

if [[ $# -eq 1 && ("$1" == --help || "$1" == -h) ]]; then
	print_usage
	exit 0
fi

# shellcheck disable=SC2034  # Consumed by sourced component/install modules.
PKG_FILE="$DOTFILES_DIR/packages/packages.txt"

# shellcheck source=scripts/lib/action_log.sh
source "$DOTFILES_DIR/scripts/lib/action_log.sh"

# shellcheck source=scripts/lib/load.sh
source "$DOTFILES_DIR/scripts/lib/load.sh"

# Whether a person is here to answer, decided by the controlling terminal
# rather than by stdin. `-t 0` is false whenever the installer is a child of
# something reading a pipe -- `curl ... | bash` running bootstrap.sh, most of
# all -- so the component menu was skipped for exactly the operator who was
# sitting there waiting to use it. The menu reads the terminal through the
# shared adapter, so the terminal is what the answer depends on.
DOTFILES_INTERACTIVE_TTY=false
if tty_available; then
	DOTFILES_INTERACTIVE_TTY=true
fi
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
# shellcheck source=scripts/menus/libraries.sh
source "$DOTFILES_DIR/scripts/menus/libraries.sh"

SETUP_GIT_NAME=""
SETUP_GIT_EMAIL=""
TOGGLE_MSG=""

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
	local dependency dependent_key
	TOGGLE_MSG=""

	if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
		COMP_ON["$key"]=0
		for dependent_key in "${!COMP_DEPENDS_ON[@]}"; do
			if [[ "${COMP_DEPENDS_ON[$dependent_key]}" == "$key" && "${COMP_ON[$dependent_key]}" -eq 1 ]]; then
				COMP_ON["$dependent_key"]=0
				TOGGLE_MSG+="auto-disabled: ${COMP_LABELS[$(comp_index_of "$dependent_key")]}  "
			fi
		done
	else
		COMP_ON["$key"]=1
		dependency="$(comp_dependency "$key")"
		if [[ -n "$dependency" ]]; then
			if [[ "${COMP_ON[$dependency]}" -eq 0 ]]; then
				COMP_ON["$dependency"]=1
				TOGGLE_MSG+="auto-enabled: ${COMP_LABELS[$(comp_index_of "$dependency")]}"
			fi
		fi
	fi
}

# Mode dispatch, extracted so the routing can be asserted without driving a
# terminal.
_dotfiles_dispatch_mode() {
	case "$1" in
	install)
		if [[ "$DOTFILES_INTERACTIVE_TTY" == true ]]; then
			run_install_action
		else
			run_initial_setup_flow
		fi
		;;
	update)
		run_update_flow
		;;
	*)
		printf 'unknown mode: %s\n' "$1" >&2
		exit 1
		;;
	esac
}

main() {
	if ! command -v apt-get >/dev/null 2>&1; then
		echo "Error: apt-get not found. This installer targets Debian/Ubuntu." >&2
		exit 1
	fi

	local mode=""

	# Reset, then set from the flag alone. An exported DOTFILES_FORCE_REINSTALL
	# would otherwise force every non-interactive run silently -- the hazard
	# cmd_full_update already refuses, and the same one applies here.
	export DOTFILES_FORCE_REINSTALL=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--initial)
			# Retired on 2026-09-09. It opened a two-entry submenu -- check
			# status, run setup -- that the main menu already offers, and
			# non-interactively it did exactly what --install does. Named
			# explicitly rather than falling into "unknown option", because an
			# operator who learned this flag deserves to be told where it went.
			echo "--initial has been removed; use --install for component selection," >&2
			echo "or run ./install.sh with no options for the menu." >&2
			exit 1
			;;
		--install)
			mode="install"
			shift
			;;
		--update)
			mode="update"
			shift
			;;
		# The unattended equivalent of the execution plan's `x`. On an
		# interactive run the plan screen still asks, and the answer wins.
		--force)
			DOTFILES_FORCE_REINSTALL=1
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
		return $?
	fi

	_dotfiles_dispatch_mode "$mode"
}

# Source-only guard, matching bin/bin/dotfiles and the Agentbot installer, so
# the routing can be loaded and asserted without running a setup.
if [[ "${DOTFILES_SOURCE_ONLY:-0}" != 1 ]]; then
	main "$@"
fi
