# shellcheck shell=bash

_github_token_menu_open_fds() {
	local in_path="${GITHUB_TOKEN_TTY_INPUT:-$(tty_input_path)}"
	local out_path="${GITHUB_TOKEN_TTY_OUTPUT:-$(tty_output_path)}"
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

_github_token_menu_secret() {
	local out_var="$1" prompt="$2" value=''
	# `read -rs` shows nothing at all, so a mistyped token gives no feedback that
	# anything was typed. read_tty_secret masks with * and supports backspace;
	# the SSH passphrase prompt has used it since it was written.
	#
	# It reads through the DOTFILES_TTY_* seam rather than this menu's own
	# descriptors, so point the seam at them for the duration of the call. These
	# are `local`, which in Bash is dynamic scope: the helper and everything it
	# calls see them, and the parent's values come back untouched afterwards.
	# shellcheck disable=SC2034  # Read by read_tty_secret through dynamic scope.
	local DOTFILES_TTY_IN_FD="$GITHUB_TOKEN_MENU_IN_FD"
	# shellcheck disable=SC2034  # Read by read_tty_secret through dynamic scope.
	local DOTFILES_TTY_OUT_FD="$GITHUB_TOKEN_MENU_OUT_FD"
	read_tty_secret value "$prompt" || value='q'
	printf -v "$out_var" '%s' "$value"
}

# [y/N], not [y/N/q]. The hint said q for long enough to look deliberate, but
# nothing below reads it: every answer that is not y is no, and all three
# callers -- save, reveal, remove -- treat a no as "go back". A third key that
# does what the second key does is a promise the screen cannot keep, and the
# sibling product's shared tui_confirm never made it.
_github_token_menu_confirm() {
	local answer=''
	_github_token_menu_line answer "${C_YELLOW:-}$1${C_RESET:-} [y/N]: "
	case "$answer" in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
}

_github_token_menu_pause() {
	# shellcheck disable=SC2034  # Filled indirectly by _github_token_menu_line.
	local ignored=''
	# The leading blank ui_pause prints, for the same reason.
	printf '\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
	_github_token_menu_line ignored "  ${C_DIM:-}Press Enter to continue:${C_RESET:-} "
}

# What the last action did, shown by the next frame.
#
# Every outcome here used to be printed and then wiped: the loop clears the
# screen and re-renders before the operator can read "GitHub token saved." or
# "Invalid token; nothing was saved." Only the reveal survived, because it
# pauses. Carried into the next frame instead, which is what the checkbox menu
# does with MENU_CB_STATUS_MESSAGE and costs no extra keystroke.
_GITHUB_TOKEN_MENU_STATUS=''

_github_token_menu_say() {
	_GITHUB_TOKEN_MENU_STATUS="$1"
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
	printf '  %s\n' \
		"$(ui_format_shortcuts s 'Save or replace' r 'Reveal once' \
			c 'Check with GitHub' d Remove q Back)${C_RESET:-}" \
		>&"$GITHUB_TOKEN_MENU_OUT_FD"
	if [[ -n "$_GITHUB_TOKEN_MENU_STATUS" ]]; then
		printf '\n  %s\n' "$_GITHUB_TOKEN_MENU_STATUS" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	fi
	printf '\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
}

# Ask GitHub before saving, rather than only checking the shape. A refusal is
# definitive -- the token is wrong, expired or revoked -- so nothing is saved
# and the operator is told which of those it is not. Being unable to ask is not
# a refusal: an operator configuring this offline still gets the normal
# question, with the check named as skipped rather than passed.
_github_token_menu_check() {
	local token="$1" rc=0
	printf '  %sChecking it with GitHub...%s\n' \
		"${C_DIM:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	github_token_verify "$token" || rc=$?
	case "$rc" in
	0)
		printf '  %sGitHub accepted it.%s\n\n' \
			"${C_GREEN:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		;;
	1)
		_github_token_menu_say "${C_RED:-}GitHub rejected this token; nothing was saved.${C_RESET:-}"
		return 1
		;;
	*)
		printf '  %sCould not reach GitHub to check it; saving without a check.%s\n\n' \
			"${C_YELLOW:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		;;
	esac
}

_github_token_menu_save() {
	local token=''
	printf '  %sInput is hidden; only its fingerprint will be shown.%s\n' \
		"${C_DIM:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	_github_token_menu_secret token "  ${C_CYAN:-}GitHub token${C_RESET:-} (q cancels): "
	[[ "$token" != q && "$token" != Q && -n "$token" ]] || return 0
	if ! github_token_is_valid "$token"; then
		_github_token_menu_say "${C_RED:-}Invalid token; nothing was saved.${C_RESET:-}"
		return 0
	fi
	printf '\n  %sProposed:%s %s%s%s\n' \
		"${C_DIM:-}" "${C_RESET:-}" "${C_CYAN:-}" \
		"$(github_token_fingerprint "$token")" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	_github_token_menu_check "$token" || return 0
	if _github_token_menu_confirm "  Save this token?"; then
		if github_token_write "$token"; then
			_github_token_menu_say "${C_GREEN:-}GitHub token saved.${C_RESET:-}"
		else
			_github_token_menu_say "${C_RED:-}GitHub token was not saved.${C_RESET:-}"
		fi
	fi
}

_github_token_menu_reveal() {
	local token=''
	github_token_read token
	if [[ -z "$token" ]]; then
		_github_token_menu_say "${C_YELLOW:-}No valid saved token is available to reveal.${C_RESET:-}"
		return 0
	fi
	printf '  %sWARNING: the full token will be printed once on this terminal.%s\n\n' \
		"${C_RED:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	if _github_token_menu_confirm "  Reveal the full token once?"; then
		# The secret gets space around it: it is the one line on this screen
		# the operator has to read off the terminal and type somewhere else.
		printf '\n  %s\n' "$token" >&"$GITHUB_TOKEN_MENU_OUT_FD"
		_github_token_menu_pause
	fi
}

# The saved token, checked against GitHub on demand. Saving checks what is
# being typed; nothing checked what was already there, and a token that was
# good when it was saved is exactly the thing that expires or gets revoked
# later. Same three outcomes as the save path, for the same reasons.
_github_token_menu_check_saved() {
	local token='' rc=0
	github_token_read token
	if [[ -z "$token" ]]; then
		_github_token_menu_say "${C_YELLOW:-}No valid saved token to check.${C_RESET:-}"
		return 0
	fi
	printf '  %sChecking the saved token with GitHub...%s\n' \
		"${C_DIM:-}" "${C_RESET:-}" >&"$GITHUB_TOKEN_MENU_OUT_FD"
	github_token_verify "$token" || rc=$?
	case "$rc" in
	0) _github_token_menu_say "${C_GREEN:-}GitHub accepted the saved token.${C_RESET:-}" ;;
	1) _github_token_menu_say "${C_RED:-}GitHub rejected the saved token; it is invalid, expired, or revoked.${C_RESET:-}" ;;
	*) _github_token_menu_say "${C_YELLOW:-}Could not reach GitHub to check the saved token.${C_RESET:-}" ;;
	esac
}

_github_token_menu_remove() {
	if [[ ! -e "$(github_token_file)" && ! -L "$(github_token_file)" ]]; then
		_github_token_menu_say "${C_DIM:-}No saved token file exists.${C_RESET:-}"
		return 0
	fi
	if _github_token_menu_confirm "  Remove the saved token?"; then
		GITHUB_TOKEN_REMOVE_REASON=''
		if github_token_remove; then
			_github_token_menu_say "${C_GREEN:-}Saved token removed.${C_RESET:-}"
		else
			_github_token_menu_say "${C_RED:-}Not removed: ${GITHUB_TOKEN_REMOVE_REASON:-the saved token could not be removed safely}.${C_RESET:-}"
		fi
	fi
}

github_token_menu() {
	local action=''
	_github_token_menu_open_fds || return 1
	_github_token_warning_scope_begin
	_GITHUB_TOKEN_MENU_STATUS=''
	while true; do
		ui_clear
		_github_token_menu_render
		# Shown once: it describes what just happened, not what is true.
		_GITHUB_TOKEN_MENU_STATUS=''
		_github_token_menu_line action "  ${C_BOLD:-}Select action:${C_RESET:-} "
		# One blank below the answer, so an action's output starts on its own
		# rather than running straight on from the line it was asked on. Here
		# rather than in each action: every one of them wants it.
		printf '\n' >&"$GITHUB_TOKEN_MENU_OUT_FD"
		case "$action" in
		s | S) _github_token_menu_save ;;
		r | R) _github_token_menu_reveal ;;
		c | C) _github_token_menu_check_saved ;;
		d | D) _github_token_menu_remove ;;
		q | Q) break ;;
		*) _github_token_menu_say "${C_YELLOW:-}Invalid choice.${C_RESET:-}" ;;
		esac
	done
	_github_token_warning_scope_end
	_github_token_menu_close_fds
}
