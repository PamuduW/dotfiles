#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2030,SC2031  # Dynamic repo sources and isolated subshell tests are intentional.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=tests/lib/test_harness.sh
# shellcheck disable=SC1091
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init
test_harness_protect_original_path ".config/agent_bootstrap/github.env"
test_harness_protect_original_path ".config/agentbot/github.env"

# shellcheck source=scripts/lib/github_token.sh
source "$REPO_DIR/scripts/lib/github_token.sh"
# shellcheck source=scripts/lib/menu_render.sh
source "$REPO_DIR/scripts/lib/menu_render.sh"
# shellcheck source=scripts/lib/tty.sh
source "$REPO_DIR/scripts/lib/tty.sh"
# shellcheck source=scripts/lib/ui.sh
source "$REPO_DIR/scripts/lib/ui.sh"
ui_init_colors
if [[ -f "$REPO_DIR/scripts/menus/github_token.sh" ]]; then
	# shellcheck source=scripts/menus/github_token.sh
	source "$REPO_DIR/scripts/menus/github_token.sh"
fi
# shellcheck source=scripts/menus/main.sh
source "$REPO_DIR/scripts/menus/main.sh"

passed=0
failed=0
TOKEN_SEQ=0

pass() { printf 'ok - %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; failed=$((failed + 1)); }
expect_success() {
	local name="$1"
	shift
	if "$@"; then pass "$name"; else fail "$name"; fi
}

make_token() {
	local label="${1:-default}"
	TOKEN_SEQ=$((TOKEN_SEQ + 1))
	printf 'ghp_runtime_%s_%024d' "$label" "$TOKEN_SEQ"
}

active_dir() { dirname -- "$(github_token_file)"; }
legacy_file() { printf '%s\n' "$XDG_CONFIG_HOME/agent_bootstrap/github.env"; }

reset_token_state() {
	rm -rf -- "$XDG_CONFIG_HOME/agentbot" "$XDG_CONFIG_HOME/agent_bootstrap"
	unset GITHUB_TOKEN
}

write_raw_file() {
	local file="$1" content="$2" mode="${3:-600}"
	mkdir -p -- "$(dirname -- "$file")"
	chmod 700 "$(dirname -- "$file")"
	printf '%b' "$content" >"$file"
	chmod "$mode" "$file"
}

run_menu_script_capture_stderr() {
	local input="$1" output="$2" stderr="$3"
	printf '%s' "$input" >"$TEST_HARNESS_ROOT/menu.input"
	: >"$output"
	: >"$stderr"
	GITHUB_TOKEN_TTY_INPUT="$TEST_HARNESS_ROOT/menu.input" \
		GITHUB_TOKEN_TTY_OUTPUT="$output" \
		GITHUB_TOKEN_TTY_COLS=80 \
		github_token_menu 2>"$stderr"
}

run_menu_script() {
	local input="$1" output="$2" stderr="$TEST_HARNESS_ROOT/menu.stderr"
	run_menu_script_capture_stderr "$input" "$output" "$stderr" || return 1
	[[ ! -s "$stderr" ]]
}

test_environment_precedence() (
	reset_token_state
	local saved env
	saved="$(make_token saved)"
	env="$(make_token environment)"
	write_raw_file "$(github_token_file)" "GITHUB_TOKEN=${saved}\n"
	export GITHUB_TOKEN="$env"
	github_token_export_if_valid 2>"$TEST_HARNESS_ROOT/env.err" || return 1
	[[ "$GITHUB_TOKEN" == "$env" ]] || return 1
	[[ ! -s "$TEST_HARNESS_ROOT/env.err" ]]
)

test_absent_file_is_silent_optional() (
	reset_token_state
	local value='sentinel'
	github_token_read value 2>"$TEST_HARNESS_ROOT/absent.err" || return 1
	[[ -z "$value" ]] || return 1
	github_token_export_if_valid 2>>"$TEST_HARNESS_ROOT/absent.err" || return 1
	[[ -z "${GITHUB_TOKEN:-}" && ! -s "$TEST_HARNESS_ROOT/absent.err" ]]
)

test_valid_private_file_is_read_without_printing() (
	reset_token_state
	local token value='' stdout="$TEST_HARNESS_ROOT/valid.out" stderr="$TEST_HARNESS_ROOT/valid.err"
	token="$(make_token)"
	write_raw_file "$(github_token_file)" "GITHUB_TOKEN=${token}\n"
	github_token_read value >"$stdout" 2>"$stderr" || return 1
	[[ "$value" == "$token" ]] || return 1
	[[ ! -s "$stdout" && ! -s "$stderr" ]]
)

test_wrong_mode_warns_once_and_continues_anonymously() (
	reset_token_state
	local token value='' stderr="$TEST_HARNESS_ROOT/mode.err"
	token="$(make_token)"
	write_raw_file "$(github_token_file)" "GITHUB_TOKEN=${token}\n" 644
	github_token_read value 2>"$stderr" || return 1
	[[ -z "$value" ]] || return 1
	[[ "$(wc -l <"$stderr")" -eq 1 ]] || return 1
	github_token_export_if_valid 2>"$TEST_HARNESS_ROOT/mode-export.err" || return 1
	[[ -z "${GITHUB_TOKEN:-}" ]]
)

test_strict_parser_rejects_malformed_content_without_execution() (
	reset_token_state
	local token marker="$TEST_HARNESS_ROOT/parser-executed" value content
	token="$(make_token)"
	local cases=(
		"GITHUB_TOKEN=${token}\\nSECOND=value\\n"
		"GH_TOKEN=${token}\\n"
		"GITHUB_TOKEN=\\\$(touch ${marker})\\n"
		" GITHUB_TOKEN=${token}\\n"
		"GITHUB_TOKEN=${token} \\n"
		"GITHUB_TOKEN=short\\n"
		"GITHUB_TOKEN=${token}\\tbad\\n"
		"GITHUB_TOKEN=${token}"
	)
	for content in "${cases[@]}"; do
		value='sentinel'
		write_raw_file "$(github_token_file)" "$content"
		github_token_read value >/dev/null 2>"$TEST_HARNESS_ROOT/parser.err" || return 1
		[[ -z "$value" ]] || return 1
		[[ "$(wc -l <"$TEST_HARNESS_ROOT/parser.err")" -eq 1 ]] || return 1
	done
	[[ ! -e "$marker" ]]
)

test_atomic_private_write_replacement_removal_and_unsafe_rejection() (
	reset_token_state
	local first second external="$TEST_HARNESS_ROOT/external-target" stderr="$TEST_HARNESS_ROOT/write.err"
	first="$(make_token first)"; second="$(make_token second)"
	github_token_write "$first" 2>"$stderr" || return 1
	[[ "$(stat -c %a "$(active_dir)")" == 700 ]] || return 1
	[[ "$(stat -c %a "$(github_token_file)")" == 600 ]] || return 1
	[[ "$(<"$(github_token_file)")" == "GITHUB_TOKEN=$first" ]] || return 1
	[[ -z "$(find "$(active_dir)" -maxdepth 1 -name '.github.env.*' -print -quit)" ]] || return 1
	github_token_write "$second" 2>>"$stderr" || return 1
	[[ "$(<"$(github_token_file)")" == "GITHUB_TOKEN=$second" ]] || return 1
	github_token_remove || return 1
	[[ ! -e "$(github_token_file)" ]] || return 1
	printf 'protected\n' >"$external"
	ln -s -- "$external" "$(github_token_file)"
	! github_token_write "$first" 2>>"$stderr" || return 1
	[[ "$(<"$external")" == protected ]] || return 1
	! github_token_remove 2>>"$stderr" || return 1
	[[ -L "$(github_token_file)" ]]
)

test_legacy_migration_matrix() (
	reset_token_state
	local one two stderr="$TEST_HARNESS_ROOT/migrate.err"
	one="$(make_token one)"; two="$(make_token two)"
	github_token_migrate_legacy 2>"$stderr" || return 1
	[[ ! -e "$(github_token_file)" && ! -s "$stderr" ]] || return 1
	write_raw_file "$(legacy_file)" "GITHUB_TOKEN=${one}\n"
	github_token_migrate_legacy 2>"$stderr" || return 1
	[[ -f "$(github_token_file)" && ! -e "$(legacy_file)" ]] || return 1
	[[ "$(stat -c %a "$(github_token_file)")" == 600 ]] || return 1
	reset_token_state
	write_raw_file "$(github_token_file)" "GITHUB_TOKEN=${one}\n"
	write_raw_file "$(legacy_file)" "GITHUB_TOKEN=${one}\n"
	github_token_migrate_legacy 2>"$stderr" || return 1
	[[ ! -e "$(legacy_file)" ]] || return 1
	reset_token_state
	write_raw_file "$(github_token_file)" "GITHUB_TOKEN=${one}\n"
	write_raw_file "$(legacy_file)" "GITHUB_TOKEN=${two}\n"
	github_token_migrate_legacy 2>"$stderr" || return 1
	[[ -e "$(legacy_file)" ]] || return 1
	[[ "$(<"$(github_token_file)")" == "GITHUB_TOKEN=$one" ]] || return 1
	[[ "$(wc -l <"$stderr")" -eq 1 ]] || return 1
	reset_token_state
	write_raw_file "$(legacy_file)" "GITHUB_TOKEN=short\n"
	github_token_migrate_legacy 2>"$stderr" || return 1
	[[ -e "$(legacy_file)" && ! -e "$(github_token_file)" ]] || return 1
	reset_token_state
	write_raw_file "$(legacy_file)" "GITHUB_TOKEN=${one}\n" 644
	github_token_migrate_legacy 2>"$stderr" || return 1
	[[ -e "$(legacy_file)" && ! -e "$(github_token_file)" ]]
)

test_canary_never_leaks_outside_confirmed_reveal() (
	reset_token_state
	local canary stdout="$TEST_HARNESS_ROOT/canary.out" stderr="$TEST_HARNESS_ROOT/canary.err"
	canary="$(make_token)"
	export TEST_CANARY_SECRET="$canary"
	test_harness_reset_logs
	github_token_write "$canary" >"$stdout" 2>"$stderr" || return 1
	unset GITHUB_TOKEN
	github_token_export_if_valid >>"$stdout" 2>>"$stderr" || return 1
	: >"$TEST_HARNESS_ROOT/git.log"
	if grep -FR -- "$canary" "$stdout" "$stderr" "$TEST_COMMAND_LOG" "$TEST_URL_LOG" "$TEST_HARNESS_ROOT/git.log"; then
		return 1
	fi
	unset TEST_CANARY_SECRET GITHUB_TOKEN
)

test_visible_entry_requires_save_confirmation() (
	reset_token_state
	local token output="$TEST_HARNESS_ROOT/no-save.menu"
	token="$(make_token)"
	run_menu_script $'s\n'"${token}"$'\nn\nq\n' "$output" || return 1
	[[ ! -e "$(github_token_file)" ]] || return 1
	grep -Fq 'Input is visible' "$output" || return 1
	! grep -Fq "$token" "$output"
)

test_menu_save_cancel_remove_and_q_state_machine() (
	reset_token_state
	local token output="$TEST_HARNESS_ROOT/state.menu"
	token="$(make_token)"
	run_menu_script $'s\n'"${token}"$'\ny\nq\n' "$output" || return 1
	[[ -f "$(github_token_file)" ]] || return 1
	local before
	before="$(<"$(github_token_file)")"
	run_menu_script $'s\nq\nq\n' "$output" || return 1
	[[ "$(<"$(github_token_file)")" == "$before" ]] || return 1
	run_menu_script $'d\nn\nq\n' "$output" || return 1
	[[ -f "$(github_token_file)" ]] || return 1
	run_menu_script $'d\ny\nq\n' "$output" || return 1
	[[ ! -e "$(github_token_file)" ]] || return 1
	run_menu_script $'q\n' "$output"
)

test_fingerprint_and_warned_one_time_reveal() (
	reset_token_state
	local token fingerprint output="$TEST_HARNESS_ROOT/reveal.menu"
	token="$(make_token)"
	github_token_write "$token" || return 1
	fingerprint="$(github_token_fingerprint "$token")"
	[[ -n "$fingerprint" && "$fingerprint" != "$token" && "$fingerprint" == *"${token: -4}"* ]] || return 1
	run_menu_script $'r\nn\nq\n' "$output" || return 1
	grep -Fq 'WARNING' "$output" || return 1
	! grep -Fq "$token" "$output" || return 1
	run_menu_script $'r\ny\n\nq\n' "$output" || return 1
	[[ "$(grep -Foc "$token" "$output")" -eq 1 ]] || return 1
	grep -Fq 'Press Enter to continue' "$output"
)

test_menu_presentation_is_complete() (
	reset_token_state
	local output="$TEST_HARNESS_ROOT/presentation.menu"
	run_menu_script $'q\n' "$output" || return 1
	grep -Fq '=== GitHub Token Config ===' "$output" || return 1
	grep -Fq 'Dotfiles › GitHub Token Config' "$output" || return 1
	grep -Fq "$(github_token_file)" "$output" || return 1
	grep -Fqi 'optional' "$output" || return 1
	grep -Fqi 'public-repository API rate limits' "$output" || return 1
	grep -Fqi 'no repository scopes' "$output"
)

test_invalid_saved_state_warns_once_per_menu_session() (
	local token output="$TEST_HARNESS_ROOT/invalid-session.menu"
	local stderr="$TEST_HARNESS_ROOT/invalid-session.err" content mode
	token="$(make_token invalid-session)"
	for content in 'GITHUB_TOKEN=short\n' "GITHUB_TOKEN=${token}\n"; do
		if [[ "$content" == 'GITHUB_TOKEN=short\n' ]]; then mode=600; else mode=644; fi
		reset_token_state
		write_raw_file "$(github_token_file)" "$content" "$mode"
		run_menu_script_capture_stderr $'x\nr\nq\n' "$output" "$stderr" || return 1
		[[ "$(wc -l <"$stderr")" -eq 1 ]] || return 1
		grep -Fq 'Warning:' "$stderr" || return 1
		grep -Fq 'No valid saved token is available to reveal.' "$output" || return 1
		run_menu_script_capture_stderr $'q\n' "$output" "$stderr" || return 1
		[[ "$(wc -l <"$stderr")" -eq 1 ]] || return 1
	done
)

test_migration_and_export_consolidate_target_warning_per_attempt() (
	reset_token_state
	local legacy_token stderr="$TEST_HARNESS_ROOT/consolidated.err"
	legacy_token="$(make_token legacy_warning)"
	write_raw_file "$(legacy_file)" "GITHUB_TOKEN=${legacy_token}\n"
	write_raw_file "$(github_token_file)" 'GITHUB_TOKEN=short\n'
	github_token_migrate_legacy 2>"$stderr" || return 1
	[[ "$(wc -l <"$stderr")" -eq 1 ]] || return 1
	[[ -e "$(legacy_file)" ]] || return 1
	unset GITHUB_TOKEN
	github_token_export_if_valid 2>"$stderr" || return 1
	[[ "$(wc -l <"$stderr")" -eq 1 ]] || return 1
	[[ -z "${GITHUB_TOKEN:-}" ]] || return 1
	unset GITHUB_TOKEN
	github_token_export_if_valid 2>"$stderr" || return 1
	[[ "$(wc -l <"$stderr")" -eq 1 ]]
)

test_original_home_token_paths_remain_unchanged() (
	test_harness_verify_protected_paths
)

test_root_hook_reaches_token_menu_without_reordering() (
	reset_token_state
	local before_labels="${_main_menu_labels[*]}" before_keys="${_main_menu_keys[*]}"
	local output="$TEST_HARNESS_ROOT/root-token.menu" stderr="$TEST_HARNESS_ROOT/root-token.err" pauses=0
	printf 'q\n' >"$TEST_HARNESS_ROOT/menu.input"
	: >"$stderr"
	ui_pause() { pauses=$((pauses + 1)); }
	GITHUB_TOKEN_TTY_INPUT="$TEST_HARNESS_ROOT/menu.input" \
		GITHUB_TOKEN_TTY_OUTPUT="$output" \
		GITHUB_TOKEN_TTY_COLS=80 \
		_main_menu_dispatch github_token 2>"$stderr" || return 1
	[[ ! -s "$stderr" ]] || return 1
	[[ "$pauses" -eq 0 ]] || return 1
	[[ "${_main_menu_labels[*]}" == "$before_labels" ]] || return 1
	[[ "${_main_menu_keys[*]}" == "$before_keys" ]]
)

expect_success 'valid environment token wins over saved state' test_environment_precedence
expect_success 'absent saved token is silent anonymous fallback' test_absent_file_is_silent_optional
expect_success 'valid private one-line file reads without output' test_valid_private_file_is_read_without_printing
expect_success 'wrong mode warns once and continues anonymously' test_wrong_mode_warns_once_and_continues_anonymously
expect_success 'strict parser rejects malformed content without execution' test_strict_parser_rejects_malformed_content_without_execution
expect_success 'atomic private write, replacement, removal, and unsafe rejection work' test_atomic_private_write_replacement_removal_and_unsafe_rejection
expect_success 'legacy migration handles absent, valid, identical, conflict, and unsafe states' test_legacy_migration_matrix
expect_success 'canary is absent outside confirmed reveal output' test_canary_never_leaks_outside_confirmed_reveal
expect_success 'visible entry does not write before save confirmation' test_visible_entry_requires_save_confirmation
expect_success 'menu save, entry cancel, remove confirm/cancel, and q preserve state' test_menu_save_cancel_remove_and_q_state_machine
expect_success 'existing token is fingerprinted and Reveal is warned, confirmed, and one-time' test_fingerprint_and_warned_one_time_reveal
expect_success 'token screen header, breadcrumb, path, and optional no-scope copy are complete' test_menu_presentation_is_complete
expect_success 'invalid saved state warns once across menu redraw and Reveal per session' test_invalid_saved_state_warns_once_per_menu_session
expect_success 'migration and export consolidate one bad-target warning per attempt' test_migration_and_export_consolidate_target_warning_per_attempt
expect_success 'root github_token hook reaches screen without reorder or extra pause' test_root_hook_reaches_token_menu_without_reordering
expect_success 'original-home legacy and active token paths remain unchanged' test_original_home_token_paths_remain_unchanged

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
