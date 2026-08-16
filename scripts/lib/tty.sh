# shellcheck shell=bash
# Central terminal input/output adapter.

if [[ "${_DOTFILES_TTY_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_TTY_LOADED=1

tty_input_path() {
	printf '%s\n' "${DOTFILES_TTY_INPUT:-/dev/tty}"
}

tty_output_path() {
	printf '%s\n' "${DOTFILES_TTY_OUTPUT:-/dev/tty}"
}

tty_available() {
	local input_path output_path fd
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
	output_path="$(tty_output_path)"
	tty_available || return 1
	# shellcheck disable=SC2059  # This is intentionally a printf-compatible adapter.
	printf "$@" >"$output_path"
}

read_tty_line() {
	local __var_name="$1"
	local prompt="$2"
	local value='' input_path output_path

	tty_available || return 1
	input_path="$(tty_input_path)"
	output_path="$(tty_output_path)"
	printf '%s' "$prompt" >"$output_path"
	IFS= read -r value <"$input_path" || return 1
	printf -v "$__var_name" '%s' "$value"
}
