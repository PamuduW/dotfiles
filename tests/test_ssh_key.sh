#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# SSH key generation, and specifically that it never stops to ask for anything.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

# A recording stand-in: the real ssh-keygen would want a terminal, which is the
# thing under test.
_install_fake_keygen() {
	local bin="$1"
	mkdir -p -- "$bin"
	cat >"$bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$KEYGEN_ARGS"
IFS= read -r line || line='<empty>'
printf 'stdin:%s\n' "$line" >>"$KEYGEN_ARGS"
key=''
for ((i = 1; i <= $#; i++)); do
	[[ "${!i}" == -f ]] && { j=$((i + 1)); key="${!j}"; }
done
printf 'private\n' >"$key"
printf 'ssh-ed25519 AAAA test\n' >"$key.pub"
EOF
	chmod +x -- "$bin/ssh-keygen"
	for stub in ssh-agent ssh-add; do
		printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$(basename "$0")" >>"$AGENT_CALLS"\nexit 0\n' >"$bin/$stub"
		chmod +x -- "$bin/$stub"
	done
}

_run_generate_ssh_key() (
	local home="$1" passphrase="$2" bin="$3"
	export HOME="$home" KEYGEN_ARGS="$home/keygen-args" AGENT_CALLS="$home/agent-calls" PATH="$bin:$PATH"
	export SETUP_GIT_EMAIL='test@example.com'
	export SETUP_SSH_PASSPHRASE="$passphrase"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	source "$REPO_DIR/scripts/lib/installers/stow.sh"
	generate_ssh_key
)

test_generation_never_waits_for_input() (
	# Break caught: ssh-keygen inherited stdin, which under `curl ... | bash` is
	# the pipe. It fell back to ssh-askpass, which is not installed, so the run
	# announced a passphrase prompt, never prompted, and wrote an unprotected
	# key. The passphrase is now collected with the Git identity, before the
	# plan is confirmed, so nothing interrupts a running install.
	local machine="$TEST_HARNESS_ROOT/collected" bin="$TEST_HARNESS_ROOT/collected/bin"
	mkdir -p -- "$machine/home"
	_install_fake_keygen "$bin"

	local output
	output="$(_run_generate_ssh_key "$machine/home" 'from-the-menu' "$bin" </dev/null 2>&1)" || return 1
	# -N carries the collected answer, so ssh-keygen has nothing left to ask.
	grep -Fq -- "-N from-the-menu" "$machine/home/keygen-args" || return 1
	# Nothing was read: the run was given /dev/null, and a prompt would hang it.
	grep -Fqx 'stdin:<empty>' "$machine/home/keygen-args" || return 1
	[[ "$output" != *"You'll be prompted"* ]] || return 1
	[[ "$output" == *'protected by a passphrase'* ]] || return 1
	# ssh-add on a protected key would stop here asking for it again.
	! grep -Fq 'ssh-add' "$machine/home/agent-calls" 2>/dev/null
)

test_no_collected_passphrase_says_the_key_is_unprotected() (
	# The fallback for any path that never collected an answer: an unprotected
	# key and a line saying so, not a promise of a prompt that cannot arrive.
	local machine="$TEST_HARNESS_ROOT/unasked" bin="$TEST_HARNESS_ROOT/unasked/bin"
	mkdir -p -- "$machine/home"
	_install_fake_keygen "$bin"

	local output
	output="$(_run_generate_ssh_key "$machine/home" '' "$bin" </dev/null 2>&1)" || return 1
	[[ "$output" != *"You'll be prompted"* ]] || return 1
	[[ "$output" == *'without a passphrase'* ]] || return 1
	grep -Fq -- "-N " "$machine/home/keygen-args"
)

# A file-backed terminal needs a descriptor, not a path: a path is reopened per
# call, so every read would return the first character again.
_with_fake_terminal() (
	local keystrokes="$1" out_file="$2"
	shift 2
	local in_file="${out_file%.out}.in"
	printf '%s' "$keystrokes" >"$in_file"
	: >"$out_file"
	local fd
	exec {fd}<"$in_file"
	DOTFILES_TTY_IN_FD="$fd" DOTFILES_TTY_OUTPUT="$out_file"
	export DOTFILES_TTY_IN_FD DOTFILES_TTY_OUTPUT
	source "$REPO_DIR/scripts/lib/shared/tui/tty.sh"
	"$@"
)

test_a_secret_read_shows_a_star_per_character() (
	# Silent input left the operator unable to tell a stalled prompt from a
	# typed one, so a secret echoes one '*' per character and erases on
	# backspace -- without the value itself ever reaching the transcript.
	local out="$TEST_HARNESS_ROOT/secret.out"
	_show() {
		local value=''
		read_tty_secret value '  Passphrase: ' || return 1
		printf 'value=%s\n' "$value"
	}
	local result
	result="$(_with_fake_terminal $'abcd\177\n' "$out" _show)" || return 1
	[[ "$result" == 'value=abc' ]] || return 1
	[[ "$(<"$out")" == *'  Passphrase: ***'* ]] || return 1
	# The secret itself must never appear on the terminal transcript.
	! grep -Fq 'abc' "$out"
)

test_a_mismatched_passphrase_is_asked_again() (
	local machine="$TEST_HARNESS_ROOT/mismatch"
	mkdir -p -- "$machine/home"
	local out="$machine/prompt.out"
	_ask() {
		# Exported, not prefixed: a prefix assignment covers only `source`, and
		# prompt_ssh_passphrase would then read the harness's HOME.
		export HOME="$machine/home"
		DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/scripts/install.sh"
		prompt_ssh_passphrase
		printf 'collected=%s\n' "$SETUP_SSH_PASSPHRASE"
	}
	local result
	result="$(_with_fake_terminal $'abc\nxyz\nqq\nqq\n' "$out" _ask 2>&1)" || return 1
	[[ "$result" == *'did not match'* ]] || return 1
	[[ "$result" == *$'collected=qq' ]] || return 1
)

test_an_existing_key_is_not_asked_about() (
	# Nothing will be generated, so there is nothing to ask.
	local machine="$TEST_HARNESS_ROOT/existing"
	mkdir -p -- "$machine/home/.ssh"
	: >"$machine/home/.ssh/id_ed25519"
	local out="$machine/prompt.out"
	_ask() {
		# Exported, not prefixed: a prefix assignment covers only `source`, and
		# prompt_ssh_passphrase would then read the harness's HOME.
		export HOME="$machine/home"
		DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/scripts/install.sh"
		prompt_ssh_passphrase
		printf 'collected=[%s]\n' "$SETUP_SSH_PASSPHRASE"
	}
	local result
	result="$(_with_fake_terminal '' "$out" _ask 2>&1)" || return 1
	[[ "$result" == *'collected=[]'* ]] || return 1
	[[ "$result" != *'Passphrase'* ]] || return 1
	[[ ! -s "$out" ]]
)

expect_success 'a secret read shows a star per character' test_a_secret_read_shows_a_star_per_character
expect_success 'a mismatched passphrase is asked again' test_a_mismatched_passphrase_is_asked_again
expect_success 'an existing key is not asked about' test_an_existing_key_is_not_asked_about
expect_success 'generation never waits for input' test_generation_never_waits_for_input
expect_success 'no collected passphrase says the key is unprotected' test_no_collected_passphrase_says_the_key_is_unprotected

test_harness_cleanup
finish_tests
