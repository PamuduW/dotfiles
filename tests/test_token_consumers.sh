#!/usr/bin/env bash
# shellcheck disable=SC1091  # Dynamic test/repository sources are resolved at runtime.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/test_harness.sh
source "$TEST_DIR/lib/test_harness.sh"

passed=0
failed=0

pass() { printf 'ok - %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; failed=$((failed + 1)); }
expect_success() {
	local name="$1"
	shift
	if "$@"; then pass "$name"; else fail "$name"; fi
}

install_private_curl_fake() {
	rm -f -- "$TEST_FAKE_BIN/curl"
	# This fake records argv and only the auth-present/auth-absent fact. It never
	# records the private config stream or opens a socket.
	cat >"$TEST_FAKE_BIN/curl" <<'FAKE'
#!/usr/bin/env bash
set -u
auth=auth-absent
secret=''
output_file=''
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
	if [[ "${args[i]}" == '--config' && "${args[i + 1]:-}" == '-' ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			if [[ "$line" =~ ^header[[:space:]]*=[[:space:]]*\"Authorization:[[:space:]]Bearer[[:space:]]([A-Za-z0-9_]+)\"$ ]]; then
				auth=auth-present
				secret="${BASH_REMATCH[1]}"
			fi
		done
	fi
	if [[ "${args[i]}" == '-o' ]]; then output_file="${args[i + 1]:-}"; fi
done
printf '%s\n' "$auth" >>"${TEST_CURL_AUTH_LOG:?}"
printf 'curl' >>"${TEST_COMMAND_LOG:?}"
for arg in "${args[@]}"; do
	printf '\t%s' "$arg" >>"$TEST_COMMAND_LOG"
	[[ "$arg" == http://* || "$arg" == https://* ]] && printf '%s\n' "$arg" >>"${TEST_URL_LOG:?}"
done
printf '\n' >>"$TEST_COMMAND_LOG"
if [[ -n "${TEST_CURL_PID_FILE:-}" ]]; then printf '%s\n' "$$" >"$TEST_CURL_PID_FILE"; fi
if [[ -n "${TEST_CURL_RELEASE_FILE:-}" ]]; then
	while [[ ! -e "$TEST_CURL_RELEASE_FILE" ]]; do read -r -t 0.05 _ || true; done
fi
if [[ -n "${TEST_CURL_STDERR:-}" ]]; then printf '%s\n' "$TEST_CURL_STDERR" >&2; fi
if [[ -n "${TEST_CURL_STDERR_RAW:-}" ]]; then printf '%s' "$TEST_CURL_STDERR_RAW" >&2; fi
if [[ "${TEST_CURL_ECHO_SECRET:-0}" == 1 && -n "$secret" ]]; then printf 'curl diagnostic: %s\n' "$secret" >&2; fi
if [[ -n "$output_file" ]]; then printf '%s' "${TEST_CURL_STDOUT:-}" >"$output_file"; else printf '%s' "${TEST_CURL_STDOUT:-}"; fi
exit "${TEST_CURL_RC:-0}"
FAKE
	chmod 700 "$TEST_FAKE_BIN/curl"
}

reset_request() {
	test_harness_reset_logs
	: >"$TEST_CURL_AUTH_LOG"
	unset GITHUB_TOKEN TEST_CURL_STDERR TEST_CURL_STDERR_RAW TEST_CURL_ECHO_SECRET TEST_CURL_PID_FILE TEST_CURL_RELEASE_FILE
	TEST_CURL_STDOUT='payload'
	TEST_CURL_RC=0
	export TEST_CURL_STDOUT TEST_CURL_RC
	rm -rf -- "$XDG_CONFIG_HOME/agentbot" "$XDG_CONFIG_HOME/agent_bootstrap"
}

test_anonymous_exact_argv() {
	reset_request
	github_curl -fsSL --retry 2 https://api.github.com/example >/dev/null
	grep -Fqx 'auth-absent' "$TEST_CURL_AUTH_LOG" || return 1
	grep -Fqx $'curl\t-fsSL\t--retry\t2\thttps://api.github.com/example' "$TEST_COMMAND_LOG"
}

test_invalid_saved_states_fall_back() {
	local state warning="$TEST_HARNESS_ROOT/log/token-warning.log"
	for state in malformed invalid wrong-mode; do
		reset_request
		mkdir -p "$XDG_CONFIG_HOME/agentbot"
		chmod 700 "$XDG_CONFIG_HOME/agentbot"
		case "$state" in
		malformed) printf 'OTHER=value\n' >"$XDG_CONFIG_HOME/agentbot/github.env" ;;
		invalid) printf 'GITHUB_TOKEN=short\n' >"$XDG_CONFIG_HOME/agentbot/github.env" ;;
		wrong-mode) printf 'GITHUB_TOKEN=valid_token_1234567890\n' >"$XDG_CONFIG_HOME/agentbot/github.env" ;;
		esac
		chmod 600 "$XDG_CONFIG_HOME/agentbot/github.env"
		[[ "$state" == wrong-mode ]] && chmod 644 "$XDG_CONFIG_HOME/agentbot/github.env"
		: >"$warning"
		github_curl -fsSL https://api.github.com/example >/dev/null 2>"$warning" || return 1
		grep -Fqx 'auth-absent' "$TEST_CURL_AUTH_LOG" || return 1
		grep -q '^Warning: .*continuing anonymously\.$' "$warning" || return 1
		grep -Fqx $'curl\t-fsSL\thttps://api.github.com/example' "$TEST_COMMAND_LOG" || return 1
	done
}

test_environment_token_private_config() {
	reset_request
	GITHUB_TOKEN="runtime_token_$(date +%s%N)"
	export GITHUB_TOKEN
	github_curl -fsSL https://api.github.com/example >/dev/null
	grep -Fqx 'auth-present' "$TEST_CURL_AUTH_LOG" || return 1
	grep -Fqx $'curl\t--config\t-\t-fsSL\thttps://api.github.com/example' "$TEST_COMMAND_LOG" || return 1
	! grep -Fq -- "$GITHUB_TOKEN" "$TEST_COMMAND_LOG" "$TEST_URL_LOG"
}

test_saved_token_is_child_only() {
	reset_request
	mkdir -p "$XDG_CONFIG_HOME/agentbot"
	chmod 700 "$XDG_CONFIG_HOME/agentbot"
	printf 'GITHUB_TOKEN=saved_token_1234567890\n' >"$XDG_CONFIG_HOME/agentbot/github.env"
	chmod 600 "$XDG_CONFIG_HOME/agentbot/github.env"
	github_curl -fsSL https://api.github.com/example >/dev/null
	grep -Fqx 'auth-present' "$TEST_CURL_AUTH_LOG" || return 1
	[[ -z "${GITHUB_TOKEN:-}" ]]
}

test_status_and_error_redaction() {
	local error rc token
	reset_request
	token="runtime_token_$(date +%s%N)"
	GITHUB_TOKEN="$token"
	export GITHUB_TOKEN TEST_CURL_ECHO_SECRET=1 TEST_CURL_RC=42
	set +e
	error="$(github_curl -fsSL https://api.github.com/example 2>&1 >/dev/null)"
	rc=$?
	set -e
	[[ "$rc" -eq 42 ]] || return 1
	[[ "$error" == 'curl diagnostic: [redacted]' ]] || return 1
	[[ "$error" != *"$token"* ]]
}

test_no_newline_stderr_is_redacted_byte_exactly() {
	local rc token actual="$TEST_HARNESS_ROOT/log/no-newline.actual" expected="$TEST_HARNESS_ROOT/log/no-newline.expected"
	reset_request
	token="runtime_token_$(date +%s%N)"
	GITHUB_TOKEN="$token"
	export GITHUB_TOKEN TEST_CURL_RC=43
	TEST_CURL_STDERR_RAW="prefix:${token}:suffix"
	export TEST_CURL_STDERR_RAW
	set +e
	github_curl -fsSL https://api.github.com/example >/dev/null 2>"$actual"
	rc=$?
	set -e
	[[ "$rc" -eq 43 ]] || return 1
	printf '%s' 'prefix:[redacted]:suffix' >"$expected"
	cmp -s "$expected" "$actual" || return 1
	[[ -z "$(find "$TMPDIR" -maxdepth 1 -name 'github-curl.stderr.*' -print -quit)" ]]
}

test_canary_absent_from_surfaces() {
	local token output="$TEST_HARNESS_ROOT/log/output.log" snapshot="$TEST_HARNESS_ROOT/log/snapshot.log"
	reset_request
	token="canary_$(date +%s%N)_$RANDOM"
	mkdir -p "$XDG_CONFIG_HOME/agentbot"
	chmod 700 "$XDG_CONFIG_HOME/agentbot"
	printf 'GITHUB_TOKEN=%s\n' "$token" >"$XDG_CONFIG_HOME/agentbot/github.env"
	chmod 600 "$XDG_CONFIG_HOME/agentbot/github.env"
	unset GITHUB_TOKEN
	export TEST_CURL_ECHO_SECRET=1
	github_curl -fsSL https://api.github.com/example >"$output" 2>&1
	[[ -z "${GITHUB_TOKEN:-}" ]] || return 1
	cp "$TEST_COMMAND_LOG" "$snapshot"
	! grep -FR -- "$token" "$output" "$TEST_COMMAND_LOG" "$TEST_URL_LOG" "$snapshot" || return 1
	! git -C "$REPO_DIR" log -p --all 2>/dev/null | grep -Fq -- "$token" || return 1
	! git -C "$REPO_DIR" diff 2>/dev/null | grep -Fq -- "$token"
}

test_proc_cmdline_has_no_secret() {
	local token pid='' cmdline job
	reset_request
	token="proc_token_$(date +%s%N)"
	GITHUB_TOKEN="$token"
	TEST_CURL_PID_FILE="$TEST_HARNESS_ROOT/curl.pid"
	TEST_CURL_RELEASE_FILE="$TEST_HARNESS_ROOT/curl.release"
	export GITHUB_TOKEN TEST_CURL_PID_FILE TEST_CURL_RELEASE_FILE
	github_curl -fsSL https://api.github.com/example >/dev/null 2>&1 &
	job=$!
	for _ in {1..100}; do
		[[ -s "$TEST_CURL_PID_FILE" ]] && { pid="$(<"$TEST_CURL_PID_FILE")"; break; }
		sleep 0.01
	done
	[[ -n "$pid" && -r "/proc/$pid/cmdline" ]] || { touch "$TEST_CURL_RELEASE_FILE"; wait "$job"; return 1; }
	cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
	touch "$TEST_CURL_RELEASE_FILE"
	wait "$job"
	[[ "$cmdline" != *"$token"* && "$cmdline" != *'Authorization:'* ]]
}

assert_sensitive_urls_use_boundary() {
	python3 - "$@" <<'PY'
import pathlib, re, sys
for name in sys.argv[1:]:
    lines = pathlib.Path(name).read_text().splitlines()
    function_starts = [
        index for index, line in enumerate(lines)
        if re.match(r'^\s*[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{', line)
    ]
    for i, line in enumerate(lines):
        if re.search(r'https://(?:api\.github\.com/|github\.com/.*/releases/download/)', line):
            starts = [start for start in function_starts if start <= i]
            if not starts:
                print(f'{name}:{i + 1}: sensitive URL is outside a function', file=sys.stderr)
                raise SystemExit(1)
            start = starts[-1]
            later = [candidate for candidate in function_starts if candidate > start]
            end = later[0] if later else len(lines)
            function_lines = lines[start:end]
            if not any('github_curl' in candidate for candidate in function_lines):
                print(f'{name}:{i + 1}: sensitive function does not call github_curl', file=sys.stderr)
                raise SystemExit(1)
            direct_curl = re.compile(
                r'^\s*(?:(?:if|elif)\s+!\s+)?curl(?:\s|$)'
                r'|[;|&({]\s*curl(?:\s|$)'
            )
            for offset, candidate in enumerate(function_lines, start=start + 1):
                if direct_curl.search(candidate):
                    print(f'{name}:{offset}: direct curl exists in sensitive function', file=sys.stderr)
                    raise SystemExit(1)
PY
}

test_scanner_rejects_nearby_direct_curl_bypass() {
	local fixture="$TEST_HARNESS_ROOT/direct-bypass.sh" error="$TEST_HARNESS_ROOT/log/direct-bypass.err"
	cat >"$fixture" <<'EOF'
bypass() {
	github_curl -fsSL https://example.invalid/harmless
	curl -fsSL https://api.github.com/repos/example/project/releases/latest
}
EOF
	if assert_sensitive_urls_use_boundary "$fixture" 2>"$error"; then
		return 1
	fi
	grep -Fq 'direct curl exists in sensitive function' "$error"
}

test_release_installers_routed() {
	local file="$REPO_DIR/scripts/lib/installers/github_release.sh"
	[[ "$(grep -c 'github_curl -fsSL' "$file")" -eq 4 ]] && assert_sensitive_urls_use_boundary "$file"
}

test_release_installer_standalone_source_stays_anonymous() {
	local url_log="$TEST_HARNESS_ROOT/log/standalone-release-urls.log"
	HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" URL_LOG="$url_log" bash -c '
		set -euo pipefail
		source "$1/scripts/lib/installers/github_release.sh"
		github_latest_release_version() { printf "1.2.3\\n"; }
		_linux_github_arch_suffix() { printf "x86_64\\n"; }
		log_step() { :; }
		log_ok() { :; }
		curl() {
			local output="" arg=""
			while (($#)); do
				arg="$1"; shift
				[[ "$arg" == -o ]] && { output="$1"; shift; }
			done
			printf "%s\\n" "$arg" >>"$URL_LOG"
			[[ -z "$output" ]] || : >"$output"
		}
		sha256sum() { return 1; }
		install_lazygit_from_github >/dev/null 2>&1 || :
	' _ "$REPO_DIR" || return 1
	grep -Fqx 'https://github.com/jesseduffield/lazygit/releases/download/v1.2.3/lazygit_1.2.3_linux_x86_64.tar.gz' "$url_log"
}

test_fonts_and_asdf_routed() {
	local fonts="$REPO_DIR/scripts/lib/installers/fonts.sh" cli="$REPO_DIR/scripts/lib/installers/cli_tools.sh"
	[[ "$(grep -c 'github_curl -fsSL' "$fonts")" -eq 1 ]] || return 1
	[[ "$(grep -c 'github_curl -fsSL' "$cli")" -eq 1 ]] || return 1
	assert_sensitive_urls_use_boundary "$fonts" "$cli"
}

test_global_dotfiles_routed() {
	local file="$REPO_DIR/bin/bin/dotfiles"
	[[ "$(grep -c 'github_curl -fsSL' "$file")" -eq 5 ]] || return 1
	# shellcheck disable=SC2016  # The source expression is the literal contract under test.
	grep -Fq 'source "$_GITHUB_TOKEN_LIB"' "$file" || return 1
	assert_sensitive_urls_use_boundary "$file"
}

test_complete_consumer_inventory() {
	local files=(
		"$REPO_DIR/scripts/lib/github_api.sh"
		"$REPO_DIR/scripts/lib/installers/github_release.sh"
		"$REPO_DIR/scripts/lib/installers/fonts.sh"
		"$REPO_DIR/scripts/lib/installers/cli_tools.sh"
		"$REPO_DIR/bin/bin/dotfiles"
	)
	assert_sensitive_urls_use_boundary "${files[@]}" || return 1
	local found
	found="$(rg -l 'https://(api\.github\.com/|github\.com/.*/releases/download/)' "$REPO_DIR/scripts" "$REPO_DIR/bin" | sort)"
	[[ "$found" == "$(printf '%s\n' "${files[@]}" | sort)" ]]
}

test_excluded_downloads_unchanged() {
	local file="$REPO_DIR/scripts/lib/installers/cli_tools.sh"
	grep -Fq 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/' "$file" || return 1
	grep -Fq 'curl -fsSL https://cursor.com/install' "$file" || return 1
	grep -Fq 'curl -fsSL https://claude.ai/install.sh' "$file" || return 1
	grep -Fq 'curl -fsSL https://gh.io/copilot-install' "$file"
}

test_isolation_and_fake_network() {
	[[ "$(command -v curl)" == "$TEST_FAKE_BIN/curl" ]] || return 1
	[[ "$HOME" == "$TEST_HARNESS_ROOT/home" && "$XDG_CONFIG_HOME" == "$TEST_HARNESS_ROOT/xdg" ]] || return 1
	! rg -q $'\t(sudo|stow|git|npx|sibling-install)\t?' "$TEST_COMMAND_LOG"
}

test_harness_init
test_harness_protect_original_path '.config/agent_bootstrap/github.env'
test_harness_protect_original_path '.config/agentbot/github.env'
TEST_CURL_AUTH_LOG="$TEST_HARNESS_ROOT/log/curl-auth.log"
export TEST_CURL_AUTH_LOG
install_private_curl_fake
# shellcheck source=scripts/lib/github_token.sh
source "$REPO_DIR/scripts/lib/github_token.sh"
# shellcheck source=scripts/lib/github_api.sh
source "$REPO_DIR/scripts/lib/github_api.sh"

expect_success 'missing token preserves anonymous argv and sends no auth config' test_anonymous_exact_argv
expect_success 'malformed, invalid, and wrong-mode saved state warn and stay anonymous' test_invalid_saved_states_fall_back
expect_success 'valid environment token uses private curl config only' test_environment_token_private_config
expect_success 'valid saved token is loaded only in the request child' test_saved_token_is_child_only
expect_success 'curl status and diagnostics propagate with defensive redaction' test_status_and_error_redaction
expect_success 'no-newline curl stderr is preserved byte-for-byte except token redaction' test_no_newline_stderr_is_redacted_byte_exactly
expect_success 'runtime canary is absent from output, logs, Git, snapshot, and diff' test_canary_absent_from_surfaces
expect_success 'sampled curl process command line contains no secret or auth value' test_proc_cmdline_has_no_secret
expect_success 'lazygit and lazydocker archives and checksums use the boundary' test_release_installers_routed
expect_success 'standalone release installer sources boundary and stays anonymous without token helper' test_release_installer_standalone_source_stays_anonymous
expect_success 'Monaspace and asdf release archives use the boundary' test_fonts_and_asdf_routed
expect_success 'global dotfiles release downloads use the boundary' test_global_dotfiles_routed
expect_success 'all active GitHub API and release URLs have no direct-curl bypass' test_complete_consumer_inventory
expect_success 'structural scanner rejects a direct curl bypass near github_curl' test_scanner_rejects_nearby_direct_curl_bypass
expect_success 'raw and non-GitHub installer calls remain direct and untouched' test_excluded_downloads_unchanged
expect_success 'tests remain isolated behind the fail-closed curl fake' test_isolation_and_fake_network

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
