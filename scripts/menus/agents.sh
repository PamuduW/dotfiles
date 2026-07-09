# shellcheck shell=bash

AGENT_BOOTSTRAP_REPO_URL="${AGENT_BOOTSTRAP_REPO_URL:-https://github.com/PamuduW/agent_bootstrap.git}"

_agents_menu_labels=(
	"Check status"
	"── Repo ──"
	"Clone/update agent_bootstrap repo"
	"── Setup ──"
	"Run full bootstrap"
	"Update skills"
	"Link agentboot"
	"── Workspace ──"
	"Scaffold repo (agentboot)"
	"── Health ──"
	"Run doctor"
	"Back"
)
_agents_menu_keys=(
	status header repo header bootstrap skills link header agentboot header doctor back
)
_agents_menu_types=(
	"" header "" header "" "" "" header "" header "" ""
)

resolve_agent_bootstrap_home() {
	local candidate

	if [[ -n "${AGENT_BOOTSTRAP_HOME:-}" && -x "${AGENT_BOOTSTRAP_HOME}/install.sh" ]]; then
		printf '%s\n' "$AGENT_BOOTSTRAP_HOME"
		return 0
	fi

	for candidate in \
		"${HOME}/Dev/agent_bootstrap" \
		"${HOME}/Dev/new_setup/agent_bootstrap" \
		"$(dirname "$DOTFILES_DIR")/agent_bootstrap"; do
		if [[ -x "$candidate/install.sh" ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	printf '%s\n' "${HOME}/Dev/agent_bootstrap"
}

clone_or_update_agent_bootstrap() {
	local ab_home="$1"
	local parent_dir answer

	parent_dir="$(dirname "$ab_home")"
	mkdir -p "$parent_dir"

	if [[ -d "$ab_home/.git" ]]; then
		echo "Fetching agent_bootstrap at ${ab_home}..."
		git -C "$ab_home" fetch --prune
		echo ""
		read_tty_line answer "Proceed with git pull? [y/N]: "
		case "$answer" in
		y | Y | yes | YES) git -C "$ab_home" pull --ff-only ;;
		*) echo "Pull skipped." ;;
		esac
	elif [[ -d "$ab_home" ]]; then
		echo "Error: ${ab_home} exists but is not a git repository." >&2
		return 1
	else
		echo "Cloning agent_bootstrap to ${ab_home}..."
		git clone "$AGENT_BOOTSTRAP_REPO_URL" "$ab_home"
	fi
}

require_agent_bootstrap_installer() {
	local ab_home="$1"
	if [[ -x "$ab_home/install.sh" ]]; then
		return 0
	fi
	echo "Error: ${ab_home}/install.sh not found." >&2
	echo "Run 'Clone/update agent_bootstrap repo' first." >&2
	return 1
}

print_agents_status() {
	local ab_home branch dirty link_target
	local cols
	ab_home="$(resolve_agent_bootstrap_home)"
	cols="$(menu_tty_cols)"

	{
		printf '\n'
		ui_print_header "Agents status" "Dotfiles › Agents" "$cols"
		printf '%-24s | %-32s | %s\n' "check" "detail" "result"
		printf '%s\n' "-------------------------+----------------------------------+----------"

		ui_print_status_row "agent_bootstrap" "ok" "$ab_home"

		if [[ -d "$ab_home/.git" ]]; then
			branch="$(git -C "$ab_home" branch --show-current 2>/dev/null || echo '?')"
			dirty="$(git -C "$ab_home" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
			ui_print_status_row "git branch" "ok" "$branch"
			if [[ "$dirty" -eq 0 ]]; then
				ui_print_status_row "dirty files" "ok" "0"
			else
				ui_print_status_row "dirty files" "check" "$dirty"
			fi
		else
			ui_print_status_row "git" "missing" "not a repo"
		fi

		if [[ -x "$ab_home/install.sh" ]]; then
			ui_print_status_row "install.sh" "ok" "$ab_home/install.sh"
		else
			ui_print_status_row "install.sh" "missing" "$ab_home/install.sh"
		fi

		if [[ -x "$ab_home/bin/agentboot" ]]; then
			ui_print_status_row "agentboot bin" "ok" "$ab_home/bin/agentboot"
		else
			ui_print_status_row "agentboot bin" "missing" "$ab_home/bin/agentboot"
		fi

		if command -v python3 >/dev/null 2>&1; then
			ui_print_status_row "python3" "ok" "$(command -v python3)"
		else
			ui_print_status_row "python3" "missing"
		fi

		if command -v node >/dev/null 2>&1; then
			ui_print_status_row "node" "ok" "$(command -v node)"
		else
			ui_print_status_row "node" "missing"
		fi

		if command -v npx >/dev/null 2>&1; then
			ui_print_status_row "npx" "ok" "$(command -v npx)"
		else
			ui_print_status_row "npx" "missing"
		fi

		if [[ -L "$HOME/bin/agentboot" ]]; then
			link_target="$(readlink "$HOME/bin/agentboot")"
			ui_print_status_row "~/bin/agentboot" "ok" "$link_target"
		else
			ui_print_status_row "~/bin/agentboot" "missing"
		fi
	} >/dev/tty

	if [[ -x "$ab_home/install.sh" ]]; then
		echo ""
		local status_rc=0
		( cd "$ab_home" && ./install.sh status ) || status_rc=$?
		if (( status_rc != 0 )); then
			echo "Warning: install.sh status failed (exit $status_rc)" >&2
		fi
	fi
}

_agents_dispatch() {
	local action="$1"
	local ab_home answer target_dir agentboot_args=()

	ab_home="$(resolve_agent_bootstrap_home)"

	case "$action" in
	status)
		ui_clear
		print_agents_status
		;;
	header) ;;
	repo)
		ui_clear
		clone_or_update_agent_bootstrap "$ab_home"
		;;
	bootstrap)
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		echo "Runs skills install, Claude bridge, global render, and doctor."
		read_tty_line answer "Proceed with full bootstrap? [y/N]: "
		case "$answer" in
		y | Y | yes | YES) ( cd "$ab_home" && ./install.sh ) ;;
		*) echo "Bootstrap cancelled." ;;
		esac
		;;
	skills)
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		read_tty_line answer "Proceed with skills update? [y/N]: "
		case "$answer" in
		y | Y | yes | YES) ( cd "$ab_home" && ./install.sh skills update ) ;;
		*) echo "Skills update cancelled." ;;
		esac
		;;
	link)
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		( cd "$ab_home" && ./install.sh link-agentboot )
		;;
	agentboot)
		require_agent_bootstrap_installer "$ab_home" || return 1
		if [[ ! -x "$ab_home/bin/agentboot" ]]; then
			echo "Error: ${ab_home}/bin/agentboot not found." >&2
			return 1
		fi
		ui_clear
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
		require_agent_bootstrap_installer "$ab_home" || return 1
		ui_clear
		local doctor_rc=0
		( cd "$ab_home" && ./install.sh doctor ) || doctor_rc=$?
		if (( doctor_rc != 0 )); then
			echo "Warning: doctor reported issues (exit $doctor_rc)" >&2
		fi
		;;
	esac
}

agents_menu() {
	while true; do
		MENU_SIMPLE_TITLE="Agents Bootstrap"
		MENU_SIMPLE_BREADCRUMB="Dotfiles › Agents"
		MENU_SIMPLE_HINT="Up/Down navigate   Enter confirm"
		MENU_SIMPLE_LABELS=("${_agents_menu_labels[@]}")
		MENU_SIMPLE_KEYS=("${_agents_menu_keys[@]}")
		MENU_SIMPLE_TYPES=("${_agents_menu_types[@]}")

		local choice=''
		if ! choice="$(menu_simple_run)"; then
			return 0
		fi
		[[ "$choice" == "back" ]] && return 0
		[[ "$choice" == "header" ]] && continue

		_agents_dispatch "$choice"
		ui_pause
	done
}
