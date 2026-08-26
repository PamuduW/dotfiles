#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# Architecture fitness rules.
#
# These are structural assertions, not behavior: they grep the source to keep
# one implementation of a thing where there should be one. They are grouped
# here on purpose, because a refactor that moves code will trip them and the
# right response is usually to update the rule, not to delete it.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

test_repository_update_has_no_reload_hook() (
	! declare -F repo_update_wait_for_reload >/dev/null 2>&1
	! declare -F repo_update_relaunch >/dev/null 2>&1
)

test_terminal_device_access_is_centralized() (
	! rg -n '/dev/tty' "$REPO_DIR/scripts" "$REPO_DIR/bin/bin/dotfiles" \
		--glob '!**/shared/tui/tty.sh' --glob '!tests/**'
)

test_dotfiles_cli_is_a_thin_adapter_over_update_modules() (
	[[ -f "$REPO_DIR/scripts/lib/update_components.sh" ]]
	[[ -f "$REPO_DIR/scripts/lib/update_workflow.sh" ]]
	(("$(wc -l <"$REPO_DIR/bin/bin/dotfiles")" < 400))
	! rg -n '^(install_lazygit_from_github|install_lazydocker_from_github|install_monaspace_fonts|_repo_update_change_count|_repo_update_history_detail)\(\)' \
		"$REPO_DIR/bin/bin/dotfiles"
)

test_read_only_cli_commands_do_not_load_mutating_modules() (
	local command trace
	for command in help status; do
		trace="$TEST_HARNESS_ROOT/${command}.source-trace"
		NO_COLOR=1 COMP_PROBE_TIMEOUT_SECONDS=0.2 \
			bash -x "$REPO_DIR/bin/bin/dotfiles" "$command" >/dev/null 2>"$trace" || {
			[[ "$command" == status ]] || return 1
		}
		! rg -n '^\+ source .*/scripts/lib/(update[^/]*|updates/|full_update|installers/)' "$trace" || return 1
	done
)

test_four_column_table_layout_has_one_shared_implementation() (
	rg -q '^rt_print_four_column_header\(\)' "$REPO_DIR/scripts/lib/shared/tui/report_table.sh"
	rg -q '^rt_print_four_column_row\(\)' "$REPO_DIR/scripts/lib/shared/tui/report_table.sh"
	! rg -n '^(_update|_repo_update)_(fit_text|table_rule|print_plain_cell|print_colored_cell)\(\)' \
		"$REPO_DIR/scripts/lib/update_workflow.sh" "$REPO_DIR/scripts/lib/repo_update.sh"
)

test_single_repository_install_and_update_use_one_runner() (
	declare -F repo_update_run >/dev/null
	[[ "$(declare -f _dotfiles_install_repo_gate)" == *repo_update_run* ]]
	[[ "$(declare -f _dotfiles_run_update)" == *repo_update_run* ]]
	[[ "$(declare -f cmd_update)" == *_dotfiles_run_update* ]]
)

test_repository_has_one_validation_entrypoint_and_ci() (
	[[ -x "$REPO_DIR/tests/run.sh" && -x "$REPO_DIR/scripts/validate.sh" ]]
	rg -q 'test_\*\.sh' "$REPO_DIR/tests/run.sh"
	rg -q 'scripts/validate.sh' "$REPO_DIR/.github/workflows/validate.yml"
)

test_installer_help_exits_before_log_initialization() (
	local help_line log_line probe_dir
	help_line="$(rg -n '^if \[\[.*(--help|-h)' "$REPO_DIR/scripts/install.sh" | head -n1 | cut -d: -f1)"
	log_line="$(rg -n 'source .*scripts/lib/action_log\.sh' "$REPO_DIR/scripts/install.sh" | head -n1 | cut -d: -f1)"
	[[ -n "$help_line" && -n "$log_line" && "$help_line" -lt "$log_line" ]] || return 1

	# Loading the library must not create anything; only start_action_log may.
	probe_dir="$TEST_HARNESS_ROOT/action-log-probe"
	mkdir -p "$probe_dir"
	(
		DOTFILES_DIR="$probe_dir"
		# shellcheck source=scripts/lib/action_log.sh
		source "$REPO_DIR/scripts/lib/action_log.sh"
	)
	[[ ! -e "$probe_dir/log" ]]
)

check 'repository update has no reload hook' test_repository_update_has_no_reload_hook
check 'all terminal device access goes through the shared TTY adapter' test_terminal_device_access_is_centralized
check 'dotfiles CLI is a thin adapter over shared update modules' test_dotfiles_cli_is_a_thin_adapter_over_update_modules
check 'read-only CLI commands do not load mutating modules' test_read_only_cli_commands_do_not_load_mutating_modules
check 'four-column reports share one ANSI-safe table layout implementation' test_four_column_table_layout_has_one_shared_implementation
check 'Dotfiles install and update use the same repository runner' test_single_repository_install_and_update_use_one_runner
check 'repository has one local validation entrypoint wired into CI' test_repository_has_one_validation_entrypoint_and_ci
check 'installer help exits before log initialization' test_installer_help_exits_before_log_initialization

test_harness_cleanup
finish_tests
