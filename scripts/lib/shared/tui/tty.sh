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
# When descriptors are set they win.

tty_use_fds() {
	[[ -n "${DOTFILES_TTY_IN_FD:-}" && -n "${DOTFILES_TTY_OUT_FD:-}" ]]
}

tty_input_path() {
	printf '%s\n' "${DOTFILES_TTY_INPUT:-/dev/tty}"
}

tty_output_path() {
	printf '%s\n' "${DOTFILES_TTY_OUTPUT:-/dev/tty}"
}

tty_available() {
	local input_path output_path fd
	tty_use_fds && return 0
	input_path="$(tty_input_path)"
	output_path="$(tty_output_path)"
	if [[ "$input_path" != /dev/tty || "$output_path" != /dev/tty ]]; then
		[[ -r "$input_path" ]] || return 1
		if [[ -e "$output_path" ]]; then
			[[ -w "$output_path" ]]
		else
			[[ -d "$(dirname -- "$output_path")" && -w "$(dirname -- "$output_path")" ]]
		fi
		return
	fi
	if { exec {fd}<>/dev/tty; } 2>/dev/null; then
		exec {fd}>&-
		return 0
	fi
	return 1
}

tty_printf() {
	local output_path
	if tty_use_fds; then
		# shellcheck disable=SC2059  # This is intentionally a printf-compatible adapter.
		printf "$@" >&"$DOTFILES_TTY_OUT_FD"
		return 0
	fi
	output_path="$(tty_output_path)"
	tty_available || return 1
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

	if tty_use_fds; then
		printf '%s' "$prompt" >&"$DOTFILES_TTY_OUT_FD"
		IFS= read -r value <&"$DOTFILES_TTY_IN_FD" || return 1
		printf -v "$__var_name" '%s' "$value"
		return 0
	fi

	tty_available || return 1
	input_path="$(tty_input_path)"
	output_path="$(tty_output_path)"
	printf '%s' "$prompt" >>"$output_path"
	IFS= read -r value <"$input_path" || return 1
	printf -v "$__var_name" '%s' "$value"
}
