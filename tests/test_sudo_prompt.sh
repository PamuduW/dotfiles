#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# The sudo prompt echoes nothing: a `*` per keystroke publishes the length of
# the password, and this is the prompt the operator answers most often and in
# the least private places. SUDO_ASKPASS replaces sudo's own prompt so the run
# can place it; sudo's credential cache means one prompt covers the whole run.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
passed=0
failed=0

check() {
	local label="$1"
	shift
	if "$@"; then
		printf 'ok - %s\n' "$label"
		passed=$((passed + 1))
	else
		printf 'not ok - %s\n' "$label"
		failed=$((failed + 1))
	fi
}

test_askpass_echoes_nothing_and_prints_the_password() {
	local out="$TEST_DIR/.askpass.out" seen got
	printf 'hunter2\n' >"$TEST_DIR/.askpass.in"
	got="$(
		exec {infd}<"$TEST_DIR/.askpass.in"
		exec {outfd}>"$out"
		DOTFILES_TTY_IN_FD=$infd DOTFILES_TTY_OUT_FD=$outfd \
			bash "$REPO_DIR/scripts/lib/shared/askpass.sh" '[sudo] password:'
	)"
	seen="$(cat "$out")"
	rm -f "$TEST_DIR/.askpass.in" "$out"

	# sudo reads the password from stdout; the terminal gets the prompt and
	# nothing else -- no echo, no mask, and never the password itself.
	[[ "$got" == 'hunter2' ]] || return 1
	[[ "$seen" == *'[sudo] password:'* ]] || return 1
	[[ "$seen" != *'*'* ]] || return 1
	[[ "$seen" != *hunter2* ]]
}

_load_prime() {
	# shellcheck source=scripts/lib/shared/tui/tty.sh
	source "$REPO_DIR/scripts/lib/shared/tui/tty.sh"
	# shellcheck source=scripts/lib/shared/sudo_prime.sh
	source "$REPO_DIR/scripts/lib/shared/sudo_prime.sh"
}

test_prime_uses_the_owned_helper_when_a_terminal_exists() (
	_load_prime
	local calls=''
	sudo() {
		case "$*" in
		"-n true") return 1 ;;
		*)
			calls="$* askpass=${SUDO_ASKPASS:+set}"
			return 0
			;;
		esac
	}
	tty_available() { return 0; }
	sudo_prime || return 1
	[[ "$calls" == '-A -v askpass=set' ]]
)

test_prime_falls_back_to_sudo_without_a_terminal() (
	_load_prime
	local calls=''
	sudo() {
		case "$*" in
		"-n true") return 1 ;;
		*)
			calls="$* askpass=${SUDO_ASKPASS:+set}"
			return 0
			;;
		esac
	}
	tty_available() { return 1; }
	sudo_prime || return 1
	# No terminal means nothing to mask; sudo's own prompt is not worse than
	# before, and hanging on a closed handle would be.
	[[ "$calls" == '-v askpass=' ]]
)

test_prime_does_not_prompt_when_already_authenticated() (
	_load_prime
	local prompted=0
	sudo() {
		case "$*" in
		"-n true") return 0 ;;
		*) prompted=1 ;;
		esac
	}
	tty_available() { return 0; }
	sudo_prime || return 1
	((prompted == 0))
)

test_prime_is_silent_where_sudo_is_absent() (
	_load_prime
	command() {
		[[ "$*" == "-v sudo" ]] && return 1
		builtin command "$@"
	}
	sudo_prime
)

check 'askpass echoes nothing and gives sudo the password' test_askpass_echoes_nothing_and_prints_the_password
check 'priming uses the owned helper when a terminal exists' test_prime_uses_the_owned_helper_when_a_terminal_exists
check 'priming falls back to sudo without a terminal' test_prime_falls_back_to_sudo_without_a_terminal
check 'priming does not prompt when already authenticated' test_prime_does_not_prompt_when_already_authenticated
check 'priming is silent on a machine without sudo' test_prime_is_silent_where_sudo_is_absent

printf '\nRan %d sudo-prompt test(s); %d failure(s).\n' "$((passed + failed))" "$failed"
((failed == 0))
