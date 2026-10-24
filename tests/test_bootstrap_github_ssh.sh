#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
PATH="$ORIGINAL_PATH"
export PATH
test_harness_report_init
# shellcheck source=bootstrap.sh
BOOTSTRAP_SOURCE_ONLY=1 source "$TEST_DIR/../bootstrap.sh"

FIXTURE_KEY="$TEST_HARNESS_ROOT/fixture"
/usr/bin/ssh-keygen -q -t ed25519 -N '' -C fixture -f "$FIXTURE_KEY"

setup_ssh_machine() {
	HOME="$TEST_HARNESS_ROOT/$1"
	mkdir -p "$HOME"
	SSH_LOG="$HOME/commands"
	: >"$SSH_LOG"
	SSH_MODE=ready
	SSH_AGENT_MODE=ready
	SSH_CONFIG_IDENTITY=''
	MEMORY_SSH_IDENTITY=''
	BOOTSTRAP_ANSWERS=''
	_answer_index=0
	unset SSH_AUTH_SOCK SSH_AGENT_PID
}

ssh() {
	printf 'ssh %s\n' "$*" >>"$SSH_LOG"
	if [[ "$1" == -G ]]; then
		[[ -z "$SSH_CONFIG_IDENTITY" ]] || printf 'identityfile %s\n' "$SSH_CONFIG_IDENTITY"
		return 0
	fi
	if [[ "$SSH_MODE" == network ]]; then
		printf 'ssh: Could not resolve hostname github.com\n' >&2
		return 255
	fi
	if [[ "$SSH_MODE" == ready || -e "$HOME/registered" || ("$SSH_MODE" == locked && -e "$HOME/loaded") ]]; then
		printf "Hi fixture! You've successfully authenticated, but GitHub does not provide shell access.\n" >&2
		return 1
	fi
	printf 'git@github.com: Permission denied (publickey).\n' >&2
	return 255
}

ssh-agent() {
	printf 'ssh-agent %s\n' "$*" >>"$SSH_LOG"
	printf 'SSH_AUTH_SOCK=%s/agent.sock; export SSH_AUTH_SOCK;\n' "$HOME"
	printf 'SSH_AGENT_PID=123; export SSH_AGENT_PID;\n'
}

ssh-add() {
	printf 'ssh-add %s\n' "$*" >>"$SSH_LOG"
	if [[ "$1" == -l ]]; then
		[[ "$SSH_AGENT_MODE" == ready ]] && return 0
		[[ -n "${SSH_AUTH_SOCK:-}" ]] && return 1
		return 2
	fi
	if [[ "$1" == -L ]]; then
		return 1
	fi
	touch "$HOME/loaded"
}

memory_ssh_terminal() {
	printf 'terminal %s\n' "$*" >>"$SSH_LOG"
	case "$1" in
	ssh-keygen)
		if [[ "$2" == -y ]]; then
			/usr/bin/ssh-keygen "${@:2}"
			return $?
		fi
		local key='' arg
		shift
		while (($#)); do
			arg="$1"
			shift
			if [[ "$arg" == -f ]]; then
				key="$1"
				shift
			fi
		done
		[[ ! -e "$key" ]] || return 1
		cp "$FIXTURE_KEY" "$key"
		cp "$FIXTURE_KEY.pub" "$key.pub"
		;;
	ssh-add) ssh-add "${@:2}" ;;
	*) "$@" ;;
	esac
}

test_first_connection_trusts_published_host_before_authentication() (
	setup_ssh_machine first
	prepare_memory_github_ssh >/dev/null || return 1
	/usr/bin/ssh-keygen -F github.com -f "$HOME/.ssh/known_hosts" >/dev/null || return 1
	local fingerprint
	fingerprint="$(/usr/bin/ssh-keygen -lf "$HOME/.ssh/known_hosts")"
	[[ "$fingerprint" == *'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU'* ]] || return 1
	grep -q 'StrictHostKeyChecking=yes' "$SSH_LOG" || return 1
	! grep -Eq 'ssh-agent|ssh-add|terminal' "$SSH_LOG"
)

test_declining_host_trust_does_not_connect_or_create_keys() (
	setup_ssh_machine decline
	BOOTSTRAP_ANSWERS=n
	! prepare_memory_github_ssh >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.ssh/known_hosts" ]] || return 1
	[[ ! -s "$SSH_LOG" ]]
)

test_new_key_starts_agent_and_prints_only_the_public_key() (
	setup_ssh_machine new
	SSH_MODE=denied
	SSH_AGENT_MODE=missing
	# Trust host, create key, accept filename, then leave registration pending.
	BOOTSTRAP_ANSWERS=$'y\ny\n\nskip'
	local output
	output="$(prepare_memory_github_ssh 2>&1)" && return 1
	[[ -f "$HOME/.ssh/id_ed25519" ]] || return 1
	grep -q '^terminal ssh-keygen -t ed25519 ' "$SSH_LOG" || return 1
	grep -q '^ssh-agent -s' "$SSH_LOG" || return 1
	grep -q "^ssh-add $HOME/.ssh/id_ed25519$" "$SSH_LOG" || return 1
	[[ "$output" == *"$(cut -d' ' -f1,2 "$FIXTURE_KEY.pub")"* ]] || return 1
	[[ "$output" != *'PRIVATE KEY'* ]]
)

test_reusing_a_key_preserves_it_and_retries_after_registration() (
	setup_ssh_machine reuse
	mkdir -p "$HOME/.ssh"
	cp "$FIXTURE_KEY" "$HOME/.ssh/id_ed25519"
	cp "$FIXTURE_KEY.pub" "$HOME/.ssh/id_ed25519.pub"
	SSH_MODE=denied
	ask() {
		ANSWER="$2"
		[[ "$1" != *'After adding the public key'* ]] || touch "$HOME/registered"
	}
	local output
	output="$(prepare_memory_github_ssh 2>&1)" || return 1
	cmp -s "$FIXTURE_KEY" "$HOME/.ssh/id_ed25519" || return 1
	! grep -q 'terminal ssh-keygen -t' "$SSH_LOG" || return 1
	[[ "$output" == *"$(cut -d' ' -f1,2 "$FIXTURE_KEY.pub")"* ]] || return 1
	[[ "$(grep -c '^ssh -T ' "$SSH_LOG")" -eq 3 ]]
)

test_network_failure_and_existing_host_entries_are_preserved() (
	setup_ssh_machine network
	mkdir -p "$HOME/.ssh"
	printf 'github.com %s\n' "$(cat "$FIXTURE_KEY.pub")" >"$HOME/.ssh/known_hosts"
	cp "$HOME/.ssh/known_hosts" "$HOME/known.before"
	SSH_MODE=network
	! prepare_memory_github_ssh >/dev/null 2>&1 || return 1
	cmp -s "$HOME/known.before" "$HOME/.ssh/known_hosts" || return 1
	! grep -Eq 'ssh-agent|terminal' "$SSH_LOG"
)

test_a_registered_key_only_needs_loading_into_the_agent() (
	setup_ssh_machine locked
	mkdir -p "$HOME/.ssh"
	cp "$FIXTURE_KEY" "$HOME/.ssh/id_ed25519"
	cp "$FIXTURE_KEY.pub" "$HOME/.ssh/id_ed25519.pub"
	SSH_MODE=locked
	BOOTSTRAP_ANSWERS=$'y\n1\n\nskip'
	prepare_memory_github_ssh >/dev/null || return 1
	[[ -f "$HOME/loaded" ]] || return 1
	[[ "$(grep -c '^ssh -T ' "$SSH_LOG")" -eq 2 ]]
)

test_configured_custom_keys_are_discovered_and_selected() (
	setup_ssh_machine configured
	mkdir -p "$HOME/keys"
	SSH_CONFIG_IDENTITY="$HOME/keys/custom identity"
	cp "$FIXTURE_KEY" "$SSH_CONFIG_IDENTITY"
	SSH_MODE=locked
	BOOTSTRAP_ANSWERS=$'y\n1\n\nskip'
	prepare_memory_github_ssh >/dev/null || return 1
	[[ "$MEMORY_SSH_IDENTITY" == "$SSH_CONFIG_IDENTITY" ]] || return 1
	grep -Fq -- "-i $SSH_CONFIG_IDENTITY" "$SSH_LOG" || return 1
	grep -q 'IdentitiesOnly=yes' "$SSH_LOG"
)

test_failed_public_key_derivation_does_not_poison_a_retry() (
	setup_ssh_machine derive
	local key="$HOME/custom"
	cp "$FIXTURE_KEY" "$key"
	memory_ssh_terminal() { return 1; }
	! memory_ssh_public_key "$key" >/dev/null 2>&1 || return 1
	[[ ! -e "$key.pub" ]] || return 1
	memory_ssh_terminal() { "$@"; }
	local output
	output="$(memory_ssh_public_key "$key")" || return 1
	[[ "$output" == *"$(cut -d' ' -f1,2 "$FIXTURE_KEY.pub")"* ]]
)

test_the_clone_handoff_preserves_the_selected_key_with_shell_characters() (
	setup_ssh_machine transport
	AGENTBOT_DIR="$HOME/agentbot"
	mkdir -p "$AGENTBOT_DIR/bin" "$HOME/bin"
	# Spaces, a quote, and a literal dollar sign belong to the filename.
	printf -v EXPECTED_SSH_KEY '%s/key \047 with \044dollar' "$HOME"
	SSH_ARG_LOG="$HOME/ssh-args"
	SSH_AUTH_SOCK="$HOME/agent socket"
	export EXPECTED_SSH_KEY SSH_ARG_LOG SSH_AUTH_SOCK
	cat >"$AGENTBOT_DIR/bin/agentbot" <<'EOF'
#!/bin/sh
[ "$1 $2" != 'memory status' ] || exit 2
while [ "$#" -gt 0 ]; do
  if [ "$1" = --ssh-key ]; then
    [ "$2" = "$EXPECTED_SSH_KEY" ] || exit 1
    printf '%s\n' "$2" >"$SSH_ARG_LOG"
    exit 0
  fi
  shift
done
exit 1
EOF
	chmod +x "$AGENTBOT_DIR/bin/agentbot"
	PATH="$HOME/bin:$ORIGINAL_PATH"
	prepare_memory_github_ssh() { MEMORY_SSH_IDENTITY="$EXPECTED_SSH_KEY"; }
	BOOTSTRAP_ANSWERS=$'git@github.com:fixture/vault.git\n'
	setup_memory_vault >/dev/null || return 1
	[[ -f "$SSH_ARG_LOG" ]] || return 1
	grep -Fxq -- "$EXPECTED_SSH_KEY" "$SSH_ARG_LOG"
)

test_creating_another_key_does_not_overwrite_the_existing_one() (
	setup_ssh_machine another
	mkdir -p "$HOME/.ssh"
	cp "$FIXTURE_KEY" "$HOME/.ssh/id_ed25519"
	cp "$FIXTURE_KEY.pub" "$HOME/.ssh/id_ed25519.pub"
	SSH_MODE=denied
	BOOTSTRAP_ANSWERS=$'y\n2\n\nskip'
	! prepare_memory_github_ssh >/dev/null 2>&1 || return 1
	cmp -s "$FIXTURE_KEY" "$HOME/.ssh/id_ed25519" || return 1
	[[ -f "$HOME/.ssh/id_ed25519_github_1" && -f "$HOME/.ssh/id_ed25519_github_1.pub" ]]
)

test_a_private_key_in_a_pub_file_is_never_printed() (
	setup_ssh_machine private-pub
	cp "$FIXTURE_KEY" "$HOME/not-public.pub"
	local output
	output="$(memory_ssh_public_key "$HOME/not-public" 2>&1)" && return 1
	[[ -z "$output" ]]
)

test_a_symlinked_host_file_is_not_modified() (
	setup_ssh_machine symlink
	mkdir -p "$HOME/.ssh"
	printf 'preserve\n' >"$HOME/elsewhere"
	ln -s "$HOME/elsewhere" "$HOME/.ssh/known_hosts"
	! prepare_memory_github_ssh >/dev/null 2>&1 || return 1
	[[ "$(cat "$HOME/elsewhere")" == preserve ]] || return 1
	[[ ! -s "$SSH_LOG" ]]
)

expect_success 'first SSH connection trusts the published GitHub host key before authentication' test_first_connection_trusts_published_host_before_authentication
expect_success 'declining host trust leaves SSH untouched' test_declining_host_trust_does_not_connect_or_create_keys
expect_success 'new SSH keys use an agent and expose only their public key' test_new_key_starts_agent_and_prints_only_the_public_key
expect_success 'existing SSH keys are preserved and can be retried after registration' test_reusing_a_key_preserves_it_and_retries_after_registration
expect_success 'network failures preserve existing host keys and do not create identities' test_network_failure_and_existing_host_entries_are_preserved
expect_success 'a registered key can be unlocked without another GitHub registration' test_a_registered_key_only_needs_loading_into_the_agent
expect_success 'creating another SSH key preserves the existing identity' test_creating_another_key_does_not_overwrite_the_existing_one
expect_success 'a private key mislabeled as a public key is never printed' test_a_private_key_in_a_pub_file_is_never_printed
expect_success 'a symlinked host file is left untouched' test_a_symlinked_host_file_is_not_modified
expect_success 'configured custom identities are discovered and selected for SSH' test_configured_custom_keys_are_discovered_and_selected
expect_success 'failed public-key derivation leaves a usable retry' test_failed_public_key_derivation_does_not_poison_a_retry
expect_success 'the clone handoff preserves the selected identity and shell characters' test_the_clone_handoff_preserves_the_selected_key_with_shell_characters
finish_tests
