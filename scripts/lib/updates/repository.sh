# shellcheck shell=bash
# shellcheck disable=SC2034  # Registry arrays are consumed by update_workflow.sh.
# --- repository rows ---
#
# Two repositories are reported, and both are gated before any work: the shared
# library first, because either product loads from it, then this checkout.
#
# The gate leaves the shared outcome in DOTFILES_SHARED_REPO_RESULT, declared
# beside the gate in scripts/lib/repo_update.sh, rather than threading a second
# nameref through every row-building function -- which would have grown a
# parameter per repository on four signatures and their callers.

_repo_status_row() {
	local label="$1" dir="$2" state="$3" ahead="$4" behind="$5"
	if ! command -v git >/dev/null 2>&1; then
		printf '%s|%s|—|%s\n' "$label" "$NOT_INSTALLED" "$UPDATE_CHECK_SKIP"
		return
	fi
	local branch local_rev installed available='unchecked' action="$UPDATE_CHECK_UNKNOWN"
	branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
	local_rev="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
	installed="${branch}@${local_rev}"
	case "$state" in
	current)
		available='none'
		action="$UPDATE_CHECK_CURRENT"
		;;
	ahead)
		available="${ahead} local commit(s) ahead"
		action="$UPDATE_CHECK_CURRENT"
		;;
	behind)
		available="${behind} commit(s) behind"
		action="$UPDATE_CHECK_UPGRADE"
		;;
	diverged)
		available="${ahead} ahead / ${behind} behind"
		action="$UPDATE_CHECK_UNKNOWN"
		;;
	esac
	printf '%s|%s|%s|%s\n' "$label" "$installed" "$available" "$action"
	[[ "$action" == "$UPDATE_CHECK_UPGRADE" ]]
}

dotfiles_repo_status() {
	local result_name="${1:-}" state=unchecked ahead=0 behind=0
	if [[ -n "$result_name" ]]; then
		local -n repo_result_ref="$result_name"
		state="${repo_result_ref[state]:-unchecked}"
		ahead="${repo_result_ref[ahead]:-0}"
		behind="${repo_result_ref[behind]:-0}"
	fi
	_repo_status_row 'dotfiles repo' "$DOTFILES_DIR" "$state" "$ahead" "$behind"
}

shared_repo_status() {
	if [[ -z "${DOTFILES_SHARED_ROOT:-}" ]]; then
		printf 'shared repo|%s|—|%s\n' "$NOT_INSTALLED" "$UPDATE_CHECK_SKIP"
		return
	fi
	_repo_status_row 'shared repo' "$DOTFILES_SHARED_ROOT" \
		"${DOTFILES_SHARED_REPO_RESULT[state]:-unchecked}" \
		"${DOTFILES_SHARED_REPO_RESULT[ahead]:-0}" \
		"${DOTFILES_SHARED_REPO_RESULT[behind]:-0}"
}

# --- Ordered update-step registry ---
# Preview and apply both consume this registry. A step cannot appear in one
# phase without declaring the handler used by the other phase.
UPDATE_STEP_KEYS=(apt graphify boost cursor codex claude lazygit lazydocker node npm go monaspace shared repository)
declare -gA UPDATE_STEP_LABEL=(
	[apt]='apt packages' [graphify]='Graphify CLI' [boost]='Boost CLI'
	[cursor]='Cursor CLI' [codex]='Codex CLI' [claude]='Claude CLI'
	[lazygit]='lazygit' [lazydocker]='lazydocker'
	[node]='Node.js (nvm)' [npm]='npm' [go]='Go (asdf)'
	[monaspace]='Monaspace fonts' [shared]='shared repo' [repository]='dotfiles repo'
)
declare -gA UPDATE_STEP_CHECK=(
	[apt]=check_apt [graphify]=check_graphify_cli [boost]=check_boost_cli
	[cursor]=check_cursor_cli [codex]=check_codex_cli [claude]=check_claude_cli
	[lazygit]=check_lazygit [lazydocker]=check_lazydocker
	[node]=check_node [npm]=check_npm [go]=check_go [monaspace]=check_monaspace
	[shared]=shared_repo_status
	[repository]=dotfiles_repo_status
)
declare -gA UPDATE_STEP_APPLY=(
	[apt]=_apply_apt_update_step [graphify]=upgrade_graphify_cli [boost]=upgrade_boost_cli
	[cursor]=upgrade_cursor_cli [codex]=upgrade_codex_cli [claude]=upgrade_claude_cli
	[lazygit]=upgrade_lazygit [lazydocker]=upgrade_lazydocker
	[node]=upgrade_node [npm]=_apply_npm_update_step [go]=upgrade_go
	[monaspace]=upgrade_monaspace
	[shared]=_apply_repository_update_step [repository]=_apply_repository_update_step
)
declare -gA UPDATE_STEP_RETRY=(
	[apt]='sudo apt-get upgrade' [graphify]='uv tool upgrade graphifyy'
	[boost]='dotfiles update' [cursor]='dotfiles update'
	[codex]='dotfiles update' [claude]='claude update'
	[lazygit]='dotfiles update' [lazydocker]='dotfiles update'
	[node]='nvm install --lts' [npm]='nvm install-latest-npm'
	[go]='asdf install golang latest' [monaspace]='dotfiles update'
	[shared]='dotfiles update' [repository]='dotfiles update'
)

update_step_registry_validate() {
	local -A seen=()
	local key label
	for key in "${UPDATE_STEP_KEYS[@]}"; do
		[[ -n "$key" && -z "${seen[$key]+x}" ]] || return 1
		seen["$key"]=1
		label="${UPDATE_STEP_LABEL[$key]:-}"
		[[ -n "$label" && -n "${UPDATE_STEP_CHECK[$key]:-}" && -n "${UPDATE_STEP_APPLY[$key]:-}" ]] || return 1
		declare -F "${UPDATE_STEP_CHECK[$key]}" >/dev/null || return 1
		declare -F "${UPDATE_STEP_APPLY[$key]}" >/dev/null || return 1
	done
}
