#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2178,SC2313
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/update_test_fixture.sh"
source "$TEST_DIR/lib/runtime_failure_fixture.sh"

# Status fixtures model already installed commands; adapter suites qualify the
# full npm/Python/Codex layouts separately. Only Boost uses this raw download.
update_tool_catalog_fixture() {
	local fixture_key="$1" target_version="$2" installed_version="$3" ownership="${4:-managed}" root binary
	HOME="$TEST_HARNESS_ROOT/update-$fixture_key-$BASHPID"
	export HOME
	rm -rf -- "$HOME"
	mkdir -p "$HOME/.local/bin" "$HOME/.codex/app-server-daemon"
	CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin"
	export CODEX_HOME CODEX_INSTALL_DIR
	printf '%s\n' '{"updater":{"autoUpdateEnabled":false}}' >"$HOME/.codex/app-server-daemon/settings.json"
	PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
	export PATH
	binary="$(dotfiles_catalog_command_name "$fixture_key")"
	TEST_UPDATE_ARTIFACT="$HOME/artifact"
	TEST_UPDATE_CALLS="$HOME/calls"
	: >"$TEST_UPDATE_CALLS"
	printf '#!/usr/bin/env bash\necho "%s %s"\n' "$binary" "$target_version" >"$TEST_UPDATE_ARTIFACT"
	local fixture_digest
	fixture_digest="$(sha256sum "$TEST_UPDATE_ARTIFACT")"
	printf '%s\n' "$fixture_key"$'\towner\tany\tdotfiles' "$fixture_key"$'\tkind\tany\tsoftware' \
		"$fixture_key"$'\tversion\tany\t'"$target_version" "$fixture_key"$'\tarchive\tany\traw' \
		"$fixture_key"$'\tbinary\tany\t'"$binary" "$fixture_key"$'\turl\tany\thttps://fixture.invalid/tool' \
		"$fixture_key"$'\tdigest\tany\tsha256:'"${fixture_digest%% *}" | catalog_fixture_seal "$HOME/catalog"
	catalog_fixture_use "$HOME/catalog"
	TEST_UPDATE_MISSING_COMMAND=''
	if [[ "$ownership" == managed ]]; then
		root="$(dotfiles_catalog_root "$fixture_key")"
		mkdir -p "$root/releases/baseline"
		printf '#!/usr/bin/env bash\necho "%s %s"\n' "$binary" "$installed_version" >"$root/releases/baseline/command"
		chmod +x "$root/releases/baseline/command"
		printf '%s\n%s\n%s\n' "$installed_version" "$SOFTWARE_CATALOG_DIGEST" "$SOFTWARE_CATALOG_REVISION" >"$root/releases/baseline/.catalog-receipt"
		ln -s "$root/releases/baseline" "$root/current"
		ln -s "$root/current/command" "$HOME/.local/bin/$binary"
		dotfiles_catalog_component_identity "$fixture_key" >"$root/current/.catalog-target" || return 1
	elif [[ "$ownership" == external ]]; then
		cp "$TEST_UPDATE_ARTIFACT" "$HOME/.local/bin/$binary"
		chmod +x "$HOME/.local/bin/$binary"
	else
		TEST_UPDATE_MISSING_COMMAND="$binary"
	fi
	command() {
		if [[ "$*" == "-v $TEST_UPDATE_MISSING_COMMAND" ]]; then return 1; fi
		builtin command "$@"
	}
	curl() {
		printf 'download\n' >>"$TEST_UPDATE_CALLS"
		while (($#)); do
			if [[ "$1" == -o ]]; then
				cp "$TEST_UPDATE_ARTIFACT" "$2"
				return
			fi
			shift
		done
		return 97
	}
	hash -r
}

update_codex_catalog_fixture() {
	update_tool_catalog_fixture codex_cli "$1" "$2" "${3:-managed}"
	export TEST_CODEX_UPDATE_MARKER="$HOME/uncontrolled-updater"
	source "$TEST_DIR/lib/codex_catalog_fixture.sh"
	make_codex_fixture "$1" yes "${4:-$1}"
	if [[ "${3:-managed}" == managed ]]; then
		dotfiles_catalog_component_identity codex_cli >"$(dotfiles_catalog_root codex_cli)/current/.catalog-target" || return 1
	fi
	curl() {
		printf 'download\n' >>"$TEST_UPDATE_CALLS"
		while (($#)); do
			if [[ "$1" == -o ]]; then
				cp "$TEST_HARNESS_ROOT/codex.tgz" "$2"
				return
			fi
			shift
		done
		return 97
	}
}

update_npm_catalog_fixture() {
	local target="$1" installed="$2" reported="${3:-$1}" root digest
	update_tool_catalog_fixture npm "$target" "$installed"
	root="$(dotfiles_catalog_root npm)"
	cp "$root/current/command" "$root/current/command-npx"
	ln -s "$root/current/command-npx" "$HOME/.local/bin/npx"
	mkdir -p "$HOME/npm-payload/package/bin"
	printf '{"name":"npm","version":"%s","dependencies":{},"bundleDependencies":[]}\n' "$target" >"$HOME/npm-payload/package/package.json"
	printf '#!/usr/bin/env bash\necho "%s"\n' "$reported" >"$HOME/npm-payload/package/bin/npm-cli.js"
	cp "$HOME/npm-payload/package/bin/npm-cli.js" "$HOME/npm-payload/package/bin/npx-cli.js"
	tar -czf "$HOME/npm.tgz" -C "$HOME/npm-payload" package
	digest="$(sha256sum "$HOME/npm.tgz")"
	printf '%s\n' $'npm\towner\tany\tdotfiles' $'npm\tkind\tany\tsoftware' \
		$'npm\tversion\tany\t'"$target" $'npm\tarchive\tany\ttgz' \
		$'npm\tbinary\tany\tpackage/bin/npm-cli.js' $'npm\turl\tany\thttps://fixture.invalid/npm.tgz' \
		$'npm\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$HOME/catalog-npm"
	catalog_fixture_use "$HOME/catalog-npm"
	dotfiles_catalog_component_identity npm >"$root/current/.catalog-target" || return 1
	curl() {
		printf 'download\n' >>"$TEST_UPDATE_CALLS"
		while (($#)); do
			if [[ "$1" == -o ]]; then
				cp "$HOME/npm.tgz" "$2"
				[[ "${TEST_NPM_DOWNLOAD_FAILS:-0}" != 1 ]] || return 56
				return
			fi
			shift
		done
		return 97
	}
	nvm() {
		printf 'floating nvm:%s\n' "$*" >>"$TEST_UPDATE_CALLS"
		return 97
	}
}

source "$TEST_DIR/lib/graphify_catalog_fixture.sh"

test_downstream_executes_apt_first_then_every_managed_step() (
	local events="$TEST_HARNESS_ROOT/downstream.events"
	: >"$events"
	sudo() {
		if [[ "$*" == --version ]]; then
			printf 'Sudo version 1.9.17p2\n'
		else
			printf 'sudo:%s\n' "$*" >>"$events"
		fi
	}
	npm_available_version() { printf '12.0.2\n'; }
	_run_upgrade_step() {
		printf 'step:%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" >>"$events"
		UPGRADE_STEP_RESULT["$1"]=ok
	}

	_run_update_downstream >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == 'sudo:apt-get update -qq' ]] || return 1
	grep -Fq 'step:apt packages|' "$events" || return 1
	grep -Fq 'step:Graphify CLI|' "$events" || return 1
	grep -Fq 'step:Boost CLI|' "$events" || return 1
	grep -Fq 'step:Node.js (nvm)|' "$events" || return 1
	grep -Fqx 'step:npm|dotfiles update|_apply_npm_update_step|' "$events" || return 1
	grep -Fq 'step:Go (asdf)|' "$events" || return 1
	grep -Fq 'step:Ubuntu Sans Mono fonts|' "$events"
)

# A failed step is a report about one tool, not a dead run: full-update reads
# this status to decide whether the phases queued behind the update still go.
test_a_failed_step_reports_partial_rather_than_plain_failure() (
	local rc=0
	sudo() { :; }
	npm_available_version() { printf '12.0.2\n'; }
	_run_upgrade_step() {
		if [[ "$1" == 'Boost CLI' ]]; then
			UPGRADE_STEP_RESULT["$1"]="$UPGRADE_RESULT_FAILED"
		else
			UPGRADE_STEP_RESULT["$1"]=ok
		fi
	}

	_run_update_downstream >/dev/null || rc=$?
	[[ "$rc" -eq "${DOTFILES_UPDATE_PARTIAL_RC:-4}" ]]
)

test_an_apt_refresh_failure_reports_partial_too() (
	local rc=0
	_run_apt_index_refresh() { return 1; }
	_run_upgrade_step() { UPGRADE_STEP_RESULT["$1"]=ok; }

	_run_update_downstream >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq "${DOTFILES_UPDATE_PARTIAL_RC:-4}" ]] || return 1
	[[ "${UPGRADE_STEP_RESULT['apt packages']}" == "$UPGRADE_RESULT_FAILED" ]]
)

test_update_rejects_the_retired_all_flag() (
	local events="$TEST_HARNESS_ROOT/downstream-all-flag.events"
	: >"$events"
	_dotfiles_run_update() { printf 'run:%s:%s\n' "$1" "$2" >>"$events"; }

	cmd_update >/dev/null || return 1
	! cmd_update --all >/dev/null 2>&1 || return 1
	[[ "$(<"$events")" == 'run:_dotfiles_confirm_repo_update:false' ]]
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
	local installed ownership expected
	while IFS='|' read -r installed ownership expected; do
		update_tool_catalog_fixture npm 12.0.1 "$installed" "$ownership"
		[[ "$(check_npm || true)" == "npm|$expected" ]] || return 1
	done <<'CASES'
11.16.0|managed|11.16.0|12.0.1|upgrade
12.0.1|managed|12.0.1|12.0.1|current
13.0.0|managed|13.0.0|12.0.1|blocked
ignored|external|external installation|12.0.1|external
ignored|absent|not installed|12.0.1|skip
CASES
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

test_npm_upgrade_scenario_matrix() (
	local reported expected mode rc
	while IFS='|' read -r reported expected mode; do
		update_npm_catalog_fixture 12.0.2 12.0.1 "$reported"
		unset TEST_NPM_DOWNLOAD_FAILS
		case "$mode" in
		download) TEST_NPM_DOWNLOAD_FAILS=1 ;;
		digest) printf corrupt >>"$HOME/npm.tgz" ;;
		esac
		rc=0
		upgrade_npm >"$HOME/output" 2>&1 || rc=$?
		if [[ "$expected" == success ]]; then
			[[ "$rc" == 0 && "$UPGRADE_STEP_ACTIVE_RESULT" == updated ]] || return 1
			[[ "$("$HOME/.local/bin/npm" --version)" == 12.0.2 && "$("$HOME/.local/bin/npx" --version)" == 12.0.2 ]] || return 1
		else
			[[ "$rc" != 0 && "$("$HOME/.local/bin/npm" --version)" == 'npm 12.0.1' ]] || return 1
			[[ "$mode" != download || "$rc" == 56 ]] || return 1
		fi
		! grep -Fq 'floating nvm:' "$TEST_UPDATE_CALLS" || return 1
	done <<'CASES'
12.0.2|success|normal
12.0.1|failure|normal
12.1.0|failure|normal
installed|failure|normal
12.0.2|failure|download
12.0.2|failure|digest
CASES
)

test_npm_upgrade_skips_commands_when_already_current() (
	update_npm_catalog_fixture 12.0.2 12.0.2
	upgrade_npm >"$HOME/output" 2>&1 || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == already-current && ! -s "$TEST_UPDATE_CALLS" ]] || return 1
	grep -Fq 12.0.2 "$HOME/output"
)

test_npm_failed_postcheck_sets_retryable_failed_step() (
	update_npm_catalog_fixture 12.0.2 12.0.1 12.0.1
	_run_upgrade_step npm "${UPDATE_STEP_RETRY[npm]}" upgrade_npm >"$HOME/output" 2>&1 || return 1
	[[ "${UPGRADE_STEP_RESULT[npm]}" == failed ]] || return 1
	grep -Fq 'retry manually: dotfiles update' "$HOME/output" || return 1
	[[ "$("$HOME/.local/bin/npm" --version)" == 'npm 12.0.1' ]]
)

test_unverifiable_cli_probes_label_latest_unchecked() (
	local key label binary output
	while IFS='|' read -r key label; do
		update_tool_catalog_fixture "$key" 2.0.0 ignored external
		binary="$(dotfiles_catalog_command_name "$key")"
		printf '#!/usr/bin/env bash\n: >%q\necho "2.0.0"\n' "$HOME/executed" >"$HOME/.local/bin/$binary"
		catalog_fixture_seal "$HOME/empty-catalog" </dev/null
		catalog_fixture_use "$HOME/empty-catalog"
		case "$key" in
		cursor_cli) output="$(check_cursor_cli || true)" ;;
		claude_cli) output="$(check_claude_cli || true)" ;;
		esac
		[[ "$output" == "$label|external installation|—|blocked" && ! -e "$HOME/executed" ]] || return 1
	done <<'CASES'
cursor_cli|Cursor CLI
claude_cli|Claude CLI
CASES
)

test_codex_probe_reports_ownership_and_release_states() (
	local installed ownership expected
	while IFS='|' read -r installed ownership expected; do
		update_tool_catalog_fixture codex_cli 0.150.0 "$installed" "$ownership"
		[[ "$(check_codex_cli || true)" == "Codex CLI|$expected" ]] || return 1
	done <<'CASES'
0.149.1|managed|0.149.1|0.150.0|upgrade
0.150.0|managed|0.150.0|0.150.0|current
0.151.0|managed|0.151.0|0.150.0|blocked
ignored|external|external installation|0.150.0|external
ignored|absent|not installed|0.150.0|skip
CASES
)

test_codex_update_application_preserves_ownership_and_result_truth() (
	update_codex_catalog_fixture 1.2.3 1.0.0
	upgrade_codex_cli >/dev/null || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == updated ]] || return 1
	[[ "$("$HOME/.local/bin/codex" --version)" == 'codex-cli 1.2.3' ]] || return 1
	: >"$TEST_UPDATE_CALLS"
	upgrade_codex_cli >/dev/null || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == already-current && ! -s "$TEST_UPDATE_CALLS" ]] || return 1
	local ownership
	for ownership in absent external; do
		update_codex_catalog_fixture 1.2.3 1.0.0 "$ownership"
		upgrade_codex_cli >/dev/null || return 1
		[[ "$UPGRADE_STEP_ACTIVE_RESULT" == skipped && ! -s "$TEST_UPDATE_CALLS" ]] || return 1
	done
	update_codex_catalog_fixture 1.2.3 1.0.0
	printf corrupt >>"$TEST_HARNESS_ROOT/codex.tgz"
	_run_upgrade_step 'Codex CLI' 'dotfiles update' upgrade_codex_cli >"$HOME/output" 2>&1 || return 1
	[[ "${UPGRADE_STEP_RESULT['Codex CLI']}" == failed ]] || return 1
	grep -Fq 'retry manually: dotfiles update' "$HOME/output" || return 1
	[[ "$("$HOME/.local/bin/codex" --version)" == 'codex 1.0.0' ]]
)

test_codex_current_release_skips_a_failing_installer() (
	local installed expected rc
	while IFS='|' read -r installed expected; do
		update_codex_catalog_fixture 1.2.3 "$installed"
		rc=0
		upgrade_codex_cli >"$HOME/output" 2>&1 || rc=$?
		if [[ "$expected" == current ]]; then
			[[ "$rc" == 0 && "$UPGRADE_STEP_ACTIVE_RESULT" == already-current ]] || return 1
		else
			[[ "$rc" != 0 ]] || return 1
			grep -Fq 'review version drift' "$HOME/output" || return 1
		fi
		[[ ! -s "$TEST_UPDATE_CALLS" ]] || return 1
		[[ "$("$HOME/.local/bin/codex" --version)" == "codex $installed" ]] || return 1
	done <<'CASES'
1.2.3|current
1.2.4|blocked
1.3.0-alpha.1|blocked
CASES
)

test_codex_verified_upgrade_checks_the_resulting_version() (
	local reported expected rc
	while IFS='|' read -r reported expected; do
		update_codex_catalog_fixture 1.2.3 1.0.0 managed "$reported"
		rc=0
		upgrade_codex_cli >"$HOME/output" 2>&1 || rc=$?
		if [[ "$expected" == success ]]; then
			[[ "$rc" == 0 && "$UPGRADE_STEP_ACTIVE_RESULT" == updated ]] || return 1
			[[ "$("$HOME/.local/bin/codex" --version)" == 'codex-cli 1.2.3' ]] || return 1
		else
			[[ "$rc" != 0 && "$("$HOME/.local/bin/codex" --version)" == 'codex 1.0.0' ]] || return 1
		fi
	done <<'CASES'
1.0.0|failure
1.2.3|success
1.2.4|failure
installed|failure
CASES
)

test_codex_retry_registry_uses_dotfiles_update() {
	[[ "${UPDATE_STEP_RETRY[codex]}" == 'dotfiles update' ]]
}

test_graphify_probe_reports_uv_owned_and_external_states() (
	update_tool_catalog_fixture graphify_cli 1.2.4 1.2.3
	[[ "$(check_graphify_cli || true)" == 'Graphify CLI|1.2.3|1.2.4|upgrade' ]] || return 1
	update_tool_catalog_fixture graphify_cli 1.2.4 ignored external
	[[ "$(check_graphify_cli || true)" == 'Graphify CLI|external installation|1.2.4|external' ]]
)

test_graphify_probe_skips_when_not_installed() (
	update_tool_catalog_fixture graphify_cli 1.2.4 ignored absent
	[[ "$(check_graphify_cli || true)" == 'Graphify CLI|not installed|1.2.4|skip' ]]
)

test_boost_probe_reports_managed_external_and_absent_states() (
	update_tool_catalog_fixture boost_cli 0.12.7 0.12.6
	[[ "$(check_boost_cli || true)" == 'Boost CLI|0.12.6|0.12.7|upgrade' ]] || return 1
	update_tool_catalog_fixture boost_cli 0.12.7 ignored external
	[[ "$(check_boost_cli || true)" == 'Boost CLI|external installation|0.12.7|external' ]] || return 1
	update_tool_catalog_fixture boost_cli 0.12.7 ignored absent
	[[ "$(check_boost_cli || true)" == 'Boost CLI|not installed|0.12.7|skip' ]]
)

test_boost_update_reconciles_only_dotfiles_owned_binary() (
	update_tool_catalog_fixture boost_cli 0.12.7 0.12.5
	upgrade_boost_cli >/dev/null || return 1
	[[ "$("$HOME/.local/bin/boost" --version)" == 'boost 0.12.7' ]] || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == updated ]] || return 1
	grep -Fxq download "$TEST_UPDATE_CALLS" || return 1
	update_tool_catalog_fixture boost_cli 0.12.7 ignored external
	upgrade_boost_cli >/dev/null || return 1
	[[ ! -s "$TEST_UPDATE_CALLS" && "$UPGRADE_STEP_ACTIVE_RESULT" == skipped ]]
)

test_graphify_upgrade_uses_uv_tool_upgrade() (
	graphify_reset
	install_graphify_cli >/dev/null || return 1
	graphify_fixture 1.2.4
	: >"$TEST_COMMAND_LOG"
	local output
	output="$(upgrade_graphify_cli)" || return 1
	grep -q '^uv:pip sync .*--require-hashes' "$TEST_COMMAND_LOG" || return 1
	! grep -q '^uv:tool upgrade' "$TEST_COMMAND_LOG" || return 1
	[[ "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.4' ]] || return 1
	[[ "$output" == *'Updated from 1.2.3 to 1.2.4'* && "$output" == *"run 'agentbot update' to refresh its skill"* ]]
)

test_graphify_upgrade_with_nothing_new_is_already_current() (
	graphify_reset
	install_graphify_cli >/dev/null || return 1
	: >"$TEST_COMMAND_LOG"
	upgrade_graphify_cli >"$HOME/graphify-output" || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == already-current && ! -s "$TEST_COMMAND_LOG" ]] || return 1
	grep -Fq 'Already current at 1.2.3' "$HOME/graphify-output"
)

test_graphify_upgrade_retries_with_system_certs_after_failure() (
	graphify_reset
	install_graphify_cli >/dev/null || return 1
	graphify_fixture 1.2.4
	: >"$TEST_COMMAND_LOG"
	export TEST_GRAPHIFY_CERT_RETRY=1
	upgrade_graphify_cli >"$HOME/graphify-output" 2>&1 || return 1
	[[ "$(grep -c '^uv:pip sync ' "$TEST_COMMAND_LOG")" == 2 ]] || return 1
	grep -Fxq certs:false "$TEST_COMMAND_LOG" || return 1
	grep -Fxq certs:true "$TEST_COMMAND_LOG" || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == updated && "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.4' ]]
)

test_graphify_first_attempt_error_is_quiet_when_the_retry_works() (
	graphify_reset
	install_graphify_cli >/dev/null || return 1
	graphify_fixture 1.2.4
	export TEST_GRAPHIFY_CERT_RETRY=1
	local output
	output="$(upgrade_graphify_cli 2>&1)" || return 1
	[[ "$output" != *UnknownIssuer* && "$output" != *'Error during'* ]] || return 1
	[[ "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.4' ]]
)

test_graphify_upgrade_failure_has_copyable_retry_command() (
	graphify_reset
	install_graphify_cli >/dev/null || return 1
	local previous
	previous="$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" || return 1
	graphify_fixture 1.2.4
	: >"$TEST_COMMAND_LOG"
	export TEST_GRAPHIFY_SYNC_FAILS=1
	_run_upgrade_step 'Graphify CLI' "${UPDATE_STEP_RETRY[graphify]}" upgrade_graphify_cli >"$HOME/graphify-output" 2>&1 || return 1
	[[ "${UPGRADE_STEP_RESULT['Graphify CLI']}" == failed ]] || return 1
	[[ "$(grep -c '^uv:pip sync ' "$TEST_COMMAND_LOG")" == 2 ]] || return 1
	grep -Fq 'retry manually: dotfiles update' "$HOME/graphify-output" || return 1
	[[ "$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" == "$previous" ]] || return 1
	[[ "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.3' ]]
)

test_upgrade_step_marks_failures_in_red_with_retry_command() (
	local output
	unset NO_COLOR
	export FORCE_COLOR=1
	colors_clear_palette
	_failing_probe() { return 7; }

	output="$(_run_upgrade_step 'probe' 'probe --retry' _failing_probe 2>&1)"
	grep -Fq $'\033[31m>> FAILED (exit 7) — retry manually: probe --retry <<\033[0m' <<<"$output"
)

test_upgrade_step_respects_no_color_with_retry_command() (
	local output
	export NO_COLOR=1 FORCE_COLOR=1
	colors_set_palette
	_failing_probe() { return 7; }

	output="$(_run_upgrade_step 'probe' 'probe --retry' _failing_probe 2>&1)"
	grep -Fq '>> FAILED (exit 7) — retry manually: probe --retry <<' <<<"$output" || return 1
	[[ "$output" != *$'\033['* ]]
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
	runtime_failure_fixture node
	local rc=0
	upgrade_node >"$HOME/output" 2>&1 || rc=$?
	[[ "$rc" == 27 && "$(cat "$TEST_RUNTIME_FAILURE_CALLS")" == 'source:nvm' ]] || return 1
	[[ "$("$HOME/.local/bin/node" --version)" == 'node 24.0.0' ]] || return 1
	[[ ! -e "$HOME/.local/share/dotfiles-catalog/nodejs.native" ]]
)

test_go_upgrade_stops_when_asdf_install_fails() (
	runtime_failure_fixture go
	local rc=0
	upgrade_go >"$HOME/output" 2>&1 || rc=$?
	[[ "$rc" == 27 && "$(cat "$TEST_RUNTIME_FAILURE_CALLS")" == 'download:https://fixture.invalid/asdf' ]] || return 1
	[[ "$("$HOME/.local/bin/go" --version)" == 'go 1.2.2' ]] || return 1
	[[ ! -e "$HOME/.local/share/dotfiles-catalog/go.native" ]]
)

test_go_reads_asdf_from_where_the_installer_put_it() (
	# Break caught: the bootstrap installs Go through asdf, then runs the update
	# in a new process whose PATH predates the stowed .bashrc. The update
	# reported "Go (asdf) | not installed" and skipped the upgrade one screen
	# after the install reported go1.27.1 installed.
	local home="$TEST_HARNESS_ROOT/asdf-home"
	rm -rf -- "$home"
	mkdir -p -- "$home/.asdf/bin" "$home/.asdf/shims"
	cat >"$home/.asdf/bin/asdf" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
'current golang') printf 'golang 1.27.1 %s\n' "$HOME/.tool-versions" ;;
'latest golang') printf '1.27.1\n' ;;
esac
EOF
	chmod +x -- "$home/.asdf/bin/asdf"

	local output
	# PATH stripped: the machine running the suite may have its own asdf, and
	# finding that one would prove nothing about the fallback.
	output="$(HOME="$home" ASDF_DIR="$home/.asdf" PATH=/usr/bin:/bin bash -c '
		source "$1"
		NOT_INSTALLED="not installed"
		go_installed_version
	' _ "$REPO_DIR/scripts/lib/updates/runtimes.sh")" || return 1
	[[ "$output" == '1.27.1' ]] || return 1

	# No checkout, no claim: an absent asdf is still reported as absent, and
	# PATH holds nothing at all so a system `go` cannot answer for it either.
	local empty="$TEST_HARNESS_ROOT/asdf-absent"
	rm -rf -- "$empty"
	mkdir -p -- "$empty/bin"
	# Absolute interpreter: PATH is deliberately empty of everything.
	output="$(HOME="$empty" ASDF_DIR="$empty/.asdf" PATH="$empty/bin" /bin/bash -c '
		source "$1"
		NOT_INSTALLED="not installed"
		go_installed_version
	' _ "$REPO_DIR/scripts/lib/updates/runtimes.sh")" || return 1
	[[ "$output" == 'not installed' ]]
)

test_cursor_update_blocks_before_cli_execution() (
	update_tool_catalog_fixture cursor_cli 2.0.0 1.0.0
	printf '#!/usr/bin/env bash\n: >%q\necho "agent 1.0.0"\n' "$HOME/executed" >"$(dotfiles_catalog_root cursor_cli)/current/command"
	local rc=0
	upgrade_cursor_cli >"$HOME/output" 2>&1 || rc=$?
	[[ "$rc" != 0 && ! -e "$HOME/executed" && ! -s "$TEST_UPDATE_CALLS" ]] || {
		echo 'FAIL: blocked Cursor update executed the CLI or a floating fallback' >&2
		return 1
	}
	grep -Fq 'no verified autonomous-update suppression' "$HOME/output"
)

test_cursor_status_blocks_before_executing_the_cli() (
	update_tool_catalog_fixture cursor_cli 2.0.0 1.0.0
	printf '#!/usr/bin/env bash\n: >%q\necho "agent 1.0.0"\n' "$HOME/executed" >"$(dotfiles_catalog_root cursor_cli)/current/command"
	local output
	output="$(check_cursor_cli || true)"
	[[ "$output" == 'Cursor CLI|installed|2.0.0|blocked' && ! -e "$HOME/executed" ]] || {
		echo 'FAIL: blocked Cursor status executed the CLI or claimed qualification' >&2
		return 1
	}
)

test_a_self_update_is_reported_by_its_versions() (
	update_tool_catalog_fixture boost_cli 0.13.30 0.13.28
	local label='Boost CLI'
	_run_upgrade_step "$label" 'dotfiles update' upgrade_boost_cli >/dev/null 2>&1 || return 1
	[[ "${UPGRADE_STEP_RESULT[$label]}" == updated ]] || return 1
	: >"$TEST_UPDATE_CALLS"
	_run_upgrade_step "$label" 'dotfiles update' upgrade_boost_cli >/dev/null 2>&1 || return 1
	[[ "${UPGRADE_STEP_RESULT[$label]}" == already-current && ! -s "$TEST_UPDATE_CALLS" ]]
)

test_a_windows_cursor_is_never_executed() (
	# Break caught: the update resolved `cursor` with a bare `command -v`, which
	# under appendWindowsPath is the Windows editor, and then ran
	# "<Windows Cursor> update" -- launching the IDE on the operator's desktop
	# mid-install. `cursor` is the editor launcher and is never the CLI.
	local machine="$TEST_HARNESS_ROOT/windows-cursor"
	local calls="$machine/calls" output="$machine/output" label='Cursor CLI'
	local win_bin="$machine/mnt/c/cursor/bin"
	mkdir -p -- "$win_bin" "$machine/home"
	: >"$calls"
	printf '#!/usr/bin/env bash\nprintf "launched-ide:%%s\\n" "$*" >>"%s"\n' "$calls" >"$win_bin/cursor"
	chmod +x -- "$win_bin/cursor"

	local result
	result="$(
		export HOME="$machine/home"
		# A fixed PATH, not an extended one: the developer's own machine may
		# carry a real Cursor CLI, and this test is about what happens when the
		# only thing that answers to a Cursor name is the Windows editor.
		export PATH="$win_bin:/usr/bin:/bin"
		export DOTFILES_WINDOWS_MOUNT_ROOT="$machine/mnt"
		export DOTFILES_NO_PROGRESS_ANIMATION=1
		run_vendor_shell_installer() { printf 'fallback\n' >>"$calls"; }
		_run_upgrade_step 'Cursor CLI' 'dotfiles update' upgrade_cursor_cli >"$output" 2>&1
		printf '%s' "${UPGRADE_STEP_RESULT[$label]:-}"
	)" || return 1

	# Nothing was executed and nothing was reinstalled: with no Linux CLI
	# present the honest outcome is "not installed".
	[[ ! -s "$calls" ]] || return 1
	[[ "$result" == skipped ]] || return 1
	grep -Fq 'Skipping absent or externally owned' "$output"
)

test_the_apt_upgrade_is_quiet_and_reported_as_updated() (
	# Break caught: the upgrade ran apt-get raw, so a 140-package run printed
	# several hundred lines of dpkg unpacking and buried every other phase --
	# and then reported "checked/no change" for it.
	local machine="$TEST_HARNESS_ROOT/apt-quiet"
	local output="$machine/output"
	mkdir -p -- "$machine"

	local result
	result="$(
		export DOTFILES_NO_PROGRESS_ANIMATION=1
		apt_upgradable_count() { printf '140\n'; }
		sudo() { printf 'DPKG-NOISE\n'; }
		_update_apt_packages >"$output" 2>&1
		printf '%s' "$UPGRADE_STEP_ACTIVE_RESULT"
	)" || return 1

	# The dpkg output is captured, not printed; the count is what the operator
	# is told, so a hidden upgrade is still an announced one.
	! grep -Fq 'DPKG-NOISE' "$output" || return 1
	grep -Fq 'Apply 140 package upgrade(s)' "$output" || return 1
	grep -Fq 'Upgraded 140 package(s)' "$output" || return 1
	[[ "$result" == updated ]]
)

test_a_failed_apt_upgrade_still_shows_its_output() (
	# Quiet on success only: a failure that swallowed its own diagnostics would
	# be worse than the noise.
	local machine="$TEST_HARNESS_ROOT/apt-loud"
	local output="$machine/output"
	mkdir -p -- "$machine"

	local rc=0
	(
		apt_upgradable_count() { printf '3\n'; }
		sudo() {
			printf 'E: could not resolve archive.ubuntu.com\n'
			return 100
		}
		_update_apt_packages >"$output" 2>&1
	) || rc=$?

	[[ "$rc" -ne 0 ]] || return 1
	grep -Fq 'could not resolve archive.ubuntu.com' "$output"
)

test_every_upgrade_step_says_something() (
	# Break caught: capturing the Codex installer's narration left its update
	# section as a heading with nothing under it, which reads as a step that
	# died. A step that prints nothing is indistinguishable from one that hung.
	local machine="$TEST_HARNESS_ROOT/codex-speaks"
	local output="$machine/output"
	mkdir -p -- "$machine"

	export HOME="$machine/home" TEST_CODEX_UPDATE_MARKER="$machine/uncontrolled-updater"
	PATH="$HOME/.local/bin:/usr/bin:/bin"
	export PATH
	source "$TEST_DIR/lib/codex_catalog_fixture.sh"
	make_codex_fixture 1.2.3
	curl() {
		while (($#)); do
			if [[ "$1" == -o ]]; then
				cp "$TEST_HARNESS_ROOT/codex.tgz" "$2"
				return
			fi
			shift
		done
		return 1
	}
	CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin"
	export CODEX_HOME CODEX_INSTALL_DIR
	install_codex_cli >"$output" 2>&1 || {
		echo 'FAIL: narration fixture installation failed' >&2
		cat "$output" >&2
		return 1
	}
	[[ "$("$HOME/.local/bin/codex" --version)" == 'codex-cli 1.2.3' ]] || return 1
	upgrade_codex_cli >"$output" 2>&1 || return 1
	[[ -s "$output" ]] || {
		echo 'FAIL: current approved Codex update is silent' >&2
		return 1
	}
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == already-current ]] || return 1
	grep -Fq '1.2.3' "$output" || return 1

	# The apt step is silent precisely when it has the least to do, which is
	# when an empty section is most likely to read as a failure.
	local apt_output="$machine/apt-output"
	local apt_result
	apt_result="$(
		apt_upgradable_count() { printf '0\n'; }
		sudo() { :; }
		_update_apt_packages >"$apt_output" 2>&1
		printf '%s' "$UPGRADE_STEP_ACTIVE_RESULT"
	)" || return 1
	[[ -s "$apt_output" ]] || return 1
	[[ "$apt_result" == checked-no-change ]]
)

test_copilot_update_management_is_absent() {
	! declare -F copilot_command >/dev/null || return 1
	! declare -F copilot_installed_version >/dev/null || return 1
	! declare -F copilot_is_installed >/dev/null || return 1
	! declare -F check_copilot_cli >/dev/null || return 1
	! declare -F upgrade_copilot_cli >/dev/null
}

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
	[[ "$output" == 'apt packages|system packages|none (cached)|refresh-required' ]]
)

test_installed_version_reports_installed_when_version_command_fails() (
	local bin_dir="$TEST_HARNESS_ROOT/broken-version-bin"
	mkdir -p "$bin_dir"
	# A tool that exists but whose --version fails must report "installed",
	# not an empty cell. `cmd --version | head -n1 || echo installed` could
	# never do this: head exits 0 on empty input.
	printf '#!/bin/sh\nexit 3\n' >"$bin_dir/claude"
	chmod +x "$bin_dir/claude"
	[[ "$(PATH="$bin_dir:/usr/bin:/bin" HOME="$TEST_HARNESS_ROOT" claude_installed_version)" == 'installed' ]] || return 1

	printf '#!/bin/sh\nexit 3\n' >"$bin_dir/lazydocker"
	chmod +x "$bin_dir/lazydocker"
	[[ "$(PATH="$bin_dir:/usr/bin:/bin" HOME="$TEST_HARNESS_ROOT" lazydocker_installed_version)" == "$NOT_INSTALLED" ]]
)

test_status_and_update_share_one_tool_resolver() (
	# Both paths must find the same executable, including the ~/.local/bin
	# fallback, so status and update cannot disagree about what is installed.
	local home_dir="$TEST_HARNESS_ROOT/shared-resolver-home"
	mkdir -p "$home_dir/.local/bin"
	printf '#!/bin/sh\necho 9.9.9\n' >"$home_dir/.local/bin/claude"
	chmod +x "$home_dir/.local/bin/claude"
	local empty="$TEST_HARNESS_ROOT/shared-resolver-bin"
	mkdir -p "$empty"
	[[ "$(PATH="$empty:/usr/bin:/bin" HOME="$home_dir" tool_resolve claude)" == "$home_dir/.local/bin/claude" ]] || return 1
	[[ "$(PATH="$empty:/usr/bin:/bin" HOME="$home_dir" claude_installed_version)" == '9.9.9' ]]
)

expect_success 'installed-version reports installed when the version command fails' test_installed_version_reports_installed_when_version_command_fails
expect_success 'status and update share one tool resolver' test_status_and_update_share_one_tool_resolver
expect_success 'downstream execution runs apt refresh first, then every managed step' test_downstream_executes_apt_first_then_every_managed_step
expect_success 'a failed step reports partial rather than plain failure' test_a_failed_step_reports_partial_rather_than_plain_failure
expect_success 'an apt refresh failure reports partial too' test_an_apt_refresh_failure_reports_partial_too
expect_success 'update rejects the retired --all flag' test_update_rejects_the_retired_all_flag
expect_success 'Node.js probe follows nvm default instead of a stale shell PATH' test_node_probe_uses_nvm_default_when_shell_path_is_stale
expect_success 'npm probe reports upgrade current and missing states' test_npm_probe_reports_upgrade_current_and_missing_states
expect_success 'npm version verification accepts only safe equal or newer versions' test_npm_version_reached_requires_a_safe_equal_or_newer_version
expect_success 'npm upgrade verifies its exact bundled archive and preserves working commands on failure' test_npm_upgrade_scenario_matrix
expect_success 'current approved npm skips downloads and floating manager updates' test_npm_upgrade_skips_commands_when_already_current
expect_success 'npm failed post-check records a copyable failed step' test_npm_failed_postcheck_sets_retryable_failed_step
expect_success 'missing approved CLI pins report blocked without executing external commands' test_unverifiable_cli_probes_label_latest_unchecked
expect_success 'Codex update probe reports standalone, absent, and external states' test_codex_probe_reports_ownership_and_release_states
expect_success 'Codex update application records changed, unchanged, skipped, and failed outcomes' test_codex_update_application_preserves_ownership_and_result_truth
expect_success 'current Codex skips downloads and newer drift blocks replacement' test_codex_current_release_skips_a_failing_installer
expect_success 'verified Codex upgrade must match the exact approved version' test_codex_verified_upgrade_checks_the_resulting_version
expect_success 'Codex update retry uses the guarded Dotfiles workflow' test_codex_retry_registry_uses_dotfiles_update
expect_success 'Graphify update probe distinguishes uv-owned and external installs' test_graphify_probe_reports_uv_owned_and_external_states
expect_success 'Graphify update probe skips an absent CLI' test_graphify_probe_skips_when_not_installed
expect_success 'Boost probe reports managed external and absent states' test_boost_probe_reports_managed_external_and_absent_states
expect_success 'Boost update reconciles only a Dotfiles-owned binary' test_boost_update_reconciles_only_dotfiles_owned_binary
expect_success 'Graphify update applies the frozen closure and reminds about skill refresh' test_graphify_upgrade_uses_uv_tool_upgrade
expect_success 'Graphify update with nothing new is already current' test_graphify_upgrade_with_nothing_new_is_already_current
expect_success 'Graphify update retries with system certificates after failure' test_graphify_upgrade_retries_with_system_certs_after_failure
expect_success 'Graphify first-attempt error is quiet when the retry works' test_graphify_first_attempt_error_is_quiet_when_the_retry_works
expect_success 'Graphify update failures include a copyable retry command' test_graphify_upgrade_failure_has_copyable_retry_command
expect_success 'upgrade step marks failures in red with retry command' test_upgrade_step_marks_failures_in_red_with_retry_command
expect_success 'upgrade step respects NO_COLOR and retains retry command' test_upgrade_step_respects_no_color_with_retry_command
expect_success 'upgrade step omits failure marker after success' test_upgrade_step_omits_failure_marker_after_success
expect_success 'Node.js upgrade stops when its approved NVM source is unavailable' test_node_upgrade_stops_when_nvm_install_fails
expect_success 'Go upgrade stops when its approved asdf artifact cannot download' test_go_upgrade_stops_when_asdf_install_fails
expect_success 'Go reads asdf from where the installer put it' test_go_reads_asdf_from_where_the_installer_put_it
expect_success 'Cursor update blocks before CLI execution or floating fallback' test_cursor_update_blocks_before_cli_execution
expect_success 'Cursor status blocks before executing a managed CLI' test_cursor_status_blocks_before_executing_the_cli
expect_success 'a catalog update is reported by observed before and after versions' test_a_self_update_is_reported_by_its_versions
expect_success 'a Windows cursor is never executed' test_a_windows_cursor_is_never_executed
expect_success 'the apt upgrade is quiet and reported as updated' test_the_apt_upgrade_is_quiet_and_reported_as_updated
expect_success 'a failed apt upgrade still shows its output' test_a_failed_apt_upgrade_still_shows_its_output
expect_success 'every upgrade step says something' test_every_upgrade_step_says_something
expect_success 'Copilot has no update helpers' test_copilot_update_management_is_absent
expect_success 'pre-confirmation apt report probing never invokes sudo' test_apt_report_probe_uses_cached_indices_without_sudo

expect_success 'apt preview labels cached metadata without claiming it is current' test_apt_report_does_not_claim_cached_indices_are_current

finish_tests
