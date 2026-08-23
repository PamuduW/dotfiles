# shellcheck shell=bash

if [[ "${_DOTFILES_REPO_UPDATE_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_REPO_UPDATE_LOADED=1

if ! declare -F colors_set_palette >/dev/null 2>&1; then
	_REPO_UPDATE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/shared/tui" && pwd)"
	# shellcheck source=scripts/lib/shared/tui/colors.sh
	source "$_REPO_UPDATE_LIB_DIR/colors.sh"
fi
if ! declare -F tty_available >/dev/null 2>&1; then
	_REPO_UPDATE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/shared/tui" && pwd)"
	# shellcheck source=scripts/lib/shared/tui/tty.sh
	source "$_REPO_UPDATE_LIB_DIR/tty.sh"
fi
if ! declare -F rt_print_four_column_header >/dev/null 2>&1; then
	_REPO_UPDATE_LIB_DIR="${_REPO_UPDATE_LIB_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/shared/tui" && pwd)}"
	# shellcheck source=scripts/lib/shared/tui/report_table.sh
	source "$_REPO_UPDATE_LIB_DIR/report_table.sh"
fi

_repo_update_result_init() {
	local result_name="$1" repo_dir="$2" repo_label="$3"
	local -n result_ref="$result_name"
	result_ref=(
		[dir]="$repo_dir"
		[label]="$repo_label"
		[state]=invalid
		[ahead]=0
		[behind]=0
		[dirty]=0
		[changes]=''
		[upstream]=''
		[reason]=''
		[safe]=0
		[approved]=0
		[apply_action]=''
		[recovery_branch]=''
		[recovery_stash]=''
		[outcome]=stopped
	)
}

_repo_update_result_stop() {
	local result_name="$1" state="$2" message="$3"
	local -n result_ref="$result_name"
	result_ref[state]="$state"
	result_ref[reason]="$state"
	result_ref[safe]=0
	result_ref[outcome]=stopped
	printf '%s\n' "$message" >&2
	return 1
}

_repo_update_print_fetch_output() {
	local output="$1" line
	while IFS= read -r line; do
		printf '%s%s%s\n' "${C_CYAN:-}" "$line" "${C_RESET:-}"
	done <<<"$output"
}

repo_update_origin_allowed() {
	local origin="$1" expected_slug="$2" rewrite_rules="${3:-}"
	local key target prefix matched_prefix='' matched_target='' resolved
	case "$expected_slug" in
	PamuduW/dotfiles) [[ "${DOTFILES_REPO_URL_ALLOW_ANY:-0}" == 1 ]] && return 0 ;;
	esac
	case "$origin" in *://*@*) return 1 ;; esac
	case "$origin" in
	"git@github.com:${expected_slug}" | "git@github.com:${expected_slug}.git" | "https://github.com/${expected_slug}" | "https://github.com/${expected_slug}.git") return 0 ;;
	esac
	while IFS=$' \t' read -r key target; do
		[[ "$key" == url.*.insteadof ]] || continue
		prefix="${key#url.}"
		prefix="${prefix%.insteadof}"
		case "$origin" in
		"$prefix"*)
			if ((${#prefix} > ${#matched_prefix})); then
				matched_prefix="$prefix"
				matched_target="$target"
			fi
			;;
		esac
	done <<<"$rewrite_rules"
	[[ -n "$matched_prefix" ]] || return 1
	resolved="${matched_target}${origin#"$matched_prefix"}"
	case "$resolved" in
	"git@github.com:${expected_slug}" | "git@github.com:${expected_slug}.git" | "https://github.com/${expected_slug}" | "https://github.com/${expected_slug}.git") return 0 ;;
	*) return 1 ;;
	esac
}

repo_update_preflight() {
	local repo_dir="$1" repo_label="$2" result_name="$3" expected_slug="${4:-}"
	local upstream counts fetch_output='' origin rewrite_rules=''
	local -n result_ref="$result_name"
	_repo_update_result_init "$result_name" "$repo_dir" "$repo_label"

	command -v git >/dev/null 2>&1 || {
		_repo_update_result_stop "$result_name" invalid 'Git is not installed.'
		return 0
	}
	[[ "$(git -C "$repo_dir" rev-parse --is-inside-work-tree 2>/dev/null || true)" == true ]] || {
		_repo_update_result_stop "$result_name" invalid "Not a Git worktree: $repo_dir"
		return 0
	}
	[[ "$(git -C "$repo_dir" rev-parse --is-bare-repository 2>/dev/null || true)" == false ]] || {
		_repo_update_result_stop "$result_name" invalid 'Bare repositories cannot be updated.'
		return 0
	}
	origin="$(git -C "$repo_dir" remote get-url origin 2>/dev/null)" || {
		_repo_update_result_stop "$result_name" no-origin 'No origin remote is configured.'
		return 0
	}
	result_ref[origin]="$origin"
	if [[ -n "$expected_slug" ]]; then
		rewrite_rules="$(git config --global --get-regexp '^url\..*\.insteadof$' 2>/dev/null || true)"
		repo_update_origin_allowed "$origin" "$expected_slug" "$rewrite_rules" || {
			_repo_update_result_stop "$result_name" wrong-origin "Origin is not the expected repository: $origin"
			return 0
		}
	fi
	git -C "$repo_dir" symbolic-ref -q --short HEAD >/dev/null 2>&1 || {
		_repo_update_result_stop "$result_name" detached 'HEAD is detached; check out a branch first.'
		return 0
	}
	upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || {
		_repo_update_result_stop "$result_name" no-upstream 'No upstream is configured; set the branch upstream first.'
		return 0
	}
	[[ "${upstream%%/*}" == origin ]] || {
		_repo_update_result_stop "$result_name" non-origin-upstream 'The current branch upstream must use the origin remote.'
		return 0
	}
	result_ref[upstream]="$upstream"

	if ! result_ref[changes]="$(git -C "$repo_dir" status --short --untracked-files=all 2>/dev/null)"; then
		_repo_update_result_stop "$result_name" status-failed 'Could not inspect local repository changes.'
		return 0
	fi
	[[ -n "${result_ref[changes]}" ]] && result_ref[dirty]=1

	if ! fetch_output="$(git -C "$repo_dir" fetch --prune 2>&1)"; then
		[[ -n "$fetch_output" ]] && printf '%s\n' "$fetch_output" >&2
		_repo_update_result_stop "$result_name" fetch-failed 'Git fetch failed; remote freshness is unknown.'
		return 0
	fi
	[[ -n "$fetch_output" ]] && _repo_update_print_fetch_output "$fetch_output"

	counts="$(git -C "$repo_dir" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null)" || {
		_repo_update_result_stop "$result_name" invalid 'Could not classify local and upstream history.'
		return 0
	}
	read -r result_ref[ahead] result_ref[behind] <<<"$counts"
	if [[ ! "${result_ref[ahead]}" =~ ^[0-9]+$ || ! "${result_ref[behind]}" =~ ^[0-9]+$ ]]; then
		_repo_update_result_stop "$result_name" invalid-counts 'Git returned invalid ahead/behind counts.'
		return 0
	fi

	if ((result_ref[ahead] > 0 && result_ref[behind] > 0)); then
		result_ref[state]=diverged
	elif ((result_ref[ahead] > 0)); then
		result_ref[state]=ahead
	elif ((result_ref[behind] > 0)); then
		result_ref[state]=behind
	else
		result_ref[state]=current
	fi

	if [[ "${result_ref[dirty]}" == 1 ]]; then
		result_ref[reason]=dirty
		return 0
	fi
	if [[ "${result_ref[state]}" == diverged ]]; then
		result_ref[reason]=diverged
		return 0
	fi
	result_ref[reason]="${result_ref[state]}"
	result_ref[safe]=1
}

_repo_update_change_count_for() {
	local result_name="$1"
	local -n result_ref="$result_name"
	if [[ -z "${result_ref[changes]:-}" ]]; then
		printf '0\n'
	else
		awk 'END { print NR }' <<<"${result_ref[changes]}"
	fi
}

_repo_update_history_detail_for() {
	local result_name="$1"
	local -n result_ref="$result_name"
	case "${result_ref[state]:-stopped}" in
	current) printf 'current' ;;
	ahead) printf '%s local commit(s) ahead' "${result_ref[ahead]:-0}" ;;
	behind) printf '%s commit(s) behind' "${result_ref[behind]:-0}" ;;
	diverged) printf '%s ahead / %s behind' "${result_ref[ahead]:-0}" "${result_ref[behind]:-0}" ;;
	*) printf 'freshness unknown' ;;
	esac
}

_repo_update_color_available() { status_color_available "$1"; }
_repo_update_color_action() { status_color_action "$1"; }

_repo_update_print_table_header() {
	local last_col="$1"
	rt_print_four_column_header 18 component 28 installed 22 available 16 "$last_col"
}

_repo_update_print_table_row() {
	local component="$1" installed="$2" available="$3" action="$4"
	rt_print_four_column_row 18 "$component" 28 "$installed" 22 "$available" 16 "$action" \
		_repo_update_color_available _repo_update_color_action
}

repo_update_print_result() {
	local result_name="$1"
	local -n result_ref="$result_name"
	local branch local_rev available action change_count remote_action
	branch="$(git -C "${result_ref[dir]}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
	local_rev="$(git -C "${result_ref[dir]}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
	available="$(_repo_update_history_detail_for "$result_name")"
	change_count="$(_repo_update_change_count_for "$result_name")"
	case "${result_ref[state]}" in current | ahead | behind | diverged) remote_action=verified ;; *) remote_action=unchecked ;; esac
	if [[ "${result_ref[dirty]}" == 1 ]]; then
		action=blocked
	else
		case "${result_ref[state]}" in behind) action='pull --ff-only' ;; ahead | diverged) action='replace after backup' ;; current) action='current' ;; *) action='check' ;; esac
	fi

	printf '\n%s%sRepository update%s\n\n' "${C_BOLD:-}" "${C_YELLOW:-}" "${C_RESET:-}"
	_repo_update_print_table_header action
	if [[ "${result_ref[dirty]}" == 1 ]]; then
		_repo_update_print_table_row "${result_ref[label]}" "${branch}@${local_rev}" "${change_count} local change(s)" "$action"
	else
		_repo_update_print_table_row "${result_ref[label]}" "${branch}@${local_rev}" "$available" "$action"
	fi
	_repo_update_print_table_row "${result_ref[upstream]:-upstream}" 'remote history' "$available" "$remote_action"
	printf '\n'
}

repo_update_print_changes() {
	local result_name="$1" max_lines=20 total shown=0 omitted quoted_repo line
	local -n result_ref="$result_name"
	[[ -n "${result_ref[changes]:-}" ]] || return 0
	total="$(awk 'END { print NR }' <<<"${result_ref[changes]}")"
	printf '  Local changes:\n'
	while IFS= read -r line; do
		((shown >= max_lines)) && break
		printf '  %s\n' "$line"
		shown=$((shown + 1))
	done <<<"${result_ref[changes]}"
	omitted=$((total - shown))
	if ((omitted > 0)); then
		printf '  ... %d more local change(s)\n' "$omitted"
	fi
	printf -v quoted_repo '%q' "${result_ref[dir]}"
	printf '  Full list: git -C %s status --short --untracked-files=all\n' "$quoted_repo"
}

repo_update_print_stopped() {
	local result_name="$1"
	local -n result_ref="$result_name"
	case "${result_ref[reason]:-unknown}" in
	behind-declined | ahead-declined) return 0 ;;
	esac
	repo_update_print_result "$result_name"
	repo_update_print_changes "$result_name"
	case "${result_ref[reason]:-unknown}" in
	dirty)
		printf '%sRepository pull and downstream updates stopped.%s\n' "${C_RED:-}" "${C_RESET:-}" >&2
		printf '%sResolve the local changes, then retry.%s\n' "${C_RED:-}" "${C_RESET:-}" >&2
		;;
	fetch-failed)
		printf '%sRepository pull and downstream updates stopped because remote freshness is unknown.%s\n' \
			"${C_RED:-}" "${C_RESET:-}" >&2
		;;
	*)
		printf '%sRepository pull and downstream updates stopped: %s.%s\n' \
			"${C_RED:-}" "${result_ref[reason]:-unknown}" "${C_RESET:-}" >&2
		;;
	esac
}

repo_update_request_approval() {
	local result_name="$1" confirm_fn="$2" event prompt
	local -n result_ref="$result_name"
	result_ref[approved]=0
	if [[ "${result_ref[reason]:-}" == dirty || ("${result_ref[dirty]:-0}" == 0 && ("${result_ref[state]:-}" == ahead || "${result_ref[state]:-}" == diverged)) ]]; then
		event=replace-local
		prompt="Back up local work and replace it with ${result_ref[upstream]}?"
		repo_update_print_result "$result_name"
		repo_update_print_changes "$result_name"
		if "$confirm_fn" "$event" "$prompt"; then
			result_ref[approved]=1
			result_ref[apply_action]=replace
			return 0
		fi
		result_ref[reason]=replace-declined
		result_ref[outcome]=stopped
		printf '\n\n%sReplacement declined; update stopped.%s\n' "${C_RED:-}" "${C_RESET:-}"
		return 1
	fi
	if [[ "${result_ref[safe]}" != 1 ]]; then
		result_ref[outcome]=stopped
		return 1
	fi
	case "${result_ref[state]}" in
	current)
		result_ref[approved]=1
		result_ref[outcome]=current
		return 0
		;;
	ahead)
		event=continue-ahead
		prompt='Local branch is ahead. Continue with downstream updates?'
		;;
	behind)
		event=pull-behind
		prompt="Pull ${result_ref[behind]} commit(s) with --ff-only?"
		;;
	*) return 1 ;;
	esac
	repo_update_print_result "$result_name"
	if "$confirm_fn" "$event" "$prompt"; then
		result_ref[approved]=1
		[[ "${result_ref[state]}" == ahead ]] && result_ref[outcome]=ahead_continue
		return 0
	fi
	result_ref[reason]="${result_ref[state]}-declined"
	result_ref[outcome]=stopped
	if [[ "${result_ref[state]}" == behind ]]; then
		printf '\n\n%sPull declined; update stopped.%s\n' "${C_RED:-}" "${C_RESET:-}"
	else
		printf '\n\n%sUpdate stopped; no downstream work was run.%s\n' "${C_RED:-}" "${C_RESET:-}"
	fi
	return 1
}

_repo_update_recovery_branch() {
	local result_name="$1" timestamp candidate suffix=0
	local -n result_ref="$result_name"
	timestamp="$(date -u +%Y%m%d-%H%M%S)" || {
		result_ref[reason]=recovery-timestamp-failed
		return 1
	}
	candidate="recovery/dotfiles-${timestamp}"
	while git -C "${result_ref[dir]}" show-ref --verify --quiet "refs/heads/${candidate}"; do
		suffix=$((suffix + 1))
		candidate="recovery/dotfiles-${timestamp}-${suffix}"
	done
	if ! git -C "${result_ref[dir]}" branch "$candidate" HEAD; then
		result_ref[reason]=recovery-branch-failed
		return 1
	fi
	result_ref[recovery_branch]="$candidate"
}

_repo_update_stash_changes() {
	local result_name="$1" stash_output='' stash_id message
	local -n result_ref="$result_name"
	message="dotfiles full-update recovery $(date -u +%Y%m%d-%H%M%S)" || {
		result_ref[reason]=recovery-timestamp-failed
		return 1
	}
	if ! stash_output="$(git -C "${result_ref[dir]}" stash push --include-untracked -m "$message" 2>&1)"; then
		[[ -n "$stash_output" ]] && printf '%s\n' "$stash_output" >&2
		result_ref[reason]=stash-failed
		return 1
	fi
	stash_id="$(git -C "${result_ref[dir]}" rev-parse --verify refs/stash 2>/dev/null)" || {
		result_ref[reason]=stash-reference-failed
		return 1
	}
	result_ref[recovery_stash]="$stash_id"
}

_repo_update_replace_with_upstream() {
	local result_name="$1" remaining reset_output=''
	local -n result_ref="$result_name"
	if ((result_ref[ahead] > 0)); then
		_repo_update_recovery_branch "$result_name" || return 1
	fi
	if [[ "${result_ref[dirty]}" == 1 ]]; then
		_repo_update_stash_changes "$result_name" || return 1
	fi
	remaining="$(git -C "${result_ref[dir]}" status --short --untracked-files=all 2>/dev/null)" || {
		result_ref[reason]=status-failed-after-recovery
		return 1
	}
	if [[ -n "$remaining" ]]; then
		result_ref[reason]=recovery-incomplete
		return 1
	fi
	if ! reset_output="$(git -C "${result_ref[dir]}" reset --hard '@{upstream}' 2>&1)"; then
		[[ -n "$reset_output" ]] && printf '%s\n' "$reset_output" >&2
		result_ref[reason]=reset-failed
		return 1
	fi
	[[ -n "$reset_output" ]] && _repo_update_print_fetch_output "$reset_output"
	result_ref[outcome]=repository_changed
}

repo_update_print_recovery() {
	local result_name="$1"
	local -n result_ref="$result_name"
	[[ -n "${result_ref[recovery_branch]:-}${result_ref[recovery_stash]:-}" ]] || return 0
	printf 'Recovery data preserved:\n'
	[[ -n "${result_ref[recovery_branch]:-}" ]] && printf '  Recovery branch: %s\n' "${result_ref[recovery_branch]}"
	[[ -n "${result_ref[recovery_stash]:-}" ]] && printf '  Recovery stash: %s\n' "${result_ref[recovery_stash]}"
}

repo_update_apply() {
	local result_name="$1" pull_output=''
	local -n result_ref="$result_name"
	[[ "${result_ref[approved]}" == 1 ]] || {
		result_ref[outcome]=stopped
		return 1
	}
	if [[ "${result_ref[apply_action]:-}" == replace ]]; then
		_repo_update_replace_with_upstream "$result_name"
		return $?
	fi
	case "${result_ref[state]}" in
	current) result_ref[outcome]=current ;;
	ahead) result_ref[outcome]=ahead_continue ;;
	behind)
		if pull_output="$(git -C "${result_ref[dir]}" pull --ff-only 2>&1)"; then
			[[ -n "$pull_output" ]] && _repo_update_print_fetch_output "$pull_output"
			result_ref[outcome]=repository_changed
		else
			[[ -n "$pull_output" ]] && printf '%s\n' "$pull_output" >&2
			printf 'Fast-forward pull failed; resolve the repository manually.\n' >&2
			result_ref[reason]=pull-failed
			result_ref[outcome]=stopped
			return 1
		fi
		;;
	*)
		result_ref[outcome]=stopped
		return 1
		;;
	esac
}

# Complete the single-repository workflow. Every caller gets the same
# preflight, report, approval, pull, and stopped-state presentation.
repo_update_run() {
	# Contract: 0 means callers may continue, 1 means the update stopped, and
	# 2 means a fast-forward changed this checkout and all higher-level work
	# must stop so the user can rerun from the new repository state.
	local repo_dir="$1" repo_label="$2" confirm_fn="$3" result_name="$4" expected_slug="${5:-}"
	repo_update_preflight "$repo_dir" "$repo_label" "$result_name" "$expected_slug"
	local -n result_ref="$result_name"
	if [[ "${result_ref[safe]}" != 1 && "${result_ref[reason]}" != dirty && "${result_ref[state]}" != diverged ]]; then
		repo_update_print_stopped "$result_name"
		return 1
	fi
	if ! repo_update_request_approval "$result_name" "$confirm_fn"; then
		return 1
	fi
	if ! repo_update_apply "$result_name"; then
		repo_update_print_recovery "$result_name"
		return 1
	fi
	if [[ "${result_ref[outcome]}" == repository_changed ]]; then
		repo_update_print_recovery "$result_name"
		return 2
	fi
	return 0
}

repo_update_is_declined() {
	local result_name="$1"
	local -n result_ref="$result_name"
	case "${result_ref[reason]:-unknown}" in
	behind-declined | ahead-declined | replace-declined) return 0 ;;
	*) return 1 ;;
	esac
}

repo_update_print_changed() {
	printf '%sRepository fast-forward succeeded%s\n\n' "${C_GREEN:-}" "${C_RESET:-}"
	printf 'Run setup again when ready.\n'
}
