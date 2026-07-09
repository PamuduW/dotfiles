# shellcheck shell=bash

AGENT_BOOTSTRAP_REPO_URL="${AGENT_BOOTSTRAP_REPO_URL:-git@github.com:PamuduW/agent_bootstrap.git}"

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

_agent_bootstrap_status_json() {
	local ab_home="$1"

	[[ -d "$ab_home/src/agent_bootstrap" ]] || return 1

	(
		cd "$ab_home" || exit 1
		python3 -m src.agent_bootstrap.cli --root "$ab_home" status --json 2>/dev/null
	) || (
		cd "$ab_home" || exit 1
		./install.sh status --json 2>/dev/null
	)
}

_agent_bootstrap_skills_fallback() {
	local ab_home="$1"
	local installed=0 enabled=0 lock_skills=0 bridge=0 doctor_issues=0
	local lock_file="$HOME/.agents/.skill-lock.json"

	if [[ -d "$HOME/.agents/skills" ]]; then
		installed="$(find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
	fi
	if [[ -f "$ab_home/skills.sources.yaml" ]]; then
		enabled="$(python3 - "$ab_home/skills.sources.yaml" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
current = None
count = 0

def flush():
    global count, current
    if current and current.get("enabled", True) and current.get("repo") and current.get("skills"):
        count += 1
    current = None

for raw in path.read_text(encoding="utf-8").splitlines():
    line = raw.split("#", 1)[0].rstrip()
    if not line.strip():
        continue
    if m := re.match(r"^\s*-\s+id:\s+(.+)$", line):
        flush()
        current = {"enabled": True, "repo": None, "skills": []}
        continue
    if not current:
        continue
    if m := re.match(r"^\s+repo:\s+(.+)$", line):
        value = m.group(1).strip()
        current["repo"] = None if value == "null" else value
    elif re.match(r"^\s+enabled:\s+false\s*$", line):
        current["enabled"] = False
    elif m := re.match(r"^\s+-\s+(.+)$", line):
        current["skills"].append(m.group(1).strip())

flush()
print(count)
PY
)"
	fi
	if [[ -f "$lock_file" ]]; then
		lock_skills="$(python3 - "$lock_file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    print(-1)
    raise SystemExit(0)
skills = data.get("skills")
if isinstance(skills, dict):
    print(len(skills))
elif isinstance(skills, list):
    print(len(skills))
else:
    print(0)
PY
)"
	fi
	if [[ -d "$HOME/.claude/skills" ]]; then
		bridge="$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')"
	fi
	if [[ ! -f "$ab_home/global/AGENTS.md" ]]; then
		doctor_issues=1
	fi

	printf '%s\n' \
		"installed=${installed}" \
		"enabled=${enabled}" \
		"lock_skills=${lock_skills}" \
		"bridge=${bridge}" \
		"doctor_issues=${doctor_issues}"
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
	ok | installed | configured) ((++_agents_ok_count)) ;;
	check | drift | extra) ((++_agents_check_count)) ;;
	missing | failed) ((++_agents_miss_count)) ;;
	skipped*) ;;
	esac
}

_agents_print_row() {
	local component="$1"
	local detail="$2"
	local result="$3"

	_agents_count_row "$result"
	ui_print_report_table_row "$component" "$detail" "$result"
}

_agents_git_upstream_counts() {
	local ab_home="$1"
	local behind=0 ahead=0

	if git -C "$ab_home" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
		# rev-list prints: <ahead> <behind> (left=HEAD-only, right=upstream-only)
		read -r ahead behind < <(
			git -C "$ab_home" rev-list --left-right --count HEAD...'@{upstream}' 2>/dev/null || echo '0 0'
		)
	fi
	printf '%s %s\n' "$behind" "$ahead"
}

_agents_git_one_line_summary() {
	local text="$1"
	text="${text//$'\r'/}"
	text="$(printf '%s\n' "$text" | sed '/^[[:space:]]*$/d' | tail -1)"
	printf '%s' "$text"
}

clone_or_update_agent_bootstrap() {
	local ab_home="$1"
	local cols parent_dir branch remote before_sha after_sha upstream_sha
	local behind ahead fetch_lines pull_lines pull_rc=0
	local fetch_detail pull_detail clone_detail
	local _agents_ok_count=0 _agents_check_count=0 _agents_miss_count=0

	cols="$(menu_tty_cols)"
	parent_dir="$(dirname "$ab_home")"
	mkdir -p "$parent_dir"

	{
		ui_print_header "Clone/update repo" "Dotfiles › Agents" "$cols"
		printf '  %s%s%s\n' "$C_DIM" \
			"Fetches and pulls agent_bootstrap at the dotfiles sibling path." "$C_RESET"

		ui_print_report_section_block "── Target ──"
		_agents_print_row "clone path" "$ab_home" ok

		if [[ -d "$ab_home/.git" ]]; then
			branch="$(git -C "$ab_home" branch --show-current 2>/dev/null || echo '?')"
			before_sha="$(git -C "$ab_home" rev-parse --short HEAD 2>/dev/null || echo '?')"
			remote="$(git -C "$ab_home" remote get-url origin 2>/dev/null || echo 'not configured')"
			_agents_print_row "git branch" "$branch" ok
			_agents_print_row "git remote" "$remote" \
				"$([[ "$remote" != "not configured" ]] && echo ok || echo check)"
			_agents_print_row "git commit" "$before_sha (before)" ok

			ui_print_report_section_block "── Fetch ──"
			fetch_lines="$(git -C "$ab_home" fetch --prune 2>&1 || true)"
			read -r behind ahead < <(_agents_git_upstream_counts "$ab_home")
			upstream_sha="$(git -C "$ab_home" rev-parse --short '@{upstream}' 2>/dev/null || echo '?')"

			if [[ "$behind" -gt 0 ]]; then
				fetch_detail="${behind} commit(s) behind origin · ${before_sha} → ${upstream_sha}"
				_agents_print_row "fetch" "$fetch_detail" check
			elif [[ -n "$fetch_lines" ]]; then
				fetch_detail="$(_agents_git_one_line_summary "$fetch_lines")"
				[[ -z "$fetch_detail" ]] && fetch_detail="up to date with origin"
				_agents_print_row "fetch" "$fetch_detail" ok
			else
				_agents_print_row "fetch" "up to date with origin" ok
			fi

			if [[ "$ahead" -gt 0 ]]; then
				_agents_print_row "local commits" "${ahead} commit(s) ahead of origin" check
			fi

			printf '\n'
			if [[ "$behind" -gt 0 ]]; then
				if ui_confirm_yes_no "Proceed with git pull?"; then
					ui_print_report_section_block "── Pull ──"
					pull_lines="$(git -C "$ab_home" pull --ff-only 2>&1)" || pull_rc=$?
					after_sha="$(git -C "$ab_home" rev-parse --short HEAD 2>/dev/null || echo '?')"

					if [[ "$pull_rc" -eq 0 ]]; then
						if [[ "$pull_lines" == *"Already up to date"* ]]; then
							pull_detail="already up to date"
							_agents_print_row "pull" "$pull_detail" ok
							_agents_print_row "git commit" "$after_sha (unchanged)" ok
						else
							pull_detail="$(_agents_git_one_line_summary "$pull_lines")"
							if [[ "$pull_lines" == *"files changed"* ]]; then
								pull_detail="$(printf '%s\n' "$pull_lines" | grep -E 'files? changed' | tail -1)"
							fi
							[[ -z "$pull_detail" ]] && pull_detail="fast-forward to ${after_sha}"
							_agents_print_row "pull" "$pull_detail" ok
							_agents_print_row "git commit" "${before_sha} → ${after_sha}" ok
						fi
					else
						_agents_print_row "pull" "$(_agents_git_one_line_summary "$pull_lines")" failed
					fi
				else
					printf '  %sPull skipped.%s\n\n' "$C_DIM" "$C_RESET"
					_agents_print_row "pull" "skipped by user" skipped
				fi
			else
				if [[ "$ahead" -gt 0 ]]; then
					printf '  %sLocal branch is %s commit(s) ahead of origin (pull not required).%s\n' \
						"$C_YELLOW" "$ahead" "$C_RESET"
				else
					printf '  %sNo pull needed — already up to date with origin.%s\n' "$C_GREEN" "$C_RESET"
				fi
			fi
		elif [[ -d "$ab_home" ]]; then
			_agents_print_row "git repo" "path exists but is not a git repo" missing
		else
			ui_print_report_section_block "── Clone ──"
			if clone_detail="$(git clone "$AGENT_BOOTSTRAP_REPO_URL" "$ab_home" 2>&1)"; then
				after_sha="$(git -C "$ab_home" rev-parse --short HEAD 2>/dev/null || echo '?')"
				remote="$(git -C "$ab_home" remote get-url origin 2>/dev/null || echo "$AGENT_BOOTSTRAP_REPO_URL")"
				_agents_print_row "clone" "repository created" ok
				_agents_print_row "git remote" "$remote" ok
				_agents_print_row "git commit" "$after_sha" ok
			else
				_agents_print_row "clone" "$(_agents_git_one_line_summary "$clone_detail")" failed
			fi
		fi

		ui_print_report_rollup "$_agents_ok_count" "$_agents_check_count" "$_agents_miss_count"
	} >/dev/tty
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
	local status_json installed enabled lock_skills bridge doctor_issues fallback_line
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
			else
				while IFS= read -r fallback_line; do
					case "$fallback_line" in
					installed=*) installed="${fallback_line#installed=}" ;;
					enabled=*) enabled="${fallback_line#enabled=}" ;;
					lock_skills=*) lock_skills="${fallback_line#lock_skills=}" ;;
					bridge=*) bridge="${fallback_line#bridge=}" ;;
					doctor_issues=*) doctor_issues="${fallback_line#doctor_issues=}" ;;
					esac
				done < <(_agent_bootstrap_skills_fallback "$ab_home")
			fi

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
		fi

		ui_print_report_rollup "$_agents_ok_count" "$_agents_check_count" "$_agents_miss_count"
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
