# shellcheck shell=bash

_github_token_menu_open_fds() {
	local in_path="${GITHUB_TOKEN_TTY_INPUT:-/dev/tty}"
	local out_path="${GITHUB_TOKEN_TTY_OUTPUT:-/dev/tty}"
	exec {GITHUB_TOKEN_MENU_IN_FD}<"$in_path"
	exec {GITHUB_TOKEN_MENU_OUT_FD}>"$out_path"
}

_github_token_menu_close_fds() {
	exec {GITHUB_TOKEN_MENU_IN_FD}<&-
	exec {GITHUB_TOKEN_MENU_OUT_FD}>&-
}

_github_token_menu_line() {
	local out_var="$1" prompt="$2" value=''
	printf '%s' "$prompt" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	IFS= read -r value <&"$GITHUB_TOKEN_MENU_IN_FD" || value='q'
	printf -v "$out_var" '%s' "$value"
}

_github_token_menu_confirm() {
	local answer=''
	_github_token_menu_line answer "${C_YELLOW:-}$1${C_RESET:-} [y/N/q]: "
	case "$answer" in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
}

_github_token_menu_pause() {
	# shellcheck disable=SC2034  # Filled indirectly by _github_token_menu_line.
	local ignored=''
	_github_token_menu_line ignored "${C_DIM:-}Press Enter to continue:${C_RESET:-} "
}

_github_token_menu_render() {
	local token='' current='not configured' current_color="${C_DIM:-}"
	local root="${DOTFILES_MENU_ROOT:-Dotfiles}"
	local cols="${GITHUB_TOKEN_TTY_COLS:-}"
	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi
	github_token_read token
	if [[ -n "$token" ]]; then
		current="$(github_token_fingerprint "$token")"
		current_color="${C_GREEN:-}"
	elif [[ -e "$(github_token_file)" || -L "$(github_token_file)" ]]; then
		current='saved state is invalid or unsafe'
		current_color="${C_RED:-}"
	fi
	ui_print_header "GitHub Token Config" "${root} › GitHub Token Config" "$cols" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  %sCurrent:%s %s%s%s\n' \
		"${C_BOLD:-}" "${C_RESET:-}" "$current_color" "$current" "${C_RESET:-}" \
		>&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  %sSaved outside this repository:%s %s%s%s\n\n' \
		"${C_DIM:-}" "${C_RESET:-}" "${C_CYAN:-}" "$(github_token_file)" "${C_RESET:-}" \
		>&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  %sOptional:%s raises public-repository API rate limits.\n' \
		"${C_DIM:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  %sNo repository scopes are needed for this workflow.%s\n\n' \
		"${C_DIM:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  %s[s]%s Save or replace   %s[r]%s Reveal once   %s[d]%s Remove   %s[q]%s Back\n' \
		"${C_CYAN:-}" "${C_RESET:-}" "${C_CYAN:-}" "${C_RESET:-}" \
		"${C_CYAN:-}" "${C_RESET:-}" "${C_CYAN:-}" "${C_RESET:-}" \
		>&"$GITHUB_TOKEN_MENU_OUT_FD"
}

_github_token_menu_save() {
	local token=''
	printf '  %sInput is visible on screen and may be seen by others.%s\n' \
		"${C_YELLOW:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	_github_token_menu_line token "  ${C_CYAN:-}GitHub token${C_RESET:-} (q cancels): "
	[[ "$token" != q && "$token" != Q && -n "$token" ]] || return 0
	if ! github_token_is_valid "$token"; then
		printf '  %sInvalid token; nothing was saved.%s\n' \
			"${C_RED:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		return 0
	fi
	printf '  %sProposed:%s %s%s%s\n' \
		"${C_DIM:-}" "${C_RESET:-}" "${C_CYAN:-}" \
		"$(github_token_fingerprint "$token")" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	if _github_token_menu_confirm "  Save this token?"; then
		if github_token_write "$token"; then
			printf '  %sGitHub token saved.%s\n' \
				"${C_GREEN:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		else
			printf '  %sGitHub token was not saved.%s\n' \
				"${C_RED:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		fi
	fi
}

_github_token_menu_reveal() {
	local token=''
	github_token_read token
	if [[ -z "$token" ]]; then
		printf '  %sNo valid saved token is available to reveal.%s\n' \
			"${C_YELLOW:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		return 0
	fi
	printf '  %sWARNING: the full token will be printed once on this terminal.%s\n' \
		"${C_RED:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	if _github_token_menu_confirm "  Reveal the full token once?"; then
		printf '  %s\n' "$token" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		_github_token_menu_pause
	fi
}

_github_token_menu_remove() {
	if [[ ! -e "$(github_token_file)" && ! -L "$(github_token_file)" ]]; then
		printf '  %sNo saved token file exists.%s\n' \
			"${C_DIM:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		return 0
	fi
	if _github_token_menu_confirm "  Remove the saved token?"; then
		if github_token_remove; then
			printf '  %sSaved token removed.%s\n' \
				"${C_GREEN:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		else
			printf '  %sSaved token could not be removed safely.%s\n' \
				"${C_RED:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		fi
	fi
}

github_token_menu() {
	local action=''
	_github_token_menu_open_fds || return 1
	_github_token_warning_scope_begin
	while true; do
		ui_clear
		_github_token_menu_render
		_github_token_menu_line action "  ${C_BOLD:-}Select action:${C_RESET:-} "
		case "$action" in
		s | S) _github_token_menu_save ;;
		r | R) _github_token_menu_reveal ;;
		d | D) _github_token_menu_remove ;;
		q | Q) break ;;
		*) printf '  %sInvalid choice.%s\n' "${C_YELLOW:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD" ;;
		esac
	done
	_github_token_warning_scope_end
	_github_token_menu_close_fds
}
