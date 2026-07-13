# shellcheck shell=bash
# TTY line input helpers.

read_tty_line() {
	local __var_name="$1"
	local prompt="$2"
	local value=''

	printf '%s' "$prompt" >/dev/tty
	IFS= read -r value </dev/tty
	printf -v "$__var_name" '%s' "$value"
}

read_tty_secret() {
	local __var_name="$1"
	local prompt="$2"
	local value=''

	printf '%s' "$prompt" >/dev/tty
	IFS= read -r -s value </dev/tty
	printf '\n' >/dev/tty
	printf -v "$__var_name" '%s' "$value"
}
