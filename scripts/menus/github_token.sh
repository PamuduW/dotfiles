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
	_github_token_menu_line answer "$1 [y/N/q]: "
	case "$answer" in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
}

_github_token_menu_pause() {
	# shellcheck disable=SC2034  # Filled indirectly by _github_token_menu_line.
	local ignored=''
	_github_token_menu_line ignored "Press Enter to continue: "
}

_github_token_menu_render() {
	local token='' current='not configured' root="${DOTFILES_MENU_ROOT:-Dotfiles}"
	local cols="${GITHUB_TOKEN_TTY_COLS:-}"
	if [[ -z "$cols" ]]; then
		cols="$(menu_tty_cols)"
	fi
	github_token_read token
	if [[ -n "$token" ]]; then
		current="$(github_token_fingerprint "$token")"
	elif [[ -e "$(github_token_file)" || -L "$(github_token_file)" ]]; then
		current='saved state is invalid or unsafe'
	fi
	ui_print_header "GitHub Token Config" "${root} › GitHub Token Config" "$cols" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  Current: %s\n' "$current" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  Saved outside this repository: %s\n\n' "$(github_token_file)" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  Optional: raises public-repository API rate limits.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  No repository scopes are needed for this workflow.\n\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
	printf '  [s] Save or replace   [r] Reveal once   [d] Remove   [q] Back\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
}

_github_token_menu_save() {
	local token=''
	printf '  Input is visible on screen and may be seen by others.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
	_github_token_menu_line token "  GitHub token (q cancels): "
	[[ "$token" != q && "$token" != Q && -n "$token" ]] || return 0
	if ! github_token_is_valid "$token"; then
		printf '  Invalid token; nothing was saved.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
		return 0
	fi
	printf '  Proposed: %s\n' "$(github_token_fingerprint "$token")" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	if _github_token_menu_confirm "  Save this token?"; then
		if github_token_write "$token"; then
			printf '  GitHub token saved.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
		else
			printf '  GitHub token was not saved.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
		fi
	fi
}

_github_token_menu_reveal() {
	local token=''
	github_token_read token
	if [[ -z "$token" ]]; then
		printf '  No valid saved token is available to reveal.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
		return 0
	fi
	printf '  WARNING: the full token will be printed once on this terminal.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
	if _github_token_menu_confirm "  Reveal the full token once?"; then
		printf '  %s\n' "$token" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		_github_token_menu_pause
	fi
}

_github_token_menu_remove() {
	if [[ ! -e "$(github_token_file)" && ! -L "$(github_token_file)" ]]; then
		printf '  No saved token file exists.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
		return 0
	fi
	if _github_token_menu_confirm "  Remove the saved token?"; then
		if github_token_remove; then
			printf '  Saved token removed.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
		else
			printf '  Saved token could not be removed safely.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
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
		_github_token_menu_line action "  Select action: "
		case "$action" in
		s | S) _github_token_menu_save ;;
		r | R) _github_token_menu_reveal ;;
		d | D) _github_token_menu_remove ;;
		q | Q) break ;;
		*) printf '  Invalid choice.\n' >&"$GITHUB_TOKEN_MENU_OUT_FD" ;;
		esac
	done
	_github_token_warning_scope_end
	_github_token_menu_close_fds
}
