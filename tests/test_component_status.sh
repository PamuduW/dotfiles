#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init

PKG_FILE="$REPO_DIR/packages/packages.txt"
export PKG_FILE

# shellcheck source=scripts/lib/components/registry.sh
source "$REPO_DIR/scripts/lib/components/registry.sh"
# shellcheck source=scripts/lib/components/probes.sh
source "$REPO_DIR/scripts/lib/components/probes.sh"

test_harness_report_init

test_probe_capture_keeps_only_first_line() {
	local command_path="$TEST_HARNESS_ROOT/two-lines" output=''
	printf '#!/usr/bin/env bash\nprintf "first\\nsecond\\n"\n' >"$command_path"
	chmod +x "$command_path"

	_comp_probe_capture output 1 "$command_path" || return 1
	[[ "$output" == first ]]
}

test_probe_capture_preserves_command_failure() {
	local command_path="$TEST_HARNESS_ROOT/fails" output='unchanged' rc
	printf '#!/usr/bin/env bash\nexit 23\n' >"$command_path"
	chmod +x "$command_path"

	set +e
	_comp_probe_capture output 1 "$command_path"
	rc=$?
	set -e
	[[ "$rc" -eq 23 && -z "$output" ]]
}

test_probe_capture_bounds_stalled_command() {
	local command_path="$TEST_HARNESS_ROOT/stalls" output='unchanged' rc
	printf '#!/usr/bin/env bash\nsleep 5\n' >"$command_path"
	chmod +x "$command_path"

	set +e
	_comp_probe_capture output 0.05 "$command_path"
	rc=$?
	set -e
	[[ "$rc" -eq 124 && -z "$output" ]]
}

test_probe_capture_normalizes_forced_kill_timeout() {
	local command_path="$TEST_HARNESS_ROOT/ignores-term" output='unchanged' rc
	printf '#!/usr/bin/env bash\ntrap "" TERM\nwhile true; do sleep 1; done\n' >"$command_path"
	chmod +x "$command_path"

	set +e
	_comp_probe_capture output 0.05 "$command_path"
	rc=$?
	set -e
	[[ "$rc" -eq 124 && -z "$output" ]]
}

test_codex_probe_reports_local_ownership_states() (
	local fixture_state fixture_version fixture_rc expected actual
	local active_path="$HOME/.nvm/versions/node/v24.0.0/bin/codex"
	local forbidden_log="$TEST_HARNESS_ROOT/codex-probe-forbidden.log"
	: >"$forbidden_log"
	codex_cli_install_state() { printf '%s\n' "$fixture_state"; }
	codex_active_command() { printf '%s\n' "$active_path"; }
	codex_visible_install_path() { printf '%s\n' "$HOME/.local/bin/codex"; }
	_comp_probe_capture() {
		printf -v "$1" '%s' "$fixture_version"
		return "$fixture_rc"
	}
	curl() { printf 'curl\n' >>"$forbidden_log"; }
	npm() { printf 'npm\n' >>"$forbidden_log"; }
	_load_nvm() { printf 'nvm\n' >>"$forbidden_log"; }
	codex_sync_standalone() { printf 'installer\n' >>"$forbidden_log"; }
	codex() { printf 'codex:%s\n' "$*" >>"$forbidden_log"; }

	while IFS='|' read -r fixture_state fixture_version fixture_rc expected; do
		actual="$(_comp_probe_codex_cli)"
		[[ "$actual" == "$expected" ]] || {
			printf '%s returned %q\n' "$fixture_state" "$actual" >&2
			return 1
		}
	done <<EOF
standalone|codex-cli 0.150.0|0|installed|codex-cli 0.150.0 (standalone)
external|codex-cli 0.149.1|0|check|codex-cli 0.149.1 (external; migration required)
standalone-shadowed|ignored|0|check|standalone Codex is shadowed by $active_path
absent|ignored|0|missing|codex not on PATH
standalone|ignored|124|check|codex cli probe timed out
EOF
	[[ ! -s "$forbidden_log" ]]
)

test_doctor_routes_codex_remediation_by_ownership() (
	DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/bin/bin/dotfiles" >/dev/null
	dotfiles_load_command doctor
	local fixture_row output rc active_path="$HOME/.nvm/versions/node/v24.0.0/bin/codex"
	collect_component_status_rows() {
		local -n rows_ref="$1"
		rows_ref=("$fixture_row")
	}
	codex_active_command() { printf '%s\n' "$active_path"; }

	fixture_row='Codex CLI|codex not on PATH|missing'
	rc=0
	output="$(NO_COLOR=1 cmd_doctor)" || rc=$?
	[[ "$rc" -ne 0 && "$output" == *'initial setup'* && "$output" == *'select Codex CLI'* ]] || return 1

	for fixture_row in \
		'Codex CLI|codex-cli 0.149.1 (external; migration required)|check' \
		"Codex CLI|standalone Codex is shadowed by $active_path|check"; do
		rc=0
		output="$(NO_COLOR=1 cmd_doctor)" || rc=$?
		[[ "$rc" -ne 0 && "$output" == *"$active_path"* ]] || return 1
		[[ "$output" == *'README.md#codex-cli-migration'* && "$output" != *'temp/process.md'* ]] || return 1
	done

	fixture_row='Codex CLI|codex cli probe timed out|check'
	rc=0
	output="$(NO_COLOR=1 cmd_doctor)" || rc=$?
	[[ "$rc" -ne 0 && "$output" == *'dotfiles update'* && "$output" != *'README.md#codex-cli-migration'* ]] || return 1

	fixture_row='Codex CLI|codex-cli 0.150.0 (standalone)|installed'
	output="$(NO_COLOR=1 cmd_doctor)" || return 1
	[[ "$output" == *'Nothing needs attention.'* && "$output" != *'Codex migration'* ]]
)

test_stalled_version_probe_returns_one_neutral_row() (
	local fake_bin="$TEST_HARNESS_ROOT/stall-bin"
	local command_path="$fake_bin/cursor"
	mkdir -p "$fake_bin"
	printf '#!/usr/bin/env bash\nsleep 5\n' >"$command_path"
	chmod +x "$command_path"
	PATH="$fake_bin:/usr/bin:/bin"
	COMP_PROBE_TIMEOUT_SECONDS=0.05
	export PATH COMP_PROBE_TIMEOUT_SECONDS

	[[ "$(_comp_probe_cursor_cli)" == 'check|cursor cli probe timed out' ]]
)

test_external_probes_share_bounded_timeout_behavior() (
	local fake_bin="$TEST_HARNESS_ROOT/bounded-bin"
	local fake_tool="$fake_bin/_probe_tool" name fn expected actual
	mkdir -p "$fake_bin"
	printf '#!/usr/bin/env bash\nexit 124\n' >"$fake_tool"
	chmod +x "$fake_tool"
	for name in timeout graphify pwsh go asdf node direnv docker lazygit lazydocker cursor codex claude copilot; do
		ln -sf -- _probe_tool "$fake_bin/$name"
	done
	HOME="$TEST_HARNESS_ROOT/empty-home"
	mkdir -p "$HOME"
	PATH="$fake_bin:/usr/bin:/bin"
	export HOME PATH
	graphify_command() { printf '%s\n' "$fake_bin/graphify"; }
	graphify_cli_is_uv_owned() { return 1; }

	while IFS='|' read -r fn expected; do
		actual="$("$fn")"
		[[ "$actual" == "check|${expected} probe timed out" ]] || {
			printf '%s returned %q\n' "$fn" "$actual" >&2
			return 1
		}
	done <<'EOF'
_comp_probe_graphify_cli|graphify cli
_comp_probe_powershell|powershell
_comp_probe_go|go
_comp_probe_nodejs|node
_comp_probe_direnv|direnv
_comp_probe_docker|docker
_comp_probe_portainer|portainer
_comp_probe_lazygit|lazygit
_comp_probe_lazydocker|lazydocker
_comp_probe_cursor_cli|cursor cli
_comp_probe_codex_cli|codex cli
_comp_probe_claude_cli|claude cli
_comp_probe_copilot_cli|copilot cli
EOF
)

test_component_collector_overlaps_probes_and_preserves_registry_order() (
	local barrier="$TEST_HARNESS_ROOT/probe-barrier" count i
	local -a rows=()
	mkdir -p "$barrier"
	COMP_KEYS=(alpha beta gamma)
	COMP_LABELS=(Alpha Beta Gamma)
	comp_probe() {
		local key="$1"
		: >"$barrier/$key"
		for ((i = 0; i < 100; i++)); do
			count="$(find "$barrier" -maxdepth 1 -type f | wc -l)"
			[[ "$count" -eq 3 ]] && break
			sleep 0.01
		done
		[[ "$count" -eq 3 ]] || {
			printf 'check|probes did not overlap\n'
			return 0
		}
		case "$key" in alpha) sleep 0.03 ;; beta) sleep 0.01 ;; esac
		printf 'installed|%s detail\n' "$key"
	}

	collect_component_status_rows rows
	[[ "$(printf '%s\n' "${rows[@]}")" == $'Alpha|alpha detail|installed\nBeta|beta detail|installed\nGamma|gamma detail|installed' ]]
)

test_component_collector_keeps_rows_when_one_probe_fails() (
	local -a rows=()
	COMP_KEYS=(alpha broken gamma)
	COMP_LABELS=(Alpha Broken Gamma)
	comp_probe() {
		[[ "$1" != broken ]] || return 19
		printf 'installed|%s detail\n' "$1"
	}

	collect_component_status_rows rows
	[[ "$(printf '%s\n' "${rows[@]}")" == $'Alpha|alpha detail|installed\nBroken|probe failed|check\nGamma|gamma detail|installed' ]]
)

test_status_is_local_read_only() {
	local output="$TEST_HARNESS_ROOT/status.output"
	local protected_relative=".dotfiles-task05-status-${BASHPID}"
	local forbidden=$'^(curl|npx|sudo|stow|apt-get)\t|^git\t.*\t(fetch|pull)(\t|$)'
	local fake
	test_harness_protect_original_path "$protected_relative"
	for fake in sudo stow apt-get; do
		ln -s -- _test_fake_command "$TEST_FAKE_BIN/$fake"
		test_harness_configure_fake "$fake" 98 '' 'read-only status must not invoke this command'
	done
	test_harness_configure_fake git 0 $'## feat/test\n'
	test_harness_reset_logs
	"$REPO_DIR/bin/bin/dotfiles" status >"$output" || return 1
	grep -Fqi 'freshness' "$output" || return 1
	grep -Fqi 'unchecked' "$output" || return 1
	if grep -Eq "$forbidden" "$TEST_COMMAND_LOG"; then
		return 1
	fi
	[[ ! -s "$TEST_URL_LOG" ]]
}

expect_success 'probe capture keeps only the first output line' test_probe_capture_keeps_only_first_line
expect_success 'probe capture preserves command failure status' test_probe_capture_preserves_command_failure
expect_success 'probe capture bounds a stalled command' test_probe_capture_bounds_stalled_command
expect_success 'probe capture normalizes forced-kill timeout' test_probe_capture_normalizes_forced_kill_timeout
expect_success 'Codex probe reports standalone, external, shadowed, absent, and timeout states locally' test_codex_probe_reports_local_ownership_states
expect_success 'Doctor routes Codex absence and ownership conflicts to actionable remediation' test_doctor_routes_codex_remediation_by_ownership
expect_success 'stalled version probe returns one neutral row' test_stalled_version_probe_returns_one_neutral_row
expect_success 'external probes share bounded timeout behavior' test_external_probes_share_bounded_timeout_behavior
expect_success 'component collector overlaps probes and preserves registry order' test_component_collector_overlaps_probes_and_preserves_registry_order
expect_success 'component collector keeps rows when one probe fails' test_component_collector_keeps_rows_when_one_probe_fails

test_generic_version_probes_cover_every_table_row() (
	local row id
	((${#_COMP_VERSION_PROBES[@]} > 0)) || return 1
	for row in "${_COMP_VERSION_PROBES[@]}"; do
		IFS='|' read -r id _ <<<"$row"
		declare -F "_comp_probe_${id}" >/dev/null || {
			printf 'table row without a probe function: %s\n' "$id" >&2
			return 1
		}
		comp_index_of "$id" >/dev/null || {
			printf 'table row is not a registered component: %s\n' "$id" >&2
			return 1
		}
	done
)

test_generic_probe_reports_missing_timeout_and_version() (
	local bin_dir="$TEST_HARNESS_ROOT/generic-probe-bin"
	local home_dir="$TEST_HARNESS_ROOT/generic-probe-home"
	mkdir -p "$bin_dir" "$home_dir"

	# absent binary uses the missing label, not the timeout label
	[[ "$(PATH="$bin_dir:/usr/bin:/bin" HOME="$home_dir" \
		_comp_probe_version 'nope/absent' 'absent cli' nope-absent-cli --version '' '' '')" == 'missing|nope/absent not on PATH' ]] || return 1

	# a version is extracted and prefixed
	printf '#!/bin/sh\necho "some 1.2.3 build"\n' >"$bin_dir/toolx"
	chmod +x "$bin_dir/toolx"
	[[ "$(PATH="$bin_dir:/usr/bin:/bin" HOME="$home_dir" \
		_comp_probe_version toolx toolx toolx --version '[0-9]+\.[0-9]+\.[0-9]+' 'v' '')" == 'installed|v1.2.3' ]] || return 1

	# the ~/.local/bin fallback is used when the command is not on PATH
	mkdir -p "$home_dir/.local/bin"
	printf '#!/bin/sh\necho fallback-9\n' >"$home_dir/.local/bin/tooly"
	chmod +x "$home_dir/.local/bin/tooly"
	[[ "$(PATH="$bin_dir:/usr/bin:/bin" HOME="$home_dir" \
		_comp_probe_version tooly tooly tooly --version '' '' '')" == 'installed|fallback-9' ]] || return 1

	# a hung binary reports the timeout label
	printf '#!/bin/sh\nsleep 5\n' >"$bin_dir/toolz"
	chmod +x "$bin_dir/toolz"
	[[ "$(COMP_PROBE_TIMEOUT_SECONDS=1 PATH="$bin_dir:/usr/bin:/bin" HOME="$home_dir" \
		_comp_probe_version toolz 'tool z' toolz --version '' '' '')" == 'check|tool z probe timed out' ]]
)
expect_success 'dotfiles status is local-only and reports freshness unchecked' test_status_is_local_read_only
expect_success 'every version-probe table row has a probe and a registered component' test_generic_version_probes_cover_every_table_row
expect_success 'generic probe reports missing, version, fallback, and timeout states' test_generic_probe_reports_missing_timeout_and_version

finish_tests
