# shellcheck shell=bash
# shellcheck disable=SC2034  # repo_result is populated through a nameref by repo_update_run.
# Repository-first update orchestration and fixed-width update reports.
# Depends on update_components.sh and repo_update.sh.

_color_action() {
	case "$1" in
	refresh\ on\ apply) _colors_wrap "${C_YELLOW:-}" "$1" ;;
	externally\ managed) _colors_wrap "${C_DIM:-}" "$1" ;;
	*) status_color_action "$1" ;;
	esac
}
_color_result() {
	case "$1" in
	updated | already\ current | checked/no\ change) _colors_wrap "${C_GREEN:-}" "$1" ;;
	recovered) _colors_wrap "${C_YELLOW:-}" "$1" ;;
	not\ run) _colors_wrap "${C_DIM:-}" "$1" ;;
	*) status_color_result "$1" ;;
	esac
}

_check_state_display() {
	case "$1" in
	upgrade) printf 'upgrade\n' ;;
	current) printf 'up to date\n' ;;
	unknown) printf 'latest unchecked\n' ;;
	refresh-required) printf 'refresh on apply\n' ;;
	external) printf 'externally managed\n' ;;
	skip) printf 'skip\n' ;;
	*) printf '%s\n' "$1" ;;
	esac
}

_upgrade_result_display() {
	case "$1" in
	already-current) printf 'already current\n' ;;
	checked-no-change) printf 'checked/no change\n' ;;
	not-run) printf 'not run\n' ;;
	*) printf '%s\n' "$1" ;;
	esac
}

# Several checks hit the network (npm view, GitHub releases), so run them
# concurrently. Output order still follows CHECK_FUNCS, so the report is
# deterministic. dotfiles_repo_status reads an already-collected nameref and
# takes the repo result name.
_collect_check_rows() {
	local repo_result_name="${1:-}"
	_load_nvm
	local fn
	local -a probes=()
	for fn in "${CHECK_FUNCS[@]}"; do
		if [[ "$fn" == dotfiles_repo_status ]]; then
			probes+=("$(printf '%s %q' "$fn" "$repo_result_name")")
		else
			probes+=("$fn")
		fi
	done
	run_probes_parallel '' "${probes[@]}"
}

# Fixed-width table row: truncate text columns so pipes stay aligned; color last column only.
_UPDATE_LABEL_W=18
_UPDATE_INSTALLED_W=28
_UPDATE_AVAILABLE_W=22
_UPDATE_ACTION_W=16

_print_update_table_header() {
	local last_col="$1"
	rt_print_four_column_header \
		"$_UPDATE_LABEL_W" component \
		"$_UPDATE_INSTALLED_W" installed \
		"$_UPDATE_AVAILABLE_W" available \
		"$_UPDATE_ACTION_W" "$last_col"
}

_print_check_table_row() {
	local component="$1"
	local installed="$2"
	local available="$3"
	local last_col="$4"
	local color_fn="$5"

	case "$color_fn" in
	result) color_fn=_color_result ;;
	*) color_fn=_color_action ;;
	esac
	rt_print_four_column_row \
		"$_UPDATE_LABEL_W" "$component" \
		"$_UPDATE_INSTALLED_W" "$installed" \
		"$_UPDATE_AVAILABLE_W" "$available" \
		"$_UPDATE_ACTION_W" "$last_col" '' "$color_fn"
}

print_report_table() {
	local repo_result_name="${1:-}"
	local -a rows=()
	local row component installed available state display
	local upgrade_count=0 remaining_count=0

	mapfile -t rows < <(_collect_check_rows "$repo_result_name")

	for row in "${rows[@]}"; do
		IFS='|' read -r component installed available state <<<"$row"
		[[ -n "$component" ]] || continue
		case "$state" in
		upgrade) ((++upgrade_count)) ;;
		unknown | refresh-required) ((++remaining_count)) ;;
		esac
	done

	printf '%s%s==Update report==%s\n\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
	_print_update_table_header action

	for row in "${rows[@]}"; do
		IFS='|' read -r component installed available state <<<"$row"
		[[ -n "$component" ]] || continue
		display="$(_check_state_display "$state")"
		_print_check_table_row "$component" "$installed" "$available" "$display" action
	done

	printf '\n'
	if [[ $upgrade_count -eq 0 && $remaining_count -eq 0 ]]; then
		printf '%s0 verified upgrades%s — everything verified current.\n' "$C_GREEN" "$C_RESET"
	elif [[ $upgrade_count -eq 0 ]]; then
		printf '%s0 verified upgrades; %d checks or refreshes remain.%s\n' \
			"$C_YELLOW" "$remaining_count" "$C_RESET"
	else
		# shellcheck disable=SC2016  # Backticks are literal documentation formatting.
		printf '%s%d verified upgrade%s available' \
			"$C_YELLOW" "$upgrade_count" "$([[ $upgrade_count -eq 1 ]] && echo '' || echo 's')"
		if [[ $remaining_count -gt 0 ]]; then
			printf '; %d checks or refreshes remain' "$remaining_count"
		fi
		# shellcheck disable=SC2016  # Backticks are literal documentation formatting.
		printf '%s — run `%sdotfiles update%s` to apply.\n' \
			"$C_RESET" "$C_BOLD" "$C_RESET"
	fi
	printf '\n'
}

print_upgrade_summary() {
	local repo_result_name="${1:-}"
	local -a rows=()
	local row component installed available _state result display
	local updated_count=0 current_count=0 checked_count=0 recovered_count=0
	local skipped_count=0 fail_count=0 not_run_count=0

	mapfile -t rows < <(_collect_check_rows "$repo_result_name")

	printf '\n%s%s==Upgrade summary==%s\n\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
	_print_update_table_header result

	for row in "${rows[@]}"; do
		IFS='|' read -r component installed available _state <<<"$row"
		[[ -n "$component" ]] || continue
		result="${UPGRADE_STEP_RESULT[$component]:-}"
		if [[ -z "$result" ]]; then
			case "$component" in
			"dotfiles repo") result="$UPGRADE_RESULT_CHECKED_NO_CHANGE" ;;
			*) result="$UPGRADE_RESULT_NOT_RUN" ;;
			esac
		fi
		case "$result" in
		updated) ((++updated_count)) ;;
		already-current) ((++current_count)) ;;
		checked-no-change) ((++checked_count)) ;;
		recovered) ((++recovered_count)) ;;
		skipped) ((++skipped_count)) ;;
		failed) ((++fail_count)) ;;
		not-run) ((++not_run_count)) ;;
		esac
		display="$(_upgrade_result_display "$result")"
		_print_check_table_row "$component" "$installed" "$available" "$display" result
	done

	printf '\n'
	[[ $fail_count -eq 0 ]] && printf '%s' "$C_GREEN" || printf '%s' "$C_RED"
	printf 'Upgrade finished%s — %d updated; %d already current; %d checked/no change; %d recovered; %d skipped; %d failed; %d not run.\n' \
		"$C_RESET" "$updated_count" "$current_count" "$checked_count" "$recovered_count" \
		"$skipped_count" "$fail_count" "$not_run_count"
}

# --- Subcommands ---
_dotfiles_confirm() {
	local prompt="$1" answer=''
	printf '%s%s%s [y/N]: ' "$C_YELLOW" "$prompt" "$C_RESET"
	IFS= read -r answer || true
	case "$answer" in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
}

_dotfiles_confirm_repo_update() {
	local _event="$1" prompt="$2"
	_dotfiles_confirm "$prompt"
}

_update_apt_packages() {
	command -v apt-get >/dev/null 2>&1 || {
		_warn '  apt-get not found, skipping'
		upgrade_result_set skipped
		return 0
	}
	sudo apt-get -o Dpkg::Use-Pty=0 upgrade -y || return $?
	upgrade_result_set checked-no-change
}

# One approved update runs every managed step, including the runtimes and fonts
# that `--all` used to gate. See cmd_update for the compatibility note.
_run_update_downstream() {
	local apt_refresh_rc=0 npm_target='' npm_retry='nvm install-latest-npm'
	UPGRADE_STEP_RESULT=()
	if command -v apt-get >/dev/null 2>&1; then
		sudo apt-get update -qq || apt_refresh_rc=$?
		if [[ $apt_refresh_rc -ne 0 ]]; then
			_report_command_failure "$apt_refresh_rc" "sudo apt-get update"
			UPGRADE_STEP_RESULT["apt packages"]="$UPGRADE_RESULT_FAILED"
			return "$apt_refresh_rc"
		fi
	fi
	_run_upgrade_step "apt packages" "sudo apt-get upgrade" _update_apt_packages
	_run_upgrade_step "Graphify CLI" "uv tool upgrade graphifyy" upgrade_graphify_cli
	_run_upgrade_step "Boost CLI" "dotfiles update" upgrade_boost_cli
	_run_upgrade_step "Cursor CLI" "dotfiles update" upgrade_cursor_cli
	_run_upgrade_step "Codex CLI" "npm i -g @openai/codex@latest" upgrade_codex_cli
	_run_upgrade_step "Claude CLI" "claude update" upgrade_claude_cli
	_run_upgrade_step "Copilot CLI" "copilot update" upgrade_copilot_cli
	_run_upgrade_step "lazygit" "dotfiles update" upgrade_lazygit
	_run_upgrade_step "lazydocker" "dotfiles update" upgrade_lazydocker

	_run_upgrade_step "Node.js (nvm)" "nvm install --lts" upgrade_node
	npm_target="$(npm_available_version)"
	if npm_version_token_is_safe "$npm_target"; then
		npm_retry="npm install -g npm@${npm_target} --engine-strict --allow-remote=all"
	fi
	_run_upgrade_step "npm" "$npm_retry" upgrade_npm "$npm_target"
	_run_upgrade_step "Go (asdf)" "asdf install golang latest" upgrade_go
	_run_upgrade_step "Monaspace fonts" "dotfiles update" upgrade_monaspace

	local result failures=0
	for result in "${UPGRADE_STEP_RESULT[@]}"; do [[ "$result" == "$UPGRADE_RESULT_FAILED" ]] && failures=$((failures + 1)); done
	((failures == 0))
}

_dotfiles_run_update() {
	local repository_decision_fn="$1" unattended="$2" dry_run="${3:-false}" repo_rc=0
	local -A repo_result=()
	repo_update_run "$DOTFILES_DIR" 'dotfiles repo' "$repository_decision_fn" repo_result 'PamuduW/dotfiles' || repo_rc=$?
	if ((repo_rc == 2)); then
		repo_update_print_changed
		return 2
	fi
	repo_update_is_declined repo_result && return 0
	[[ "$repo_rc" -eq 0 ]] || return 1

	print_report_table repo_result
	if [[ "$dry_run" == true ]]; then
		_msg 'Dry run: nothing was changed downstream.'
		return 0
	fi
	if [[ "$unattended" != true ]] && ! _dotfiles_confirm "Proceed with apt refresh and downstream updates?"; then
		_msg 'Downstream updates skipped.'
		return 0
	fi
	printf '\n%s%s=== Upgrade ===%s\n' "$C_BOLD" "$C_ORANGE" "$C_RESET"
	local downstream_rc=0
	_run_update_downstream || downstream_rc=$?
	print_upgrade_summary repo_result
	return "$downstream_rc"
}

cmd_update() {
	local arg dry_run=false
	for arg in "$@"; do
		case "$arg" in
		# Report what would change, then stop before any downstream work.
		--dry-run) dry_run=true ;;
		# Accepted for compatibility only: one approved update already runs every
		# managed step, so --all selects nothing extra.
		--all) ;;
		-h | --help)
			cmd_help
			return 0
			;;
		*)
			_err "Unknown option: $arg"
			_msg 'Usage: dotfiles update [--all] [--dry-run]'
			return 1
			;;
		esac
	done
	_dotfiles_run_update _dotfiles_confirm_repo_update false "$dry_run"
}
