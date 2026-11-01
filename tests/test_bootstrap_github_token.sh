#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Runtime sources and command doubles.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
test_harness_protect_original_path '.config/agentbot/github.env'
BOOTSTRAP_SOURCE_ONLY=1 source "$REPO_DIR/bootstrap.sh"
SHARED_DIR="$DOTFILES_SHARED_ROOT"
source "$DOTFILES_SHARED_LIB/github_token.sh"

prepare_token_fixture() {
	unset GITHUB_TOKEN
	rm -rf -- "$XDG_CONFIG_HOME/agentbot"
	export TEST_CANARY_SECRET='bootstrap_test_token_01234567890123456789'
	export GITHUB_TOKEN_TTY_INPUT="$TEST_HARNESS_ROOT/token.input"
	export GITHUB_TOKEN_TTY_OUTPUT="$TEST_HARNESS_ROOT/token.output"
	export GITHUB_TOKEN_TTY_COLS=80
	export TEST_TOKEN_LOG="$TEST_HARNESS_ROOT/token.calls"
	: >"$GITHUB_TOKEN_TTY_OUTPUT"
	: >"$TEST_TOKEN_LOG"
	rm -f -- "$TEST_FAKE_BIN/curl"
	cat >"$TEST_FAKE_BIN/curl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
config="$(cat)"
printf 'argv:%s\n' "$*" >>"$TEST_TOKEN_LOG"
if [[ "$config" == *"Authorization: Bearer ${TEST_CANARY_SECRET}"* ]]; then
    printf 'authenticated\n' >>"$TEST_TOKEN_LOG"
else
    printf 'unauthenticated\n' >>"$TEST_TOKEN_LOG"
fi
headers='' output='' verify=0
while (($#)); do
    case "$1" in
        --dump-header) headers="$2"; shift ;;
        --output|-o) output="$2"; shift ;;
        --write-out) verify=1; shift ;;
    esac
    shift
done
if [[ -n "$headers" ]]; then
    printf 'HTTP/2 200\r\nX-OAuth-Scopes: %s\r\n' "${TEST_VERIFY_SCOPES:-}" >"$headers"
fi
if ((verify)); then
    printf '200'
elif [[ -n "$output" ]]; then
    printf '{}\n' >"$output"
fi
FAKE
	chmod +x "$TEST_FAKE_BIN/curl"
	interactive() { return 0; }
}

test_new_token_authenticates_the_first_install_in_the_same_run() (
	prepare_token_fixture
	printf 's\n%s\ny\nq\n' "$TEST_CANARY_SECRET" >"$GITHUB_TOKEN_TTY_INPUT"
	local output="$TEST_HARNESS_ROOT/bootstrap.output"
	prepare_github_token >"$output" 2>&1 || return 1
	local stored=''
	github_token_read stored
	[[ "$stored" == "$TEST_CANARY_SECRET" ]] || return 1
	[[ "$(stat -c %a "$(github_token_file)")" == 600 ]] || return 1
	[[ "$(stat -c %a "$(dirname -- "$(github_token_file)")")" == 700 ]] || return 1
	# Saved state, rather than an exported variable in this parent, must be
	# enough for a newly started installer to authenticate its first API call.
	[[ -z "${GITHUB_TOKEN:-}" ]] || return 1
	export TEST_SHARED_LIB="$DOTFILES_SHARED_LIB" TEST_DOTFILES_SOURCE="$REPO_DIR"
	DOTFILES_DIR="$TEST_HARNESS_ROOT/fresh-dotfiles"
	mkdir -p "$DOTFILES_DIR/bin/bin"
	cat >"$DOTFILES_DIR/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
source "$TEST_SHARED_LIB/github_token.sh"
source "$TEST_DOTFILES_SOURCE/scripts/lib/github_api.sh"
github_api_release_json jfrog/boost >/dev/null
printf 'download-finished\n' >>"$TEST_TOKEN_LOG"
INSTALL
	cp -- "$DOTFILES_DIR/install.sh" "$DOTFILES_DIR/bin/bin/dotfiles"
	chmod +x "$DOTFILES_DIR/install.sh" "$DOTFILES_DIR/bin/bin/dotfiles"
	run_dotfiles >>"$output" 2>&1 || return 1
	[[ "$(grep -c '^authenticated$' "$TEST_TOKEN_LOG")" -eq 3 ]] || return 1
	[[ "$(grep -c '^download-finished$' "$TEST_TOKEN_LOG")" -eq 2 ]] || return 1
	! grep -Fq "$TEST_CANARY_SECRET" "$output" "$GITHUB_TOKEN_TTY_OUTPUT" "$TEST_TOKEN_LOG"
)

test_existing_tokens_skip_the_setup_screen() (
	prepare_token_fixture
	printf 'q\n' >"$GITHUB_TOKEN_TTY_INPUT"
	github_token_write "$TEST_CANARY_SECRET"
	prepare_github_token >/dev/null 2>&1 || return 1
	[[ ! -s "$GITHUB_TOKEN_TTY_OUTPUT" && ! -s "$TEST_TOKEN_LOG" ]] || return 1
	rm -- "$(github_token_file)"
	export GITHUB_TOKEN="$TEST_CANARY_SECRET"
	prepare_github_token >/dev/null 2>&1 || return 1
	[[ ! -e "$(github_token_file)" && ! -s "$GITHUB_TOKEN_TTY_OUTPUT" && ! -s "$TEST_TOKEN_LOG" ]]
)

test_headless_and_declined_setup_continue_without_a_token() (
	prepare_token_fixture
	interactive() { return 1; }
	local output
	output="$(prepare_github_token 2>&1)" || return 1
	[[ "$output" == *'rate limit'* && ! -e "$(github_token_file)" ]] || return 1
	[[ ! -s "$TEST_TOKEN_LOG" ]] || return 1
	interactive() { return 0; }
	printf 'q\n' >"$GITHUB_TOKEN_TTY_INPUT"
	prepare_github_token >/dev/null 2>&1 || return 1
	[[ ! -e "$(github_token_file)" && ! -s "$TEST_TOKEN_LOG" ]]
)

test_bootstrap_uses_the_existing_read_only_scope_check() (
	prepare_token_fixture
	export TEST_VERIFY_SCOPES=repo
	printf 's\n%s\nq\n' "$TEST_CANARY_SECRET" >"$GITHUB_TOKEN_TTY_INPUT"
	prepare_github_token >/dev/null 2>&1 || return 1
	[[ ! -e "$(github_token_file)" ]] || return 1
	grep -Fq 'This token can write' "$GITHUB_TOKEN_TTY_OUTPUT" || return 1
	! grep -Fq "$TEST_CANARY_SECRET" "$GITHUB_TOKEN_TTY_OUTPUT" "$TEST_TOKEN_LOG"
)

test_main_prepares_the_token_before_either_installer() (
	local events="$TEST_HARNESS_ROOT/order.calls"
	: >"$events"
	preflight() { :; }
	choose_targets() { WANT_DOTFILES=1 WANT_AGENTBOT=1; }
	print_plan() { :; }
	ensure_git() { :; }
	obtain_repo() { printf '%s\n' "$3" >>"$events"; }
	prepare_github_token() { printf 'token\n' >>"$events"; }
	run_dotfiles() { printf 'dotfiles-install\n' >>"$events"; }
	run_agentbot() {
		AGENTBOT_DECLINED=1
		printf 'agentbot-install\n' >>"$events"
	}
	print_summary() { :; }
	start_new_shell() { :; }
	main >/dev/null || return 1
	local shared token dotfiles agentbot
	shared="$(grep -n '^Shared library$' "$events" | cut -d: -f1)"
	token="$(grep -n '^token$' "$events" | cut -d: -f1)"
	dotfiles="$(grep -n '^dotfiles-install$' "$events" | cut -d: -f1)"
	agentbot="$(grep -n '^agentbot-install$' "$events" | cut -d: -f1)"
	[[ -n "$token" && "$shared" -lt "$token" && "$token" -lt "$dotfiles" && "$token" -lt "$agentbot" ]]
)

check 'bootstrap saves a hidden token before the first authenticated install and update' test_new_token_authenticates_the_first_install_in_the_same_run
check 'bootstrap reuses saved and environment tokens without prompting' test_existing_tokens_skip_the_setup_screen
check 'headless and declined token setup continue without authentication' test_headless_and_declined_setup_continue_without_a_token
check 'bootstrap rejects write scopes through the existing token screen' test_bootstrap_uses_the_existing_read_only_scope_check
check 'bootstrap prepares authentication before either installer runs' test_main_prepares_the_token_before_either_installer
finish_tests
