# shellcheck shell=bash

AGENT_BOOTSTRAP_REPO_URL="${AGENT_BOOTSTRAP_REPO_URL:-git@github.com:PamuduW/agent_bootstrap.git}"

_agents_menu_labels=(
	"Check status"
	"Clone/update repo"
	"Sync skills fork (legacy)"
	"Run bootstrap"
	"Update skills"
	"Link agentboot"
	"Scaffold repo"
	"Run doctor"
	"Back"
)
_agents_menu_keys=(status repo fork bootstrap skills link agentboot doctor back)

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
	echo "Run 'Clone/update repo' first." >&2
	return 1
}

print_agents_status() {
	local ab_home clone_home branch dirty link_target ab_result cols
	local install_path agentboot_path dotfiles_root foreign_home=''
	local fork_home fork_result fork_sync_result fork_sync_detail=''
	local fork_upstream_branch fork_upstream_ref fork_behind fork_ahead

	clone_home="$(agent_bootstrap_clone_home)" || clone_home="(unknown — dotfiles root not found)"
	if [[ -n "${AGENT_BOOTSTRAP_HOME:-}" && "$AGENT_BOOTSTRAP_HOME" != "$clone_home" && \
		-x "${AGENT_BOOTSTRAP_HOME}/install.sh" ]]; then
		foreign_home="$AGENT_BOOTSTRAP_HOME"
	fi
	sync_agent_bootstrap_home_env || true
	ab_home="$(resolve_agent_bootstrap_home || true)"
	dotfiles_root="$(dotfiles_repo_root || true)"
	cols="$(menu_tty_cols)"

	{
		printf '\n'
		ui_print_header "Agents status" "Dotfiles › Agents" "$cols"
		ui_print_check_result_path_header "$cols"

		if [[ -n "$dotfiles_root" ]]; then
			ui_print_check_result_path_row "dotfiles repo" ok "$dotfiles_root" "$cols"
		else
			ui_print_check_result_path_row "dotfiles repo" check "" "$cols"
		fi

		if [[ -n "$ab_home" ]]; then
			ab_result=ok
		elif [[ -d "$clone_home" ]]; then
			ab_result=check
		else
			ab_result=missing
		fi
		ui_print_check_result_path_row "agent_bootstrap" "$ab_result" "$clone_home" "$cols"

		if [[ -n "$foreign_home" && "$foreign_home" != "$clone_home" ]] && \
			[[ -x "$foreign_home/install.sh" ]]; then
			ui_print_check_result_path_row "other install" check "$foreign_home" "$cols"
		fi

		if [[ -n "$ab_home" && -d "$ab_home/.git" ]]; then
			branch="$(git -C "$ab_home" branch --show-current 2>/dev/null || echo '?')"
			dirty="$(git -C "$ab_home" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
			ui_print_check_result_path_row "git branch" ok "$branch" "$cols"
			if [[ "$dirty" -eq 0 ]]; then
				ui_print_check_result_path_row "dirty files" ok "0" "$cols"
			else
				ui_print_check_result_path_row "dirty files" check "$dirty" "$cols"
			fi
		elif [[ -n "$ab_home" ]]; then
			ui_print_check_result_path_row "git" missing "not a repo" "$cols"
		fi

		install_path="${ab_home:+$ab_home/install.sh}"
		install_path="${install_path:-$clone_home/install.sh}"
		if [[ -n "$ab_home" && -x "$ab_home/install.sh" ]]; then
			ui_print_check_result_path_row "install.sh" ok "$install_path" "$cols"
		else
			ui_print_check_result_path_row "install.sh" missing "$install_path" "$cols"
		fi

		agentboot_path="${ab_home:+$ab_home/bin/agentboot}"
		agentboot_path="${agentboot_path:-$clone_home/bin/agentboot}"
		if [[ -n "$ab_home" && -x "$ab_home/bin/agentboot" ]]; then
			ui_print_check_result_path_row "agentboot bin" ok "$agentboot_path" "$cols"
		else
			ui_print_check_result_path_row "agentboot bin" missing "$agentboot_path" "$cols"
		fi

		if command -v python3 >/dev/null 2>&1; then
			ui_print_check_result_path_row "python3" ok "$(command -v python3)" "$cols"
		else
			ui_print_check_result_path_row "python3" missing "" "$cols"
		fi

		if command -v node >/dev/null 2>&1; then
			ui_print_check_result_path_row "node" ok "$(command -v node)" "$cols"
		else
			ui_print_check_result_path_row "node" missing "" "$cols"
		fi

		if command -v npx >/dev/null 2>&1; then
			ui_print_check_result_path_row "npx" ok "$(command -v npx)" "$cols"
		else
			ui_print_check_result_path_row "npx" missing "" "$cols"
		fi

		if [[ -L "$HOME/bin/agentboot" ]]; then
			link_target="$(readlink "$HOME/bin/agentboot")"
			ui_print_check_result_path_row "~/bin/agentboot" ok "$link_target" "$cols"
		else
			ui_print_check_result_path_row "~/bin/agentboot" missing "" "$cols"
		fi

		fork_home="$(agent_skills_fork_clone_home 2>/dev/null || true)"
		if [[ -n "$fork_home" && -d "$fork_home/.git" ]]; then
			fork_result=ok
			if git -C "$fork_home" rev-parse --verify refs/remotes/upstream/HEAD >/dev/null 2>&1 || \
				git -C "$fork_home" remote get-url upstream >/dev/null 2>&1; then
				fork_upstream_branch="$(agent_skills_fork_upstream_branch "$fork_home")"
				fork_upstream_ref="upstream/${fork_upstream_branch}"
				if git -C "$fork_home" rev-parse --verify "$fork_upstream_ref" >/dev/null 2>&1; then
					read -r fork_behind fork_ahead < <(agent_skills_fork_counts "$fork_home" "$fork_upstream_ref")
					if [[ "$fork_behind" == "0" ]]; then
						fork_sync_result=ok
						fork_sync_detail="up to date"
					else
						fork_sync_result=check
						fork_sync_detail="${fork_behind} behind upstream"
					fi
				else
					fork_sync_result=check
					fork_sync_detail="fetch pending"
				fi
			else
				fork_sync_result=check
				fork_sync_detail="upstream not configured"
			fi
		elif [[ -n "$fork_home" && -d "$fork_home" ]]; then
			fork_result=check
			fork_sync_result=missing
			fork_sync_detail="not a git repo"
		else
			fork_result=missing
			fork_sync_result=missing
			fork_sync_detail="not cloned"
			fork_home="${fork_home:-$(dirname "${dotfiles_root:-$HOME/dotfiles}")/my-agent-skills}"
		fi
		ui_print_check_result_path_row "skills fork" "$fork_result" "$fork_home" "$cols"
		if [[ -n "$fork_sync_detail" ]]; then
			ui_print_check_result_path_row "fork upstream" "$fork_sync_result" "$fork_sync_detail" "$cols"
		fi

		if [[ -n "$ab_home" && -f "$ab_home/skills.sources.yaml" ]]; then
			ui_print_check_result_path_row "skills upstreams" ok "skills.sources.yaml (Update skills)" "$cols"
		fi
	} >/dev/tty

	if [[ -n "$ab_home" && -x "$ab_home/install.sh" ]]; then
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
	fork)
		ui_clear
		ui_print_header "Sync skills fork (legacy)" "Dotfiles › Agents" "$(menu_tty_cols)"
		echo "Legacy fork workflow — checks PamuduW/my-agent-skills against Akindu23/my-agent-skills upstream."
		echo "Preferred: use 'Update skills' (agent_bootstrap install.sh skills update from skills.sources.yaml)."
		echo "Clone path: sibling of dotfiles (~/my-agent-skills when dotfiles is ~/dotfiles)."
		echo ""
		read_tty_line answer "Proceed with legacy fork sync anyway? [y/N]: "
		case "$answer" in
		y | Y | yes | YES) sync_agent_skills_fork ;;
		*) echo "Fork sync cancelled." ;;
		esac
		;;
	bootstrap)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			echo "Run 'Clone/update repo' first." >&2
			return 1
		}
		ui_clear
		ui_print_header "Run bootstrap" "Dotfiles › Agents" "$(menu_tty_cols)"
		echo "Installs skills, bridges Claude, renders global AGENTS.md, runs doctor."
		read_tty_line answer "Proceed with full bootstrap? [y/N]: "
		case "$answer" in
		y | Y | yes | YES) ( cd "$ab_home" && ./install.sh ) ;;
		*) echo "Bootstrap cancelled." ;;
		esac
		;;
	skills)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
		ui_clear
		read_tty_line answer "Proceed with skills update? [y/N]: "
		case "$answer" in
		y | Y | yes | YES) ( cd "$ab_home" && ./install.sh skills update ) ;;
		*) echo "Skills update cancelled." ;;
		esac
		;;
	link)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
		ui_clear
		( cd "$ab_home" && ./install.sh link-agentboot )
		;;
	agentboot)
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
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
		ab_home="$(resolve_agent_bootstrap_home)" || {
			echo "Error: agent_bootstrap not installed at ${clone_home}." >&2
			return 1
		}
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
	menu_submenu_loop "Agents" "Dotfiles › Agents" \
		_agents_menu_labels _agents_menu_keys _agents_dispatch
}
