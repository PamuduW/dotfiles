# shellcheck shell=bash
# shellcheck disable=SC2034  # repo_result is populated through a nameref by repo_update_run.
# Repository-first update orchestration and fixed-width update reports.
# Depends on update_components.sh and repo_update.sh.

_color_action() { status_color_action "$1"; }
_color_result() { status_color_result "$1"; }

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
	local row component installed available action
	local upgrade_count=0

	mapfile -t rows < <(_collect_check_rows "$repo_result_name")

	for row in "${rows[@]}"; do
		IFS='|' read -r _ _ _ action <<<"$row"
		case "$action" in
		upgrade | upgrade*) ((++upgrade_count)) ;;
		pull*) ((++upgrade_count)) ;;
		esac
	done

	printf '%s%s==Update report==%s\n\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
	_print_update_table_header action

	for row in "${rows[@]}"; do
		IFS='|' read -r component installed available action <<<"$row"
		_print_check_table_row "$component" "$installed" "$available" "$action" action
	done

	printf '\n'
	if [[ $upgrade_count -eq 0 ]]; then
		printf '%s0 upgrades available%s — everything looks current.\n' "$C_GREEN" "$C_RESET"
	else
		# shellcheck disable=SC2016  # Backticks are literal documentation formatting.
		printf '%s%d upgrade%s available%s — run `%sdotfiles update%s` to apply.\n' \
			"$C_YELLOW" "$upgrade_count" "$([[ $upgrade_count -eq 1 ]] && echo '' || echo 's')" "$C_RESET" \
			"$C_BOLD" "$C_RESET"
	fi
	printf '\n'
}

print_upgrade_summary() {
	local repo_result_name="${1:-}"
	local -a rows=()
	local row component installed available _action result
	local ok_count=0 fail_count=0

	mapfile -t rows < <(_collect_check_rows "$repo_result_name")

	printf '\n%s%s==Upgrade summary==%s\n\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
	_print_update_table_header result

	for row in "${rows[@]}"; do
		IFS='|' read -r component installed available _action <<<"$row"
		result="${UPGRADE_STEP_RESULT[$component]:-}"
		if [[ -z "$result" ]]; then
			case "$component" in
			"dotfiles repo") result="ok" ;;
			*) result="—" ;;
			esac
		fi
		case "$result" in
		ok) ((++ok_count)) ;;
		failed) ((++fail_count)) ;;
		esac
		_print_check_table_row "$component" "$installed" "$available" "$result" result
	done

	printf '\n'
	if [[ $fail_count -eq 0 ]]; then
		printf '%sUpgrade finished%s — %d step(s) ok.\n' "$C_GREEN" "$C_RESET" "$ok_count"
	else
		printf '%sUpgrade finished with %d failure(s)%s — see log above.\n' "$C_RED" "$fail_count" "$C_RESET"
	fi
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
		return 0
	}
	sudo apt-get -o Dpkg::Use-Pty=0 upgrade -y
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
			UPGRADE_STEP_RESULT["apt packages"]="failed"
			return "$apt_refresh_rc"
		fi
	fi
	_run_upgrade_step "apt packages" "sudo apt-get upgrade" _update_apt_packages
	_run_upgrade_step "Graphify CLI" "uv tool upgrade graphifyy" upgrade_graphify_cli
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
	for result in "${UPGRADE_STEP_RESULT[@]}"; do [[ "$result" == failed ]] && failures=$((failures + 1)); done
	((failures == 0))
}

_dotfiles_run_update() {
	local repository_decision_fn="$1" unattended="$2" repo_rc=0
	local -A repo_result=()
	repo_update_run "$DOTFILES_DIR" 'dotfiles repo' "$repository_decision_fn" repo_result 'PamuduW/dotfiles' || repo_rc=$?
	if ((repo_rc == 2)); then
		repo_update_print_changed
		return 2
	fi
	repo_update_is_declined repo_result && return 0
	[[ "$repo_rc" -eq 0 ]] || return 1

	print_report_table repo_result
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
	local arg
	for arg in "$@"; do
		case "$arg" in
		# Accepted for compatibility only: one approved update already runs every
		# managed step, so --all selects nothing extra.
		--all) ;;
		-h | --help)
			cmd_help
			return 0
			;;
		*)
			_err "Unknown option: $arg"
			_msg 'Usage: dotfiles update [--all]'
			return 1
			;;
		esac
	done
	_dotfiles_run_update _dotfiles_confirm_repo_update false
}
