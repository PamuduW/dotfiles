# shellcheck shell=bash
# Central terminal input/output adapter.

if [[ "${_DOTFILES_TTY_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_TTY_LOADED=1

# The seam has two forms, and they are not interchangeable:
#
#   paths (DOTFILES_TTY_INPUT/OUTPUT)  - the default, /dev/tty
#   descriptors (DOTFILES_TTY_IN_FD/OUT_FD) - already-open streams
#
# Descriptors exist because reopening a path restarts it. A caller that reads
# several values from one file-backed stream (the token menu, and the tests
# that drive it) must share one read position, which only a descriptor can do.
# When descriptors are set they win. Input and output are independent: a
# caller may use an already-open input stream with a path-backed transcript,
# which is why each direction has its own predicate and the pair never needed
# one.

tty_use_input_fd() {
	[[ -n "${DOTFILES_TTY_IN_FD:-}" ]]
}

tty_use_output_fd() {
	[[ -n "${DOTFILES_TTY_OUT_FD:-}" ]]
}

tty_input_path() {
	printf '%s\n' "${DOTFILES_TTY_INPUT:-/dev/tty}"
}

tty_output_path() {
	printf '%s\n' "${DOTFILES_TTY_OUTPUT:-/dev/tty}"
}

_tty_controlling_terminal_available() {
	local fd
	if { exec {fd}<>/dev/tty; } 2>/dev/null; then
		exec {fd}>&-
		return 0
	fi
	return 1
}

tty_input_available() {
	local input_path
	tty_use_input_fd && return 0
	input_path="$(tty_input_path)"
	[[ "$input_path" == /dev/tty ]] && _tty_controlling_terminal_available && return 0
	[[ "$input_path" != /dev/tty && -r "$input_path" ]]
}

tty_output_available() {
	local output_path
	tty_use_output_fd && return 0
	output_path="$(tty_output_path)"
	if [[ "$output_path" == /dev/tty ]]; then
		_tty_controlling_terminal_available
		return $?
	fi
	if [[ "$output_path" != /dev/tty ]]; then
		if [[ -e "$output_path" ]]; then
			[[ -w "$output_path" ]]
		else
			[[ -d "$(dirname -- "$output_path")" && -w "$(dirname -- "$output_path")" ]]
		fi
	fi
}

tty_available() {
	tty_input_available && tty_output_available
}

# Terminal echo, off for as long as a menu is on screen.
#
# `read -s` silences echo only while it is reading. A key pressed while the menu
# is drawing -- and a full page takes tens of milliseconds -- is echoed by the
# terminal driver instead, which is where a stray ^[[A on screen comes from.
# Held down, it is a column of them.
#
# Saved and restored rather than assumed: a caller may already have the terminal
# in a state of its own, and off a terminal there is nothing to do at all.
_TTY_ECHO_SAVED=''

tty_echo_off() {
	_TTY_ECHO_SAVED=''
	if tty_use_input_fd; then
		[[ -t "$DOTFILES_TTY_IN_FD" ]] || return 0
		_TTY_ECHO_SAVED="$(stty -g <&"$DOTFILES_TTY_IN_FD" 2>/dev/null)" || return 0
		stty -echo <&"$DOTFILES_TTY_IN_FD" 2>/dev/null || true
		return 0
	fi
	local input_path
	input_path="$(tty_input_path)"
	[[ -c "$input_path" ]] || return 0
	_TTY_ECHO_SAVED="$(stty -g <"$input_path" 2>/dev/null)" || return 0
	stty -echo <"$input_path" 2>/dev/null || true
}

tty_echo_restore() {
	local input_path
	[[ -n "$_TTY_ECHO_SAVED" ]] || return 0
	if tty_use_input_fd; then
		stty "$_TTY_ECHO_SAVED" <&"$DOTFILES_TTY_IN_FD" 2>/dev/null || true
	else
		input_path="$(tty_input_path)"
		stty "$_TTY_ECHO_SAVED" <"$input_path" 2>/dev/null || true
	fi
	_TTY_ECHO_SAVED=''
}

tty_printf() {
	local output_path
	if tty_use_output_fd; then
		# shellcheck disable=SC2059  # This is intentionally a printf-compatible adapter.
		printf "$@" >&"$DOTFILES_TTY_OUT_FD"
		return 0
	fi
	output_path="$(tty_output_path)"
	tty_output_available || return 1
	# Append rather than truncate: identical on /dev/tty, but a caller that
	# points the seam at a regular file (tests do) must accumulate output
	# instead of each write clobbering the last.
	# shellcheck disable=SC2059  # This is intentionally a printf-compatible adapter.
	printf "$@" >>"$output_path"
}

read_tty_line() {
	local __var_name="$1"
	local prompt="$2"
	local value='' input_path output_path

	tty_available || return 1
	input_path="$(tty_input_path)"
	if tty_use_output_fd; then
		printf '%s' "$prompt" >&"$DOTFILES_TTY_OUT_FD"
	else
		output_path="$(tty_output_path)"
		printf '%s' "$prompt" >>"$output_path"
	fi
	if tty_use_input_fd; then
		IFS= read -r value <&"$DOTFILES_TTY_IN_FD" || return 1
	else
		IFS= read -r value <"$input_path" || return 1
	fi
	printf -v "$__var_name" '%s' "$value"
}

# A secret read that still shows the operator something is landing: one '*' per
# character, backspace erases. Silent reads left them unable to tell a stalled
# prompt from a typed one.
# mask_char is what each keystroke echoes. Passing an empty string echoes
# nothing, which is what the sudo prompt wants: sudo's own prompt is silent, and
# a masked one that is not tells a shoulder-surfer the length of the password.
read_tty_secret() {
	local __var_name="$1"
	local prompt="$2"
	local __mask="${3-*}"
	# Underscored on purpose: a plain `value` here would be the local this
	# function assigns, not the caller's variable of the same name, and the
	# secret would silently come back empty.
	local __secret='' __char='' __rc=0

	tty_available || return 1
	tty_printf '%s' "$prompt"
	while true; do
		tty_read_key_char __char || {
			__rc=$?
			break
		}
		case "$__char" in
		'') break ;;
		$'\177' | $'\b')
			if [[ -n "$__secret" ]]; then
				__secret="${__secret%?}"
				if [[ -n "$__mask" ]]; then tty_printf '\b \b'; fi
			fi
			;;
		*)
			__secret+="$__char"
			if [[ -n "$__mask" ]]; then tty_printf '%s' "$__mask"; fi
			;;
		esac
	done
	tty_printf '\n'
	((__rc == 0)) || return "$__rc"
	printf -v "$__var_name" '%s' "$__secret"
}

tty_read_key_char() {
	local __var_name="$1"
	shift
	local value='' input_path rc=0

	if tty_use_input_fd; then
		IFS= read -rsn1 "$@" value <&"$DOTFILES_TTY_IN_FD" || rc=$?
	else
		tty_input_available || return 1
		input_path="$(tty_input_path)"
		IFS= read -rsn1 "$@" value <"$input_path" || rc=$?
	fi
	printf -v "$__var_name" '%s' "$value"
	return "$rc"
}
