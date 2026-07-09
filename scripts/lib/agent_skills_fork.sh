# shellcheck shell=bash
# Personal skills fork (PamuduW/my-agent-skills) synced from Akindu23/my-agent-skills upstream.
# Clone target: sibling of dotfiles repo, same pattern as agent_bootstrap.

AGENT_SKILLS_FORK_UPSTREAM_URL="${AGENT_SKILLS_FORK_UPSTREAM_URL:-git@github.com:Akindu23/my-agent-skills.git}"
AGENT_SKILLS_FORK_REPO_URL="${AGENT_SKILLS_FORK_REPO_URL:-git@github.com:PamuduW/my-agent-skills.git}"

agent_skills_fork_clone_home() {
	local dotfiles_root sibling

	if [[ -n "${AGENT_SKILLS_FORK_CLONE_HOME:-}" ]]; then
		printf '%s\n' "$AGENT_SKILLS_FORK_CLONE_HOME"
		return 0
	fi

	dotfiles_root="$(dotfiles_repo_root)" || {
		echo "Error: cannot resolve dotfiles repo root." >&2
		return 1
	}

	sibling="$(dirname "$dotfiles_root")/my-agent-skills"
	printf '%s\n' "$sibling"
}

agent_skills_fork_upstream_branch() {
	local repo="$1"
	local branch=''

	branch="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2>/dev/null | sed 's|^upstream/||')"
	if [[ -n "$branch" ]]; then
		printf '%s\n' "$branch"
		return 0
	fi

	for branch in main master; do
		if git -C "$repo" rev-parse --verify "upstream/${branch}" >/dev/null 2>&1; then
			printf '%s\n' "$branch"
			return 0
		fi
	done

	printf 'main\n'
}

agent_skills_fork_ensure_upstream_remote() {
	local repo="$1"
	local current=''

	if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo "Error: ${repo} is not a git repository." >&2
		return 1
	fi

	if git -C "$repo" remote get-url upstream >/dev/null 2>&1; then
		current="$(git -C "$repo" remote get-url upstream)"
		if [[ "$current" != "$AGENT_SKILLS_FORK_UPSTREAM_URL" ]]; then
			git -C "$repo" remote set-url upstream "$AGENT_SKILLS_FORK_UPSTREAM_URL"
		fi
		return 0
	fi

	git -C "$repo" remote add upstream "$AGENT_SKILLS_FORK_UPSTREAM_URL"
}

agent_skills_fork_counts() {
	local repo="$1"
	local upstream_ref="$2"
	local behind='' ahead=''

	behind="$(git -C "$repo" rev-list --count "HEAD..${upstream_ref}" 2>/dev/null || true)"
	ahead="$(git -C "$repo" rev-list --count "${upstream_ref}..HEAD" 2>/dev/null || true)"
	printf '%s %s\n' "${behind:-?}" "${ahead:-?}"
}

clone_or_init_agent_skills_fork() {
	local fork_home="$1"
	local parent_dir

	parent_dir="$(dirname "$fork_home")"
	mkdir -p "$parent_dir"

	if [[ -d "$fork_home/.git" ]]; then
		return 0
	fi

	if [[ -d "$fork_home" ]]; then
		echo "Error: ${fork_home} exists but is not a git repository." >&2
		return 1
	fi

	echo "Cloning skills fork to ${fork_home}..."
	git clone "$AGENT_SKILLS_FORK_REPO_URL" "$fork_home"
	agent_skills_fork_ensure_upstream_remote "$fork_home"
}

print_agent_skills_fork_status() {
	local fork_home="${1:-}"
	local cols branch dirty behind ahead upstream_branch upstream_ref
	local fork_result sync_result sync_detail has_upstream=''

	if [[ -z "$fork_home" ]]; then
		fork_home="$(agent_skills_fork_clone_home)" || fork_home="(unknown)"
	fi

	cols="$(menu_tty_cols)"

	if [[ -d "$fork_home/.git" ]]; then
		fork_result=ok
		branch="$(git -C "$fork_home" branch --show-current 2>/dev/null || echo '?')"
		dirty="$(git -C "$fork_home" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

		if git -C "$fork_home" remote get-url upstream >/dev/null 2>&1; then
			has_upstream=1
			upstream_branch="$(agent_skills_fork_upstream_branch "$fork_home")"
			upstream_ref="upstream/${upstream_branch}"
			if git -C "$fork_home" rev-parse --verify "$upstream_ref" >/dev/null 2>&1; then
				read -r behind ahead < <(agent_skills_fork_counts "$fork_home" "$upstream_ref")
				if [[ "$behind" == "0" ]]; then
					sync_result=ok
					sync_detail="up to date"
				elif [[ "$behind" == "?" ]]; then
					sync_result=check
					sync_detail="unknown"
				else
					sync_result=check
					sync_detail="${behind} behind upstream"
				fi
				if [[ "$ahead" != "?" && "$ahead" != "0" ]]; then
					sync_detail+=", ${ahead} ahead"
				fi
			else
				sync_result=check
				sync_detail="run sync to fetch upstream"
			fi
		else
			sync_result=check
			sync_detail="upstream remote missing"
		fi
	elif [[ -d "$fork_home" ]]; then
		fork_result=check
		sync_result=missing
		sync_detail="not a git repo"
		branch=''
		dirty=''
	else
		fork_result=missing
		sync_result=missing
		sync_detail="not cloned"
		branch=''
		dirty=''
	fi

	{
		printf '\n'
		ui_print_header "Skills fork status" "Dotfiles › Agents › fork" "$cols"
		ui_print_check_result_path_header "$cols"
		ui_print_check_result_path_row "fork repo" "$fork_result" "$fork_home" "$cols"
		ui_print_check_result_path_row "origin" "$fork_result" "$AGENT_SKILLS_FORK_REPO_URL" "$cols"
		if [[ -n "$has_upstream" ]]; then
			ui_print_check_result_path_row "upstream remote" ok "$AGENT_SKILLS_FORK_UPSTREAM_URL" "$cols"
		else
			ui_print_check_result_path_row "upstream remote" check "$AGENT_SKILLS_FORK_UPSTREAM_URL" "$cols"
		fi
		if [[ -n "$branch" ]]; then
			ui_print_check_result_path_row "git branch" ok "$branch" "$cols"
		fi
		if [[ -n "$dirty" ]]; then
			if [[ "$dirty" -eq 0 ]]; then
				ui_print_check_result_path_row "dirty files" ok "0" "$cols"
			else
				ui_print_check_result_path_row "dirty files" check "$dirty" "$cols"
			fi
		fi
		if [[ -n "$sync_detail" ]]; then
			ui_print_check_result_path_row "upstream sync" "$sync_result" "$sync_detail" "$cols"
		fi
	} >/dev/tty
}

sync_agent_skills_fork() {
	local fork_home answer branch upstream_branch upstream_ref
	local behind ahead dirty merge_rc=0 push_rc=0

	fork_home="$(agent_skills_fork_clone_home)" || return 1

	if ! clone_or_init_agent_skills_fork "$fork_home"; then
		return 1
	fi

	agent_skills_fork_ensure_upstream_remote "$fork_home"

	ui_clear
	print_agent_skills_fork_status "$fork_home"

	echo ""
	echo "Fetching origin and upstream..."
	git -C "$fork_home" fetch origin --prune
	git -C "$fork_home" fetch upstream --prune

	upstream_branch="$(agent_skills_fork_upstream_branch "$fork_home")"
	upstream_ref="upstream/${upstream_branch}"
	branch="$(git -C "$fork_home" branch --show-current 2>/dev/null || echo main)"

	if ! git -C "$fork_home" rev-parse --verify "$upstream_ref" >/dev/null 2>&1; then
		echo "Error: ${upstream_ref} not found after fetch." >&2
		return 1
	fi

	read -r behind ahead < <(agent_skills_fork_counts "$fork_home" "$upstream_ref")
	echo ""
	echo "Fork branch: ${branch}"
	echo "Upstream:    ${upstream_ref}"
	echo "Behind:      ${behind}"
	echo "Ahead:       ${ahead}"

	if [[ "$behind" == "0" ]]; then
		echo ""
		echo "Fork is already up to date with upstream."
	else
		dirty="$(git -C "$fork_home" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
		if [[ "$dirty" -ne 0 ]]; then
			echo ""
			echo "Warning: fork has ${dirty} uncommitted change(s). Commit or stash before merging." >&2
			read_tty_line answer "Merge anyway? [y/N]: "
			case "$answer" in
			y | Y | yes | YES) ;;
			*) echo "Merge skipped."; return 1 ;;
			esac
		fi

		echo ""
		read_tty_line answer "Merge ${upstream_ref} into ${branch}? [y/N]: "
		case "$answer" in
		y | Y | yes | YES)
			if ! git -C "$fork_home" merge --no-edit "$upstream_ref"; then
				echo "Error: merge failed. Resolve conflicts, then push manually." >&2
				return 1
			fi
			echo "Merged ${upstream_ref} into ${branch}."
			;;
		*) echo "Merge skipped." ;;
		esac
	fi

	read_tty_line answer "Push fork to origin? [y/N]: "
	case "$answer" in
	y | Y | yes | YES)
		if ! git -C "$fork_home" push origin "$branch"; then
			push_rc=$?
			echo "Warning: push to origin failed (exit ${push_rc})" >&2
		else
			echo "Pushed ${branch} to origin."
		fi
		;;
	*) echo "Push skipped." ;;
	esac

	ab_home="$(resolve_agent_bootstrap_home 2>/dev/null || true)"
	if [[ -n "$ab_home" && -x "$ab_home/install.sh" ]]; then
		echo ""
		read_tty_line answer "Run agent_bootstrap skills update now? [y/N]: "
		case "$answer" in
		y | Y | yes | YES)
			( cd "$ab_home" && ./install.sh skills update ) || merge_rc=$?
			;;
		esac
	fi

	if (( push_rc != 0 || merge_rc != 0 )); then
		return 1
	fi
	return 0
}
