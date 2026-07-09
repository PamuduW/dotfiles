# shellcheck shell=bash

AGENT_BOOTSTRAP_REPO_URL="${AGENT_BOOTSTRAP_REPO_URL:-git@github.com:PamuduW/agent_bootstrap.git}"

_agents_menu_labels=(
	"Check status"
	"── Repo ──"
	"Clone/update repo"
	"── Setup ──"
	"Run full bootstrap"
	"Refresh skills only"
	"Link agentboot"
	"── Workspace ──"
	"Scaffold repo (agentboot)"
	"── Health ──"
	"Run doctor"
	"Back"
)
_agents_menu_keys=(status _h1 repo _h2 bootstrap skills link _h3 agentboot _h4 doctor back)
_agents_menu_types=(item header item header item item item header item header item item)

_agent_bootstrap_status_json() {
	local ab_home="$1"
	[[ -x "$ab_home/install.sh" ]] || return 1
	( cd "$ab_home" && ./install.sh status --json 2>/dev/null )
}

_agent_json_get() {
	local json="$1"
	local key="$2"
	python3 - "$json" "$key" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
value = data.get(sys.argv[2])
if value is None:
    raise SystemExit(1)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

_agents_count_row() {
	local result="$1"
	case "$result" in
	ok) _agents_ok_count=$((_agents_ok_count + 1)) ;;
	check | drift | extra) _agents_check_count=$((_agents_check_count + 1)) ;;
	missing | failed) _agents_miss_count=$((_agents_miss_count + 1)) ;;
	esac
}

_agents_print_row() {
	local label="$1"
	local result="$2"
	local path="${3:-}"
	local cols="$4"

	_agents_count_row "$result"
	ui_print_check_result_path_row "$label" "$result" "$path" "$cols"
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
		if ui_confirm_yes_no "Proceed with git pull?"; then
			git -C "$ab_home" pull --ff-only
		else
			echo "Pull skipped."
		fi
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
	local remote sha sync_line ahead_behind node_ver npx_path
	local status_json installed enabled lock_skills bridge doctor_issues
	local _agents_ok_count=0 _agents_check_count=0 _agents_miss_count=0

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
			_agents_print_row "dotfiles repo" ok "$dotfiles_root" "$cols"
		else
			_agents_print_row "dotfiles repo" check "" "$cols"
		fi

		if [[ -n "$ab_home" ]]; then
			ab_result=ok
		elif [[ -d "$clone_home" ]]; then
			ab_result=check
		else
			ab_result=missing
		fi
		_agents_print_row "agent_bootstrap" "$ab_result" "$clone_home" "$cols"

		if [[ -n "$foreign_home" && "$foreign_home" != "$clone_home" ]] && \
			[[ -x "$foreign_home/install.sh" ]]; then
			_agents_print_row "other install" check "$foreign_home" "$cols"
			printf '  %sUnset AGENT_BOOTSTRAP_HOME or use canonical path %s%s\n' \
				"$C_DIM" "$clone_home" "$C_RESET"
		fi

		if [[ -n "$ab_home" && -d "$ab_home/.git" ]]; then
			branch="$(git -C "$ab_home" branch --show-current 2>/dev/null || echo '?')"
			sha="$(git -C "$ab_home" rev-parse --short HEAD 2>/dev/null || echo '?')"
			sync_line="$(git -C "$ab_home" status -sb 2>/dev/null | head -1 || true)"
			ahead_behind="${sync_line#*${branch} }"
			[[ "$ahead_behind" == "$sync_line" ]] && ahead_behind=""

			remote="$(git -C "$ab_home" remote get-url origin 2>/dev/null || echo '')"
			_agents_print_row "git branch" ok "$branch" "$cols"
			_agents_print_row "git commit" ok "$sha" "$cols"
			if [[ -n "$remote" ]]; then
				_agents_print_row "git remote" ok "$remote" "$cols"
			fi
			if [[ -n "$ahead_behind" ]]; then
				_agents_print_row "git sync" check "$ahead_behind" "$cols"
			else
				_agents_print_row "git sync" ok "up to date" "$cols"
			fi
			dirty="$(git -C "$ab_home" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
			if [[ "$dirty" -eq 0 ]]; then
				_agents_print_row "dirty files" ok "0" "$cols"
			else
				_agents_print_row "dirty files" check "$dirty" "$cols"
			fi
		elif [[ -n "$ab_home" ]]; then
			_agents_print_row "git" missing "not a repo" "$cols"
		fi

		install_path="${ab_home:+$ab_home/install.sh}"
		install_path="${install_path:-$clone_home/install.sh}"
		if [[ -n "$ab_home" && -x "$ab_home/install.sh" ]]; then
			_agents_print_row "install.sh" ok "$install_path" "$cols"
		else
			_agents_print_row "install.sh" missing "$install_path" "$cols"
		fi

		agentboot_path="${ab_home:+$ab_home/bin/agentboot}"
		agentboot_path="${agentboot_path:-$clone_home/bin/agentboot}"
		if [[ -n "$ab_home" && -x "$ab_home/bin/agentboot" ]]; then
			_agents_print_row "agentboot bin" ok "$agentboot_path" "$cols"
		else
			_agents_print_row "agentboot bin" missing "$agentboot_path" "$cols"
		fi

		if command -v python3 >/dev/null 2>&1; then
			_agents_print_row "python3" ok "$(command -v python3)" "$cols"
		else
			_agents_print_row "python3" missing "" "$cols"
		fi

		if command -v node >/dev/null 2>&1; then
			node_ver="$(node --version 2>/dev/null || true)"
			_agents_print_row "node" ok "${node_ver:+$node_ver — }$(command -v node)" "$cols"
		else
			_agents_print_row "node" missing "" "$cols"
		fi

		if command -v npx >/dev/null 2>&1; then
			npx_path="$(command -v npx)"
			_agents_print_row "npx" ok "$npx_path" "$cols"
		else
			_agents_print_row "npx" missing "" "$cols"
		fi

		if [[ -L "$HOME/bin/agentboot" ]]; then
			link_target="$(readlink "$HOME/bin/agentboot")"
			_agents_print_row "~/bin/agentboot" ok "$link_target" "$cols"
		else
			_agents_print_row "~/bin/agentboot" missing "" "$cols"
		fi

		if [[ -n "$ab_home" && -f "$ab_home/skills.sources.yaml" ]]; then
			status_json="$(_agent_bootstrap_status_json "$ab_home" || true)"
			if [[ -n "$status_json" ]]; then
				installed="$(_agent_json_get "$status_json" installed_skills 2>/dev/null || echo 0)"
				enabled="$(_agent_json_get "$status_json" enabled_sources 2>/dev/null || echo 0)"
				lock_skills="$(_agent_json_get "$status_json" global_lock_skills 2>/dev/null || echo 0)"
				bridge="$(_agent_json_get "$status_json" claude_bridge_links 2>/dev/null || echo 0)"
				doctor_issues="$(_agent_json_get "$status_json" doctor_issue_count 2>/dev/null || echo 0)"

				_agents_print_row "skills manifest" ok "${enabled} enabled source(s)" "$cols"
				_agents_print_row "installed skills" \
					"$([[ "$installed" -gt 0 ]] && echo ok || echo check)" \
					"$installed on disk" "$cols"
				if [[ "$lock_skills" -gt 0 ]]; then
					_agents_print_row "global skill lock" ok \
						"~/.agents/.skill-lock.json ($lock_skills pinned)" "$cols"
				else
					_agents_print_row "global skill lock" check \
						"~/.agents/.skill-lock.json" "$cols"
				fi
				_agents_print_row "claude bridge" \
					"$([[ "$bridge" -gt 0 ]] && echo ok || echo check)" \
					"$bridge symlink(s)" "$cols"
				if [[ -f "$ab_home/global/AGENTS.md" ]]; then
					_agents_print_row "global AGENTS.md" ok "global/AGENTS.md" "$cols"
				else
					_agents_print_row "global AGENTS.md" missing "global/AGENTS.md" "$cols"
				fi
				_agents_print_row "doctor" \
					"$([[ "$doctor_issues" -eq 0 ]] && echo ok || echo check)" \
					"$([[ "$doctor_issues" -eq 0 ]] && echo 'no issues' || echo "$doctor_issues issue(s)")" \
					"$cols"
			else
				_agents_print_row "skills upstreams" check "status --json unavailable" "$cols"
			fi
		fi

		printf '\n'
		if [[ $_agents_miss_count -eq 0 && $_agents_check_count -eq 0 ]]; then
			printf '  %sAll %d check(s) look good.%s\n' "$C_GREEN" "$_agents_ok_count" "$C_RESET"
		elif [[ $_agents_miss_count -eq 0 ]]; then
			printf '  %s%d ok%s, %s%d need attention%s.\n' \
				"$C_GREEN" "$_agents_ok_count" "$C_RESET" \
				"$C_YELLOW" "$_agents_check_count" "$C_RESET"
		else
			printf '  %s%d ok%s, %s%d missing%s, %s%d need attention%s.\n' \
				"$C_GREEN" "$_agents_ok_count" "$C_RESET" \
				"$C_RED" "$_agents_miss_count" "$C_RESET" \
				"$C_YELLOW" "$_agents_check_count" "$C_RESET"
		fi
	} >/dev/tty
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
		ui_print_header "Clone/update repo" "Dotfiles › Agents" "$(menu_tty_cols)"
		echo "Fetches and optionally pulls agent_bootstrap at the sibling of dotfiles."
		echo ""
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
			( cd "$ab_home" && ./install.sh )
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
			( cd "$ab_home" && ./install.sh skills update )
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
		( cd "$ab_home" && ./install.sh doctor ) || doctor_rc=$?
		if (( doctor_rc != 0 )); then
			echo "Warning: doctor reported issues (exit $doctor_rc)" >&2
		fi
		;;
	esac
}

agents_menu() {
	MENU_SUBMENU_TYPES=("${_agents_menu_types[@]}")
	menu_submenu_loop "Agents" "Dotfiles › Agents" \
		_agents_menu_labels _agents_menu_keys _agents_dispatch
	unset MENU_SUBMENU_TYPES
}
