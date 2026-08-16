#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2178,SC2313
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/update_test_fixture.sh"

test_downstream_executes_apt_first_and_all_matrix() (
	local events="$TEST_HARNESS_ROOT/downstream.events"
	: >"$events"
	sudo() { printf 'sudo:%s\n' "$*" >>"$events"; }
	npm_available_version() { printf '12.0.2\n'; }
	_run_upgrade_step() {
		printf 'step:%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" >>"$events"
		UPGRADE_STEP_RESULT["$1"]=ok
	}

	_run_update_downstream false >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == 'sudo:apt-get update -qq' ]] || return 1
	grep -Fq 'step:apt packages|' "$events" || return 1
	! grep -Eq 'step:(Node.js \(nvm\)|npm|Go \(asdf\)|Monaspace fonts)\|' "$events" || return 1

	: >"$events"
	_run_update_downstream true >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == 'sudo:apt-get update -qq' ]] || return 1
	grep -Fq 'step:Graphify CLI|' "$events" || return 1
	grep -Fq 'step:Node.js (nvm)|' "$events" || return 1
	grep -Fqx 'step:npm|npm install -g npm@12.0.2 --engine-strict --allow-remote=all|upgrade_npm|12.0.2' "$events" || return 1
	grep -Fq 'step:Go (asdf)|' "$events" || return 1
	grep -Fq 'step:Monaspace fonts|' "$events"
)

test_node_probe_uses_nvm_default_when_shell_path_is_stale() (
	_load_nvm() { :; }
	node() { printf 'v24.16.0\n'; }
	nvm() {
		if [[ "$1 ${2:-}" == 'version default' ]]; then
			printf 'v24.18.0\n'
			return 0
		fi
		return 1
	}

	[[ "$(node_installed_version)" == '24.18.0' ]]
)

test_npm_probe_reports_upgrade_current_and_missing_states() (
	local output npm_mode=upgrade
	_load_nvm() { :; }
	npm() {
		case "$*" in
		--version)
			[[ "$npm_mode" == current ]] && printf '12.0.1\n' || printf '11.16.0\n'
			;;
		'view npm version') printf '12.0.1\n' ;;
		*) return 97 ;;
		esac
	}

	output="$(check_npm || true)"
	[[ "$output" == 'npm|11.16.0|12.0.1|upgrade (--all)' ]] || return 1

	npm_mode=current
	output="$(check_npm || true)"
	[[ "$output" == 'npm|12.0.1|12.0.1|up to date' ]] || return 1

	unset -f npm
	command() {
		[[ "$*" == '-v npm' ]] && return 1
		builtin command "$@"
	}
	output="$(check_npm || true)"
	[[ "$output" == 'npm|not installed|—|skip' ]]
)

test_npm_version_reached_requires_a_safe_equal_or_newer_version() (
	local installed=12.0.2
	npm_installed_version() { printf '%s\n' "$installed"; }

	npm_version_reached 12.0.2 || return 1
	installed=12.1.0
	npm_version_reached 12.0.2 || return 1
	installed=12.0.1
	! npm_version_reached 12.0.2 || return 1
	installed="$NOT_INSTALLED"
	! npm_version_reached 12.0.2 || return 1
	installed=garbage
	! npm_version_reached 12.0.2 || return 1
	! npm_version_reached 'latest;touch /tmp/nope'
)

test_npm_upgrade_accepts_verified_nvm_result() (
	local installed=12.0.1 calls="$TEST_HARNESS_ROOT/npm-nvm-success.calls"
	: >"$calls"
	_load_nvm() { :; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		*)
			printf 'npm:%s\n' "$*" >>"$calls"
			return 97
			;;
		esac
	}
	nvm() {
		printf 'nvm:%s\n' "$*" >>"$calls"
		installed=12.0.2
	}

	upgrade_npm 12.0.2 || return 1
	grep -Fqx 'nvm:install-latest-npm' "$calls" || return 1
	! grep -Fq 'npm:install' "$calls"
)

test_npm_upgrade_falls_back_after_false_nvm_success() (
	local installed=12.0.1 calls="$TEST_HARNESS_ROOT/npm-false-success.calls"
	: >"$calls"
	_load_nvm() { :; }
	nvm() {
		printf 'nvm:%s\n' "$*" >>"$calls"
		return 0
	}
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all')
			printf 'npm:%s\n' "$*" >>"$calls"
			installed=12.0.2
			;;
		*) return 97 ;;
		esac
	}

	upgrade_npm 12.0.2 || return 1
	grep -Fqx 'npm:install -g npm@12.0.2 --engine-strict --allow-remote=all' "$calls"
)

test_npm_upgrade_fallback_can_recover_from_nvm_failure() (
	local installed=12.0.1
	_load_nvm() { :; }
	nvm() { return 23; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') installed=12.0.2 ;;
		*) return 97 ;;
		esac
	}

	upgrade_npm 12.0.2
)

test_npm_upgrade_fails_when_fallback_command_fails() (
	local installed=12.0.1
	_load_nvm() { :; }
	nvm() { return 0; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') return 24 ;;
		*) return 97 ;;
		esac
	}

	if upgrade_npm 12.0.2; then return 1; fi
)

test_npm_upgrade_fails_when_fallback_leaves_old_version() (
	local installed=12.0.1
	_load_nvm() { :; }
	nvm() { return 0; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') return 0 ;;
		*) return 97 ;;
		esac
	}

	if upgrade_npm 12.0.2; then return 1; fi
)

test_npm_upgrade_skips_commands_when_already_current() (
	local installed=12.0.2 calls="$TEST_HARNESS_ROOT/npm-current.calls"
	: >"$calls"
	_load_nvm() { :; }
	nvm() {
		printf 'nvm:%s\n' "$*" >>"$calls"
		return 97
	}
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		*)
			printf 'npm:%s\n' "$*" >>"$calls"
			return 97
			;;
		esac
	}

	upgrade_npm 12.0.2 || return 1
	[[ ! -s "$calls" ]]
)

test_npm_failed_postcheck_sets_retryable_failed_step() (
	local installed=12.0.1 output="$TEST_HARNESS_ROOT/npm-failed-step.output"
	_load_nvm() { :; }
	nvm() { return 0; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') return 0 ;;
		*) return 97 ;;
		esac
	}
	C_BOLD='' C_YELLOW='' C_RED=$'\033[31m' C_RESET=$'\033[0m'

	_run_upgrade_step 'npm' 'npm install -g npm@12.0.2 --engine-strict --allow-remote=all' upgrade_npm 12.0.2 >"$output" 2>&1
	[[ "${UPGRADE_STEP_RESULT[npm]}" == failed ]] || return 1
	grep -Fq 'retry manually: npm install -g npm@12.0.2 --engine-strict --allow-remote=all' "$output"
)

test_unverifiable_cli_probes_label_latest_unchecked() (
	local output
	agent() { [[ "$1" == --version ]] && printf '2026.07.23-e383d2b\n'; }
	claude() { [[ "$1" == --version ]] && printf '2.1.220 (Claude Code)\n'; }
	copilot() { [[ "$1" == --version ]] && printf 'GitHub Copilot CLI 1.0.75.\n'; }

	output="$(check_cursor_cli || true)"
	[[ "$output" == 'Cursor CLI|2026.07.23-e383d2b|—|latest unchecked' ]] || return 1
	output="$(check_claude_cli || true)"
	[[ "$output" == 'Claude CLI|2.1.220 (Claude Code)|—|latest unchecked' ]] || return 1
	output="$(check_copilot_cli || true)"
	[[ "$output" == 'Copilot CLI|GitHub Copilot CLI 1.0.75.|—|latest unchecked' ]]
)

test_graphify_probe_reports_uv_owned_and_external_states() (
	local output
	graphify() { [[ "$1" == --version ]] && printf 'graphify 1.2.3\n'; }
	uv() {
		case "$*" in
		'tool list') printf '%s\n' 'graphifyy v1.2.3' ;;
		*) return 97 ;;
		esac
	}
	output="$(check_graphify_cli || true)"
	[[ "$output" == 'Graphify CLI|graphify 1.2.3|—|latest unchecked' ]] || return 1

	uv() {
		[[ "$*" == 'tool list' ]] && printf '%s\n' 'other-tool v1.0.0'
	}
	output="$(check_graphify_cli || true)"
	[[ "$output" == 'Graphify CLI|graphify 1.2.3|—|externally managed' ]]
)

test_graphify_probe_skips_when_not_installed() (
	local output
	graphify_command() { return 1; }
	output="$(check_graphify_cli || true)"
	[[ "$output" == 'Graphify CLI|not installed|—|skip' ]]
)

test_graphify_upgrade_uses_uv_tool_upgrade() (
	local output calls="$TEST_HARNESS_ROOT/graphify-upgrade.calls"
	: >"$calls"
	graphify() { [[ "$1" == --version ]] && printf 'graphify 1.2.3\n'; }
	agentbot() {
		printf 'agentbot:%s\n' "$*" >>"$calls"
		return 97
	}
	uv() {
		printf 'uv:%s\n' "$*" >>"$calls"
		case "$*" in
		'tool list') printf '%s\n' 'graphifyy v1.2.3' ;;
		'tool upgrade graphifyy') return 0 ;;
		*) return 97 ;;
		esac
	}
	output="$(upgrade_graphify_cli)" || return 1
	grep -Fqx 'uv:tool upgrade graphifyy' "$calls" || return 1
	! grep -Fq 'agentbot:' "$calls" || return 1
	grep -Fq "If Agentbot's Graphify integration is enabled, run agentbot graphify setup" <<<"$output" || return 1
	grep -Fq 'or agentbot update to refresh the installed skill.' <<<"$output"
)

test_graphify_upgrade_failure_has_copyable_retry_command() (
	local output calls="$TEST_HARNESS_ROOT/graphify-failure.calls"
	: >"$calls"
	graphify() { [[ "$1" == --version ]] && printf 'graphify 1.2.3\n'; }
	uv() {
		printf 'uv:%s\n' "$*" >>"$calls"
		case "$*" in
		'tool list') printf '%s\n' 'graphifyy v1.2.3' ;;
		'tool upgrade graphifyy') return 23 ;;
		*) return 97 ;;
		esac
	}
	C_RED=$'\033[31m' C_RESET=$'\033[0m'
	output="$(_run_upgrade_step 'Graphify CLI' 'uv tool upgrade graphifyy' upgrade_graphify_cli 2>&1)"
	grep -Fqx 'uv:tool upgrade graphifyy' "$calls"
	grep -Fq 'retry manually: uv tool upgrade graphifyy' <<<"$output" || return 1
	! grep -Fq "Agentbot's Graphify integration" <<<"$output"
)

test_upgrade_step_marks_failures_in_red_with_retry_command() (
	local output
	C_BOLD='' C_YELLOW='' C_RED=$'\033[31m' C_RESET=$'\033[0m'
	_failing_probe() { return 7; }

	output="$(_run_upgrade_step 'probe' 'probe --retry' _failing_probe 2>&1)"
	grep -Fq $'\033[31m>> FAILED (exit 7) — retry manually: probe --retry <<\033[0m' <<<"$output"
)

test_upgrade_step_omits_failure_marker_after_success() (
	local output
	C_BOLD='' C_YELLOW='' C_RED=$'\033[31m' C_RESET=$'\033[0m'
	_successful_probe() { printf 'probe ok\n'; }

	output="$(_run_upgrade_step 'probe' 'probe --retry' _successful_probe 2>&1)"
	grep -Fq 'probe ok' <<<"$output" || return 1
	! grep -Fq '>> FAILED' <<<"$output"
)

test_node_upgrade_stops_when_nvm_install_fails() (
	local calls="$TEST_HARNESS_ROOT/node-upgrade.calls"
	: >"$calls"
	_load_nvm() { :; }
	nvm() {
		printf 'nvm:%s\n' "$*" >>"$calls"
		[[ "$1" != install ]]
	}

	if upgrade_node; then
		return 1
	fi
	grep -Fqx 'nvm:install --lts' "$calls" || return 1
	! grep -Fq 'nvm:alias' "$calls"
)

test_go_upgrade_stops_when_asdf_install_fails() (
	local calls="$TEST_HARNESS_ROOT/go-upgrade.calls"
	: >"$calls"
	asdf() {
		printf 'asdf:%s\n' "$*" >>"$calls"
		[[ "$1" != install ]]
	}

	if upgrade_go; then
		return 1
	fi
	grep -Fqx 'asdf:install golang latest' "$calls" || return 1
	! grep -Eq '^asdf:(set|reshim)' "$calls"
)

test_cursor_update_falls_back_to_official_installer() (
	local calls="$TEST_HARNESS_ROOT/cursor-update.calls" output="$TEST_HARNESS_ROOT/cursor-update.output"
	: >"$calls"
	C_RED=$'\033[31m' C_RESET=$'\033[0m'
	export C_RED C_RESET
	agent() {
		printf 'agent:%s\n' "$*" >>"$calls"
		return 7
	}
	curl() {
		printf 'curl:%s\n' "$*" >>"$calls"
		local output_file='' previous='' argument
		for argument in "$@"; do
			[[ "$previous" == -o ]] && output_file="$argument"
			previous="$argument"
		done
		printf '%s\n' 'printf "official-installer\n"' >"$output_file"
	}

	if ! upgrade_cursor_cli >"$output" 2>&1; then
		return 1
	fi
	grep -Fqx 'agent:update' "$calls" || return 1
	grep -Fq 'curl:-fsSL --proto =https --tlsv1.2 -o ' "$calls" || return 1
	grep -Fq ' https://cursor.com/install' "$calls" || return 1
	grep -Fqx 'official-installer' "$output" || return 1
	grep -Fq $'\033[31m>> FAILED (exit 7) — retry manually: agent update <<\033[0m' "$output"
)

test_copilot_update_uses_discovered_local_executable() (
	local local_bin="$HOME/.local/bin" calls="$TEST_HARNESS_ROOT/copilot-update.calls"
	mkdir -p "$local_bin"
	: >"$calls"
	cat >"$local_bin/copilot" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$calls'
EOF
	chmod +x "$local_bin/copilot"

	PATH="$TEST_FAKE_BIN:/usr/bin:/bin" upgrade_copilot_cli
	[[ "$(<"$calls")" == update ]]
)

test_apt_report_probe_uses_cached_indices_without_sudo() (
	local count sudo_calls=0
	apt-get() { printf '%s\n' 'Inst cached-package'; }
	sudo() {
		sudo_calls=$((sudo_calls + 1))
		return 99
	}
	count="$(apt_upgradable_count)"
	[[ "$count" -eq 1 ]] || return 1
	[[ "$sudo_calls" -eq 0 ]]
)

test_apt_report_does_not_claim_cached_indices_are_current() (
	local output
	apt_upgradable_count() { printf '0\n'; }
	output="$(check_apt || true)"
	[[ "$output" == 'apt packages|system packages|none (cached)|refresh on apply' ]]
)

expect_success 'downstream execution runs apt refresh first and honors --all' test_downstream_executes_apt_first_and_all_matrix
expect_success 'Node.js probe follows nvm default instead of a stale shell PATH' test_node_probe_uses_nvm_default_when_shell_path_is_stale
expect_success 'npm probe reports upgrade current and missing states' test_npm_probe_reports_upgrade_current_and_missing_states
expect_success 'npm version verification accepts only safe equal or newer versions' test_npm_version_reached_requires_a_safe_equal_or_newer_version
expect_success 'npm upgrade accepts a verified NVM result' test_npm_upgrade_accepts_verified_nvm_result
expect_success 'npm upgrade uses the exact fallback after false NVM success' test_npm_upgrade_falls_back_after_false_nvm_success
expect_success 'npm fallback can recover from NVM failure' test_npm_upgrade_fallback_can_recover_from_nvm_failure
expect_success 'npm upgrade fails when the fallback command fails' test_npm_upgrade_fails_when_fallback_command_fails
expect_success 'npm upgrade fails when fallback leaves the old version installed' test_npm_upgrade_fails_when_fallback_leaves_old_version
expect_success 'npm upgrade skips NVM and npm install when already current' test_npm_upgrade_skips_commands_when_already_current
expect_success 'npm failed post-check records a copyable failed step' test_npm_failed_postcheck_sets_retryable_failed_step
expect_success 'unverifiable CLI probes label latest freshness unchecked' test_unverifiable_cli_probes_label_latest_unchecked
expect_success 'Graphify update probe distinguishes uv-owned and external installs' test_graphify_probe_reports_uv_owned_and_external_states
expect_success 'Graphify update probe skips an absent CLI' test_graphify_probe_skips_when_not_installed
expect_success 'Graphify update uses uv tool upgrade' test_graphify_upgrade_uses_uv_tool_upgrade
expect_success 'Graphify update failures include a copyable retry command' test_graphify_upgrade_failure_has_copyable_retry_command
expect_success 'upgrade step marks failures in red with retry command' test_upgrade_step_marks_failures_in_red_with_retry_command
expect_success 'upgrade step omits failure marker after success' test_upgrade_step_omits_failure_marker_after_success
expect_success 'Node.js upgrade stops when nvm install fails' test_node_upgrade_stops_when_nvm_install_fails
expect_success 'Go upgrade stops when asdf install fails' test_go_upgrade_stops_when_asdf_install_fails
expect_success 'Cursor update falls back to the official installer after agent update failure' test_cursor_update_falls_back_to_official_installer
expect_success 'Copilot update invokes the executable discovered in the local vendor bin' test_copilot_update_uses_discovered_local_executable
expect_success 'pre-confirmation apt report probing never invokes sudo' test_apt_report_probe_uses_cached_indices_without_sudo
expect_success 'apt preview labels cached metadata without claiming it is current' test_apt_report_does_not_claim_cached_indices_are_current

finish_tests
