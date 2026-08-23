# shellcheck shell=bash
# shellcheck disable=SC2034  # CHECK_FUNCS is consumed by update_workflow.sh.
# --- dotfiles repo ---
dotfiles_repo_status() {
	local result_name="${1:-}" state=unchecked ahead=0 behind=0
	if ! command -v git >/dev/null 2>&1; then
		echo "$NOT_INSTALLED|—|skip"
		return
	fi
	local branch local_rev installed available='unchecked' action='unchecked'
	if [[ -n "$result_name" ]]; then
		local -n repo_result_ref="$result_name"
		state="${repo_result_ref[state]:-unchecked}"
		ahead="${repo_result_ref[ahead]:-0}"
		behind="${repo_result_ref[behind]:-0}"
	fi
	branch="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
	local_rev="$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
	installed="${branch}@${local_rev}"
	case "$state" in
	current)
		available='none'
		action='up to date'
		;;
	ahead)
		available="${ahead} local commit(s) ahead"
		action='verified'
		;;
	behind)
		available="${behind} commit(s) behind"
		action='verified'
		;;
	diverged)
		available="${ahead} ahead / ${behind} behind"
		action='blocked'
		;;
	esac
	printf '%s|%s|%s|%s\n' "dotfiles repo" "$installed" "$available" "$action"
	[[ "$action" == blocked ]]
}

# --- Report helpers ---
CHECK_FUNCS=(
	check_apt
	check_graphify_cli
	check_cursor_cli
	check_codex_cli
	check_claude_cli
	check_copilot_cli
	check_lazygit
	check_lazydocker
	check_node
	check_npm
	check_go
	check_monaspace
	dotfiles_repo_status
)
