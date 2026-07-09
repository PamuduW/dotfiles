# shellcheck shell=bash

AGENT_BOOTSTRAP_REPO_URL="${AGENT_BOOTSTRAP_REPO_URL:-git@github.com:PamuduW/agent_bootstrap.git}"

_AGENTS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib"
# shellcheck source=scripts/lib/agents_status_report.sh
source "$_AGENTS_LIB_DIR/agents_status_report.sh"
# shellcheck source=scripts/lib/git_sync_report.sh
source "$_AGENTS_LIB_DIR/git_sync_report.sh"

_agents_menu_labels=(
	"Check status"
	"Clone/update repo"
	"Run full bootstrap"
	"Refresh skills only"
	"Link agentboot"
	"Scaffold repo (agentboot)"
	"Run doctor"
	"Back"
)
_agents_menu_keys=(status repo bootstrap skills link agentboot doctor back)

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
			( cd "$ab_home" && AGENT_BOOTSTRAP_TUI=1 ./install.sh )
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
			( cd "$ab_home" && AGENT_BOOTSTRAP_TUI=1 ./install.sh skills update )
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
		( cd "$ab_home" && AGENT_BOOTSTRAP_TUI=1 ./install.sh doctor ) || doctor_rc=$?
		if (( doctor_rc != 0 )); then
			echo "Warning: doctor reported issues (exit $doctor_rc)" >&2
		fi
		;;
	esac
}

agents_menu() {
	menu_submenu_loop "Agents" "Dotfiles › Agents" \
		_agents_menu_labels _agents_menu_keys _agents_dispatch
}
