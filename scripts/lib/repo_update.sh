# shellcheck shell=bash

REPO_UPDATE_OUTCOME=stopped
REPO_UPDATE_STATE=invalid
REPO_UPDATE_AHEAD=0
REPO_UPDATE_BEHIND=0
REPO_UPDATE_DIRTY=0
REPO_UPDATE_CHANGES=''
REPO_UPDATE_UPSTREAM=''
REPO_UPDATE_REASON=''

_repo_update_stop() {
	REPO_UPDATE_STATE="$1"
	REPO_UPDATE_REASON="$1"
	printf '%s\n' "$2" >&2
	return 1
}

_repo_update_print_fetch_output() {
	local output="$1" line
	while IFS= read -r line; do
		printf '%s%s%s\n' "${C_CYAN:-}" "$line" "${C_RESET:-}"
	done <<<"$output"
}

repo_update_inspect() {
	local repo_dir="$1" upstream
	REPO_UPDATE_STATE=invalid
	REPO_UPDATE_AHEAD=0
	REPO_UPDATE_BEHIND=0
	REPO_UPDATE_DIRTY=0
	REPO_UPDATE_CHANGES=''
	REPO_UPDATE_UPSTREAM=''
	REPO_UPDATE_REASON=''
	command -v git >/dev/null 2>&1 || { _repo_update_stop invalid 'Git is not installed.'; return 1; }
	[[ "$(git -C "$repo_dir" rev-parse --is-inside-work-tree 2>/dev/null || true)" == true ]] || { _repo_update_stop invalid 'Not a Git worktree.'; return 1; }
	[[ "$(git -C "$repo_dir" rev-parse --is-bare-repository 2>/dev/null || true)" == false ]] || { _repo_update_stop invalid 'Bare repositories cannot be updated.'; return 1; }
	git -C "$repo_dir" remote get-url origin >/dev/null 2>&1 || { _repo_update_stop no-origin 'No origin remote is configured.'; return 1; }
	git -C "$repo_dir" symbolic-ref -q --short HEAD >/dev/null 2>&1 || { _repo_update_stop detached 'HEAD is detached; check out a branch first.'; return 1; }
	upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || { _repo_update_stop no-upstream 'No upstream is configured; set the branch upstream first.'; return 1; }
	[[ "${upstream%%/*}" == origin ]] || { _repo_update_stop non-origin-upstream 'The current branch upstream must use the origin remote.'; return 1; }
	REPO_UPDATE_UPSTREAM="$upstream"
	if ! REPO_UPDATE_CHANGES="$(git -C "$repo_dir" status --short --untracked-files=all 2>/dev/null)"; then
		_repo_update_stop status-failed 'Could not inspect local repository changes.'
		return 1
	fi
	[[ -n "$REPO_UPDATE_CHANGES" ]] && REPO_UPDATE_DIRTY=1
	return 0
}

repo_update_classify_history() {
	local repo_dir="$1" counts
	counts="$(git -C "$repo_dir" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null)" || { _repo_update_stop invalid 'Could not classify local and upstream history.'; return 1; }
	read -r REPO_UPDATE_AHEAD REPO_UPDATE_BEHIND <<<"$counts"
	[[ "$REPO_UPDATE_AHEAD" =~ ^[0-9]+$ && "$REPO_UPDATE_BEHIND" =~ ^[0-9]+$ ]] || { _repo_update_stop invalid-counts 'Git returned invalid ahead/behind counts.'; return 1; }
	if ((REPO_UPDATE_AHEAD > 0 && REPO_UPDATE_BEHIND > 0)); then REPO_UPDATE_STATE=diverged
	elif ((REPO_UPDATE_AHEAD > 0)); then REPO_UPDATE_STATE=ahead
	elif ((REPO_UPDATE_BEHIND > 0)); then REPO_UPDATE_STATE=behind
	else REPO_UPDATE_STATE=current
	fi
	REPO_UPDATE_REASON="$REPO_UPDATE_STATE"
}

repo_update_gate() {
	local repo_dir="$1" confirm_fn="$2" fetch_output='' pull_output=''
	REPO_UPDATE_OUTCOME=stopped
	repo_update_inspect "$repo_dir" || return 0
	if ! fetch_output="$(git -C "$repo_dir" fetch --prune 2>&1)"; then
		[[ -n "$fetch_output" ]] && printf '%s\n' "$fetch_output" >&2
		printf 'Git fetch failed; remote freshness is unknown.\n' >&2
		REPO_UPDATE_STATE=stopped
		REPO_UPDATE_REASON=fetch-failed
		return 0
	fi
	if [[ -n "$fetch_output" ]]; then
		_repo_update_print_fetch_output "$fetch_output"
	fi
	repo_update_classify_history "$repo_dir" || return 0
	if [[ "$REPO_UPDATE_DIRTY" == 1 ]]; then
		REPO_UPDATE_OUTCOME=stopped
		REPO_UPDATE_REASON=dirty
		return 0
	fi
	case "$REPO_UPDATE_STATE" in
	current) REPO_UPDATE_OUTCOME=current ;;
	ahead)
		if "$confirm_fn" 'Local branch is ahead. Continue with downstream updates?'; then REPO_UPDATE_OUTCOME=ahead_continue
		else printf 'Update stopped; no downstream work was run.\n'; fi
		;;
	behind)
		if ! "$confirm_fn" "Pull ${REPO_UPDATE_BEHIND} commit(s) with --ff-only?"; then
			printf 'Pull declined; update stopped.\n'
		elif pull_output="$(git -C "$repo_dir" pull --ff-only 2>&1)"; then
			[[ -n "$pull_output" ]] && _repo_update_print_fetch_output "$pull_output"
			REPO_UPDATE_OUTCOME=relaunch_required
		else
			[[ -n "$pull_output" ]] && printf '%s\n' "$pull_output" >&2
			printf 'Fast-forward pull failed; resolve the repository manually.\n' >&2
		fi
		;;
	diverged) printf 'Local and upstream histories diverged; resolve them manually.\n' >&2 ;;
	*) printf 'Repository state is unsafe for update.\n' >&2 ;;
	esac
}

repo_update_relaunch() {
	exec "$@"
}
