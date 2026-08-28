#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# The stowed shell configuration and the action log.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

test_update_all_calls_supported_command() (
	local calls="$TEST_HARNESS_ROOT/update-all-calls"
	: >"$calls"
	dotfiles() { printf '%s\n' "$*" >>"$calls"; }
	DOTFILES_DIR="$REPO_DIR"
	source "$REPO_DIR/bash/.bash_aliases"
	update-all
	[[ "$(<"$calls")" == 'update --all' ]]
)

test_update_codex_routes_through_dotfiles_update() (
	DOTFILES_DIR="$REPO_DIR"
	source "$REPO_DIR/bash/.bash_aliases"
	[[ "$(alias update-codex)" == "alias update-codex='dotfiles update'" ]]
)

test_bashrc_registers_prompt_hook_once() (
	local fake_home="$TEST_HARNESS_ROOT/bashrc-home"
	local fake_bin="$TEST_HARNESS_ROOT/bashrc-bin"
	local command_name output count
	mkdir -p "$fake_home" "$fake_bin"
	for command_name in fzf zoxide direnv; do
		printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/$command_name"
		chmod +x "$fake_bin/$command_name"
	done
	output="$(HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" timeout 5 \
		bash --noprofile --norc -ic "source '$REPO_DIR/bash/.bashrc'; source '$REPO_DIR/bash/.bashrc'; declare -p PROMPT_COMMAND" 2>/dev/null)"
	count="$(grep -o '__dotfiles_prompt_command' <<<"$output" | wc -l | tr -d ' ')"
	[[ "$count" == 1 ]]
)

test_codex_shortcuts_use_exact_approval_contracts() (
	local fake_home="$TEST_HARNESS_ROOT/shortcut-home"
	local fake_bin="$TEST_HARNESS_ROOT/shortcut-bin"
	local work_dir="$TEST_HARNESS_ROOT/project with spaces"
	local calls="$TEST_HARNESS_ROOT/codex-shortcut.calls"
	local command_name host_line token
	mkdir -p "$fake_home" "$fake_bin" "$work_dir"
	: >"$calls"
	for command_name in fzf zoxide direnv; do
		printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/$command_name"
		chmod +x "$fake_bin/$command_name"
	done
	export TEST_BASHRC="$REPO_DIR/bash/.bashrc" TEST_SHORTCUT_DIR="$work_dir" TEST_CODEX_CALLS="$calls"
	# shellcheck disable=SC2016  # Variables expand inside the child interactive shell.
	HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" timeout 5 bash --noprofile --norc -ic '
		source "$TEST_BASHRC"
		codex() {
			printf "%s" "$TEST_CALL_LABEL" >>"$TEST_CODEX_CALLS"
			printf "|%s" "$@" >>"$TEST_CODEX_CALLS"
			printf "\n" >>"$TEST_CODEX_CALLS"
		}
		cd -- "$TEST_SHORTCUT_DIR"
		TEST_CALL_LABEL=codex-safe codex-safe --user-flag "two words"
		TEST_CALL_LABEL=codex-host codex-host --user-flag "two words"
	' 2>/dev/null

	[[ "$(sed -n '1p' "$calls")" == "codex-safe|-C|$work_dir|-s|workspace-write|-a|on-request|--user-flag|two words" ]] || return 1
	host_line="$(sed -n '2p' "$calls")"
	[[ "$host_line" == "codex-host|-C|$work_dir|--approve-for-me|--user-flag|two words" ]] || return 1
	for token in -s --sandbox -a --ask-for-approval danger-full-access on-request; do
		[[ "|$host_line|" != *"|$token|"* ]] || return 1
	done
)

test_action_log_retains_only_the_newest_logs() (
	local probe_dir i
	probe_dir="$TEST_HARNESS_ROOT/action-log-retention"
	mkdir -p "$probe_dir/log"
	for i in $(seq -w 1 25); do
		: >"$probe_dir/log/2026-01-01_00-00-${i}.log"
	done
	: >"$probe_dir/log/orphan.log.raw"
	(
		DOTFILES_DIR="$probe_dir"
		DOTFILES_LOG_RETAIN=20
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
		_prune_action_logs
	)
	[[ "$(find "$probe_dir/log" -maxdepth 1 -name '*.log' | wc -l)" -eq 20 ]] || return 1
	[[ ! -e "$probe_dir/log/orphan.log.raw" ]] || return 1
	# Retention keeps the newest names, so the oldest must be the ones dropped.
	[[ -e "$probe_dir/log/2026-01-01_00-00-25.log" ]] || return 1
	[[ ! -e "$probe_dir/log/2026-01-01_00-00-01.log" ]]
)

check 'update-all calls dotfiles update --all' test_update_all_calls_supported_command
check 'update-codex routes through the guarded Dotfiles update workflow' test_update_codex_routes_through_dotfiles_update
check '.bashrc registers the Dotfiles prompt hook only once' test_bashrc_registers_prompt_hook_once
check 'Codex shortcuts use exact safe and automatic-approval argv contracts' test_codex_shortcuts_use_exact_approval_contracts
check 'action log retains only the newest logs and clears orphaned captures' test_action_log_retains_only_the_newest_logs

test_harness_cleanup
finish_tests
