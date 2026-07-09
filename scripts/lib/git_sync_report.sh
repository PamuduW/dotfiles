# shellcheck shell=bash
# Git clone/update report for agent_bootstrap (Agents menu).

# shellcheck source=scripts/lib/agents_report_helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/agents_report_helpers.sh"

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
