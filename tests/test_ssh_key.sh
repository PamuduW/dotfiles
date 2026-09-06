#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# SSH key generation, and specifically where its passphrase prompt comes from.
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
		printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/$stub"
		chmod +x -- "$bin/$stub"
	done
}

_run_generate_ssh_key() (
	local home="$1" tty_input="$2" bin="$3"
	export HOME="$home" KEYGEN_ARGS="$home/keygen-args" PATH="$bin:$PATH"
	export SETUP_GIT_EMAIL='test@example.com'
	export DOTFILES_TTY_INPUT="$tty_input"
	# The adapter decides output independently of input; keep it off the real
	# terminal so the suite stays quiet.
	export DOTFILES_TTY_OUTPUT="$home/tty-out"
	source "$REPO_DIR/scripts/lib/shared/tui/tty.sh"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	source "$REPO_DIR/scripts/lib/installers/stow.sh"
	generate_ssh_key
)

test_a_passphrase_is_asked_for_on_the_terminal() (
	# Break caught: ssh-keygen inherited stdin, which under `curl ... | bash` is
	# the pipe. It fell back to ssh-askpass, which is not installed, so the run
	# printed "You'll be prompted for a passphrase", never prompted, and wrote
	# an unprotected key.
	local machine="$TEST_HARNESS_ROOT/asked" bin="$TEST_HARNESS_ROOT/asked/bin"
	mkdir -p -- "$machine/home"
	_install_fake_keygen "$bin"
	local fake_tty="$machine/fake-tty"
	printf 'from-the-terminal\n' >"$fake_tty"

	local output
	output="$(_run_generate_ssh_key "$machine/home" "$fake_tty" "$bin" </dev/null 2>&1)" || return 1
	[[ "$output" == *"You'll be prompted for a passphrase"* ]] || return 1
	# No -N: the operator's answer decides the passphrase, not the script.
	! grep -q -- '-N' "$machine/home/keygen-args" || return 1
	# And the answer is read from the terminal, not from whatever stdin holds:
	# the run was given /dev/null on stdin, so only the redirect can deliver this.
	grep -Fqx 'stdin:from-the-terminal' "$machine/home/keygen-args"
)

test_no_terminal_says_the_key_has_no_passphrase() (
	# With nothing to ask on, the honest move is an unprotected key and a line
	# saying so -- not a promise of a prompt that cannot arrive.
	local machine="$TEST_HARNESS_ROOT/unasked" bin="$TEST_HARNESS_ROOT/unasked/bin"
	mkdir -p -- "$machine/home"
	_install_fake_keygen "$bin"

	local output
	output="$(_run_generate_ssh_key "$machine/home" "$machine/absent-tty" "$bin" </dev/null 2>&1)" || return 1
	[[ "$output" != *"You'll be prompted"* ]] || return 1
	[[ "$output" == *'without a passphrase'* ]] || return 1
	# -N '' keeps ssh-keygen from reaching for an askpass that is not there.
	grep -q -- "-N" "$machine/home/keygen-args"
)

expect_success 'a passphrase is asked for on the terminal' test_a_passphrase_is_asked_for_on_the_terminal
expect_success 'no terminal says the key has no passphrase' test_no_terminal_says_the_key_has_no_passphrase

test_harness_cleanup
finish_tests
