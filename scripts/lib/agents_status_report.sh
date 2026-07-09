# shellcheck shell=bash
# Agents menu status report (paths, git, toolchain, skills via install.sh).

# shellcheck source=scripts/lib/agents_report_helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/agents_report_helpers.sh"

print_agents_status() {
	local ab_home clone_home branch dirty link_target ab_result cols
	local install_path agentboot_path dotfiles_root foreign_home=''
	local remote sha sync_line ahead_behind node_ver
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
		ui_print_header "Agents status" "Dotfiles › Agents" "$cols"

		ui_print_report_section_block "── Repo & paths ──"
		if [[ -n "$dotfiles_root" ]]; then
			_agents_print_row "dotfiles repo" "$dotfiles_root" ok
		else
			_agents_print_row "dotfiles repo" "not found" check
		fi

		if [[ -n "$ab_home" ]]; then
			ab_result=ok
		elif [[ -d "$clone_home" ]]; then
			ab_result=check
		else
			ab_result=missing
		fi
		_agents_print_row "agent_bootstrap" "$clone_home" "$ab_result"

		if [[ -n "$foreign_home" && "$foreign_home" != "$clone_home" ]] && \
			[[ -x "$foreign_home/install.sh" ]]; then
			_agents_print_row "other install" "$foreign_home" check
			printf '  %sUnset AGENT_BOOTSTRAP_HOME or use canonical path %s%s\n' \
				"$C_DIM" "$clone_home" "$C_RESET"
		fi

		install_path="${ab_home:+$ab_home/install.sh}"
		install_path="${install_path:-$clone_home/install.sh}"
		if [[ -n "$ab_home" && -x "$ab_home/install.sh" ]]; then
			_agents_print_row "install.sh" "$install_path" ok
		else
			_agents_print_row "install.sh" "$install_path" missing
		fi

		agentboot_path="${ab_home:+$ab_home/bin/agentboot}"
		agentboot_path="${agentboot_path:-$clone_home/bin/agentboot}"
		if [[ -n "$ab_home" && -x "$ab_home/bin/agentboot" ]]; then
			_agents_print_row "agentboot bin" "$agentboot_path" ok
		else
			_agents_print_row "agentboot bin" "$agentboot_path" missing
		fi

		if [[ -L "$HOME/bin/agentboot" ]]; then
			link_target="$(readlink "$HOME/bin/agentboot")"
			_agents_print_row "~/bin/agentboot" "$link_target" ok
		else
			_agents_print_row "~/bin/agentboot" "not linked" missing
		fi

		if [[ -n "$ab_home" && -d "$ab_home/.git" ]]; then
			ui_print_report_section_block "── Git ──"
			branch="$(git -C "$ab_home" branch --show-current 2>/dev/null || echo '?')"
			sha="$(git -C "$ab_home" rev-parse --short HEAD 2>/dev/null || echo '?')"
			sync_line="$(git -C "$ab_home" status -sb 2>/dev/null | head -1 || true)"
			ahead_behind="${sync_line#*${branch} }"
			[[ "$ahead_behind" == "$sync_line" ]] && ahead_behind=""
			remote="$(git -C "$ab_home" remote get-url origin 2>/dev/null || echo '')"

			_agents_print_row "git branch" "$branch" ok
			_agents_print_row "git commit" "$sha" ok
			if [[ -n "$remote" ]]; then
				_agents_print_row "git remote" "$remote" ok
			fi
			if [[ -n "$ahead_behind" ]]; then
				_agents_print_row "git sync" "$ahead_behind" check
			else
				_agents_print_row "git sync" "up to date" ok
			fi
			dirty="$(git -C "$ab_home" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
			if [[ "$dirty" -eq 0 ]]; then
				_agents_print_row "dirty files" "0" ok
			else
				_agents_print_row "dirty files" "$dirty" check
			fi
		elif [[ -n "$ab_home" ]]; then
			ui_print_report_section_block "── Git ──"
			_agents_print_row "git" "not a repo" missing
		fi

		ui_print_report_section_block "── Toolchain ──"
		if command -v python3 >/dev/null 2>&1; then
			_agents_print_row "python3" "$(command -v python3)" ok
		else
			_agents_print_row "python3" "not found" missing
		fi

		if command -v node >/dev/null 2>&1; then
			node_ver="$(node --version 2>/dev/null || true)"
			_agents_print_row "node" "${node_ver:+$node_ver — }$(command -v node)" ok
		else
			_agents_print_row "node" "not found" missing
		fi

		if command -v npx >/dev/null 2>&1; then
			_agents_print_row "npx" "$(command -v npx)" ok
		else
			_agents_print_row "npx" "not found" missing
		fi

		if [[ -n "$ab_home" && -f "$ab_home/skills.sources.yaml" ]]; then
			ui_print_report_section_block "── Skills ──"
			status_json="$(_agent_bootstrap_status_json "$ab_home" 2>/dev/null || true)"
			if [[ -n "$status_json" ]]; then
				installed="$(_agent_json_get "$status_json" installed_skills 2>/dev/null || echo 0)"
				enabled="$(_agent_json_get "$status_json" enabled_sources 2>/dev/null || echo 0)"
				lock_skills="$(_agent_json_get "$status_json" global_lock_skills 2>/dev/null || echo 0)"
				bridge="$(_agent_json_get "$status_json" claude_bridge_links 2>/dev/null || echo 0)"
				doctor_issues="$(_agent_json_get "$status_json" doctor_issue_count 2>/dev/null || echo 0)"

				_agents_print_row "skills manifest" "${enabled} enabled source(s)" ok
				_agents_print_row "installed skills" "$installed on disk" \
					"$([[ "$installed" -gt 0 ]] && echo ok || echo check)"
				if [[ "$lock_skills" -gt 0 ]]; then
					_agents_print_row "global skill lock" \
						"~/.agents/.skill-lock.json ($lock_skills pinned)" ok
				else
					_agents_print_row "global skill lock" "~/.agents/.skill-lock.json" check
				fi
				_agents_print_row "claude bridge" "$bridge symlink(s)" \
					"$([[ "$bridge" -gt 0 ]] && echo ok || echo check)"
				if [[ -f "$ab_home/global/AGENTS.md" ]]; then
					_agents_print_row "global AGENTS.md" "global/AGENTS.md" ok
				else
					_agents_print_row "global AGENTS.md" "global/AGENTS.md" missing
				fi
				_agents_print_row "doctor" \
					"$([[ "$doctor_issues" -eq 0 ]] && echo 'no issues' || echo "$doctor_issues issue(s)")" \
					"$([[ "$doctor_issues" -eq 0 ]] && echo ok || echo check)"
			else
				_agents_print_row "skills status" "install.sh status --json unavailable" check
				printf '  %sRun Clone/update repo, then ./install.sh doctor from agent_bootstrap.%s\n' \
					"$C_DIM" "$C_RESET"
			fi
		fi

		ui_print_report_rollup "$_agents_ok_count" "$_agents_check_count" "$_agents_miss_count"
	} >/dev/tty
}
