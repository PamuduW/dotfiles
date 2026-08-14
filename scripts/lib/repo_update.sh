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

_repo_update_change_count() {
	if [[ -z "${REPO_UPDATE_CHANGES:-}" ]]; then
		printf '0\n'
		return
	fi
	awk 'END { print NR }' <<<"$REPO_UPDATE_CHANGES"
}

_repo_update_history_detail() {
	case "${REPO_UPDATE_STATE:-stopped}" in
	current) printf 'current' ;;
	ahead) printf '%s local commit(s) ahead' "${REPO_UPDATE_AHEAD:-0}" ;;
	behind) printf '%s commit(s) behind' "${REPO_UPDATE_BEHIND:-0}" ;;
	diverged) printf '%s ahead / %s behind' "${REPO_UPDATE_AHEAD:-0}" "${REPO_UPDATE_BEHIND:-0}" ;;
	*) printf 'freshness unknown' ;;
	esac
}

_repo_update_fit_text() {
	local text="$1" width="$2"
	if ((${#text} > width)); then
		if ((width <= 3)); then
			printf '%s' "${text:0:width}"
		else
			printf '%s...' "${text:0:$((width - 3))}"
		fi
	else
		printf '%s' "$text"
	fi
}

_repo_update_table_rule() {
	local width="$1" rule
	printf -v rule '%*s' "$width" ''
	printf '%s' "${rule// /-}"
}

_repo_update_print_plain_cell() {
	local text="$1" width="$2" fit padding
	fit="$(_repo_update_fit_text "$text" "$width")"
	printf '%s' "$fit"
	padding=$((width - ${#fit}))
	if ((padding > 0)); then
		printf '%*s' "$padding" ''
	fi
}

_repo_update_color_available() {
	local available="$1"
	case "$available" in
	none | — | up\ to\ date) printf '%s%s%s' "${C_DIM:-}" "$available" "${C_RESET:-}" ;;
	*behind | *ahead | update* | *review*) printf '%s%s%s' "${C_YELLOW:-}" "$available" "${C_RESET:-}" ;;
	*) printf '%s%s%s' "${C_CYAN:-}" "$available" "${C_RESET:-}" ;;
	esac
}

_repo_update_color_action() {
	local action="$1"
	case "$action" in
	up\ to\ date | skip | current) printf '%s%s%s' "${C_GREEN:-}" "$action" "${C_RESET:-}" ;;
	latest\ unchecked) printf '%s%s%s' "${C_DIM:-}" "$action" "${C_RESET:-}" ;;
	upgrade* | refresh | continue | check) printf '%s%s%s' "${C_YELLOW:-}" "$action" "${C_RESET:-}" ;;
	pull* | verified) printf '%s%s%s' "${C_CYAN:-}" "$action" "${C_RESET:-}" ;;
	unchecked) printf '%s%s%s' "${C_YELLOW:-}" "$action" "${C_RESET:-}" ;;
	blocked) printf '%s%s%s' "${C_RED:-}" "$action" "${C_RESET:-}" ;;
	*) printf '%s' "$action" ;;
	esac
}

_repo_update_print_colored_cell() {
	local text="$1" width="$2" color_fn="$3" fit padding
	fit="$(_repo_update_fit_text "$text" "$width")"
	"$color_fn" "$fit"
	padding=$((width - ${#fit}))
	if ((padding > 0)); then
		printf '%*s' "$padding" ''
	fi
}

_repo_update_print_table_header() {
	local last_col="$1"
	printf '%s%-*s | %-*s | %-*s | %-*s%s\n' \
		"${C_BOLD:-}" \
		18 component \
		28 installed \
		22 available \
		16 "$last_col" \
		"${C_RESET:-}"
	printf '%s%s-+-%s-+-%s-+-%s%s\n' \
		"${C_DIM:-}" \
		"$(_repo_update_table_rule 18)" \
		"$(_repo_update_table_rule 28)" \
		"$(_repo_update_table_rule 22)" \
		"$(_repo_update_table_rule 16)" \
		"${C_RESET:-}"
}

_repo_update_print_table_row() {
	local component="$1" installed="$2" available="$3" action="$4"
	_repo_update_print_plain_cell "$component" 18
	printf ' | '
	_repo_update_print_plain_cell "$installed" 28
	printf ' | '
	_repo_update_print_colored_cell "$available" 22 _repo_update_color_available
	printf ' | '
	_repo_update_print_colored_cell "$action" 16 _repo_update_color_action
	printf '\n'
}

repo_update_print_report() {
	local repo_dir="$1" heading_style="${2:-update}"
	local branch local_rev available action upstream change_count remote_action
	branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
	local_rev="$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
	available="$(_repo_update_history_detail)"
	upstream="${REPO_UPDATE_UPSTREAM:-upstream}"
	change_count="$(_repo_update_change_count)"
	case "${REPO_UPDATE_STATE:-stopped}" in
	current | ahead | behind | diverged) remote_action='verified' ;;
	*) remote_action='unchecked' ;;
	esac
	if [[ "${REPO_UPDATE_DIRTY:-0}" == 1 ]]; then
		action='blocked'
	else
		case "${REPO_UPDATE_STATE:-stopped}" in
		behind) action='pull --ff-only' ;;
		ahead) action='continue' ;;
		current) action='current' ;;
		*) action='check' ;;
		esac
	fi

	if [[ "$heading_style" == install ]]; then
		printf '\n%s%sRepository update%s\n\n' "${C_BOLD:-}" "${C_YELLOW:-}" "${C_RESET:-}"
	else
		printf '\n%s%s==Repository update==%s\n\n' "${C_BOLD:-}" "${C_ORANGE:-}" "${C_RESET:-}"
	fi
	_repo_update_print_table_header action
	if [[ "${REPO_UPDATE_DIRTY:-0}" == 1 ]]; then
		_repo_update_print_table_row 'dotfiles repo' "${branch}@${local_rev}" "${change_count} local change(s)" "$action"
	else
		_repo_update_print_table_row 'dotfiles repo' "${branch}@${local_rev}" "$available" "$action"
	fi
	_repo_update_print_table_row "$upstream" 'remote history' "$available" "$remote_action"
	printf '\n'
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
