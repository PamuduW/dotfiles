# shellcheck shell=bash

AGENT_BOOTSTRAP_REPO_URL="${AGENT_BOOTSTRAP_REPO_URL:-git@github.com:PamuduW/agent_bootstrap.git}"

_AGENTS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib"
# shellcheck source=scripts/lib/agents_status_report.sh
source "$_AGENTS_LIB_DIR/agents_status_report.sh"
# shellcheck source=scripts/lib/git_sync_report.sh
source "$_AGENTS_LIB_DIR/git_sync_report.sh"
# shellcheck source=scripts/lib/github_token.sh
source "$_AGENTS_LIB_DIR/github_token.sh"

_agents_menu_labels=(
	"Check status"
	"Clone/update repo"
	"Configure GitHub token"
	"Run full bootstrap"
	"Refresh skills only"
	"Link agentboot"
	"Scaffold repo (agentboot)"
	"Run doctor"
	"Back"
)
_agents_menu_keys=(status repo github_token bootstrap skills link agentboot doctor back)

_agents_menu_desc_fn() {
	case "$1" in
	0)
		echo "Show agent_bootstrap install state, paths, and sync summary."
		echo "Read-only report; no changes made."
		;;
	1)
		echo "Clone or pull agent_bootstrap to the configured home path."
		echo "Required before bootstrap, skills refresh, or doctor."
		;;
	2)
		echo "Save a GitHub token outside this repo for bootstrap, skills, and doctor."
		echo "Stored with owner-only permissions; blank input can remove it."
		;;
	3)
		echo "Run full install.sh: skills, Claude bridge, AGENTS.md, doctor, link."
		echo "Confirms before proceeding."
		;;
	4)
		echo "Update globally installed skills from ~/.agents/.skill-lock.json."
		echo "Re-bridges Claude and refreshes Codex symlinks; no new manifest sources."
		;;
	5)
		echo "Symlink agentboot into your PATH via install.sh link-agentboot."
		echo "Use after bootstrap to run agentboot from any directory."
		;;
	6)
		echo "Run agentboot in a target directory to scaffold agent config."
		echo "Optionally add Copilot/Cursor pointers with --full."
		;;
	7)
		echo "Run install.sh doctor to verify install health."
		echo "Reports issues; non-zero exit if problems found."
		;;
	8)
		echo "Return to the main Dotfiles menu."
		;;
	esac
}

run_agent_bootstrap_command() {
	local ab_home="$1"
	shift
	(
		github_token_load || exit 1
		cd "$ab_home" || exit 1
		AGENT_BOOTSTRAP_TUI=1 ./install.sh "$@"
	)
}

require_agent_bootstrap_installer() {
	local ab_home="$1"
	if [[ -x "$ab_home/install.sh" ]]; then
		return 0
	fi
	echo "Error: ${ab_home}/install.sh not found." >&2
	echo "Run 'Clone/update repo' first." >&2
	return 1
}

_agents_dispatch() {
	local action="$1"
	local ab_home clone_home answer target_dir agentboot_args=()

	sync_agent_bootstrap_home_env || true
	ab_home="$(resolve_agent_bootstrap_home || true)"
	clone_home="$(agent_bootstrap_clone_home)" || {
		echo "Error: cannot resolve dotfiles repo — cannot locate agent_bootstrap sibling path." >&2
		return 1
	}

	case "$action" in
	status)
		ui_clear
		print_agents_status
		;;
	repo)
		ui_clear
		if [[ -n "$ab_home" ]]; then
			clone_or_update_agent_bootstrap "$ab_home"
		else
			clone_or_update_agent_bootstrap "$clone_home"
		fi
		;;
	github_token)
		ui_clear
		ui_print_header "Configure GitHub token" "Dotfiles › Agents" "$(menu_tty_cols)"
		echo "Saved outside this repository: $(github_token_file)"
		echo "Leave blank to remove an existing saved token."
		read_tty_secret answer "GitHub token: "
		if [[ -z "$answer" ]]; then
			if [[ -f "$(github_token_file)" ]] && ui_confirm_yes_no "Remove saved GitHub token?"; then
				github_token_remove
				echo "Saved GitHub token removed."
			else
				echo "GitHub token unchanged."
			fi
		elif github_token_write "$answer"; then
			echo "GitHub token saved with owner-only permissions."
		else
			echo "Error: token must be at least 20 letters, numbers, or underscores." >&2
			return 1
		fi
		;;
	bootstrap)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			echo "Run 'Clone/update repo' first." >&2
			return 1
		}
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		ui_print_header "Run full bootstrap" "Dotfiles › Agents" "$(menu_tty_cols)"
		echo "Installs skills from manifest, bridges Claude, renders global AGENTS.md, runs doctor, links agentboot."
		if ui_confirm_yes_no "Proceed with full bootstrap?"; then
			run_agent_bootstrap_command "$ab_home"
		else
			echo "Bootstrap cancelled."
		fi
		;;
	skills)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		ui_print_header "Refresh skills only" "Dotfiles › Agents" "$(menu_tty_cols)"
		echo "Refreshes globally installed skills from ~/.agents/.skill-lock.json."
		echo "Re-bridges Claude and updates Codex symlinks. Does not add new manifest sources."
		echo ""
		if ui_confirm_yes_no "Proceed with skills refresh?"; then
			run_agent_bootstrap_command "$ab_home" skills update
		else
			echo "Skills refresh cancelled."
		fi
		;;
	link)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		ui_print_header "Link agentboot" "Dotfiles › Agents" "$(menu_tty_cols)"
		( cd "$ab_home" && ./install.sh link-agentboot )
		;;
	agentboot)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
		require_agent_bootstrap_installer "$ab_home" || return 1
		if [[ ! -x "$ab_home/bin/agentboot" ]]; then
			echo "Error: ${ab_home}/bin/agentboot not found." >&2
			return 1
		fi
		ui_clear
		ui_print_header "Scaffold repo (agentboot)" "Dotfiles › Agents" "$(menu_tty_cols)"
		read_tty_line answer "Target directory [$(pwd)]: "
		target_dir="${answer:-$(pwd)}"
		target_dir="$(cd "$target_dir" 2>/dev/null && pwd)" || {
			echo "Error: not a directory: ${answer:-$(pwd)}" >&2
			return 1
		}
		read_tty_line answer "Also add Copilot/Cursor pointers (--full)? [y/N]: "
		case "$answer" in
		y | Y | yes | YES) agentboot_args+=(--full) ;;
		esac
		( cd "$target_dir" && AGENT_BOOTSTRAP_HOME="$ab_home" "$ab_home/bin/agentboot" "${agentboot_args[@]}" )
		;;
	doctor)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		ui_print_header "Run doctor" "Dotfiles › Agents" "$(menu_tty_cols)"
		local doctor_rc=0
		run_agent_bootstrap_command "$ab_home" doctor || doctor_rc=$?
		if (( doctor_rc != 0 )); then
			echo "Warning: doctor reported issues (exit $doctor_rc)" >&2
		fi
		;;
	esac
}

agents_menu() {
	MENU_SUBMENU_DESC_FN=_agents_menu_desc_fn
	menu_submenu_loop "Agents" "Dotfiles › Agents" \
		_agents_menu_labels _agents_menu_keys _agents_dispatch
}
