# shellcheck shell=bash

REPO_UPDATE_OUTCOME=stopped
REPO_UPDATE_STATE=invalid
REPO_UPDATE_AHEAD=0
REPO_UPDATE_BEHIND=0

_repo_update_stop() {
	REPO_UPDATE_STATE="$1"
	printf '%s\n' "$2" >&2
	return 1
}

repo_update_inspect() {
	local repo_dir="$1" counts upstream
	REPO_UPDATE_STATE=invalid
	REPO_UPDATE_AHEAD=0
	REPO_UPDATE_BEHIND=0
	command -v git >/dev/null 2>&1 || { _repo_update_stop invalid 'Git is not installed.'; return 1; }
	[[ "$(git -C "$repo_dir" rev-parse --is-inside-work-tree 2>/dev/null || true)" == true ]] || { _repo_update_stop invalid 'Not a Git worktree.'; return 1; }
	[[ "$(git -C "$repo_dir" rev-parse --is-bare-repository 2>/dev/null || true)" == false ]] || { _repo_update_stop invalid 'Bare repositories cannot be updated.'; return 1; }
	git -C "$repo_dir" remote get-url origin >/dev/null 2>&1 || { _repo_update_stop no-origin 'No origin remote is configured.'; return 1; }
	git -C "$repo_dir" symbolic-ref -q --short HEAD >/dev/null 2>&1 || { _repo_update_stop detached 'HEAD is detached; check out a branch first.'; return 1; }
	upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || { _repo_update_stop no-upstream 'No upstream is configured; set the branch upstream first.'; return 1; }
	[[ "${upstream%%/*}" == origin ]] || { _repo_update_stop non-origin-upstream 'The current branch upstream must use the origin remote.'; return 1; }
	[[ -z "$(git -C "$repo_dir" status --porcelain --untracked-files=all 2>/dev/null)" ]] || { _repo_update_stop dirty 'Repository has local changes; commit, stash, or discard them first.'; return 1; }
	counts="$(git -C "$repo_dir" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null)" || { _repo_update_stop invalid 'Could not classify local and upstream history.'; return 1; }
	read -r REPO_UPDATE_AHEAD REPO_UPDATE_BEHIND <<<"$counts"
	if ((REPO_UPDATE_AHEAD > 0 && REPO_UPDATE_BEHIND > 0)); then REPO_UPDATE_STATE=diverged
	elif ((REPO_UPDATE_AHEAD > 0)); then REPO_UPDATE_STATE=ahead
	elif ((REPO_UPDATE_BEHIND > 0)); then REPO_UPDATE_STATE=behind
	else REPO_UPDATE_STATE=current
	fi
}

repo_update_gate() {
	local repo_dir="$1" confirm_fn="$2"
	REPO_UPDATE_OUTCOME=stopped
	repo_update_inspect "$repo_dir" || return 0
	if ! git -C "$repo_dir" fetch --prune; then
		printf 'Git fetch failed; remote freshness is unknown.\n' >&2
		return 0
	fi
	repo_update_inspect "$repo_dir" || return 0
	case "$REPO_UPDATE_STATE" in
	current) REPO_UPDATE_OUTCOME=current ;;
	ahead)
		if "$confirm_fn" 'Local branch is ahead. Continue with downstream updates?'; then REPO_UPDATE_OUTCOME=ahead_continue
		else printf 'Update stopped; no downstream work was run.\n'; fi
		;;
	behind)
		if ! "$confirm_fn" "Pull ${REPO_UPDATE_BEHIND} commit(s) with --ff-only?"; then
			printf 'Pull declined; update stopped.\n'
		elif git -C "$repo_dir" pull --ff-only; then
			REPO_UPDATE_OUTCOME=relaunch_required
		else
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
