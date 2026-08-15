#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

passed=0
failed=0
pass() {
	printf 'ok - %s\n' "$1"
	passed=$((passed + 1))
}
fail() {
	printf 'not ok - %s\n' "$1" >&2
	failed=$((failed + 1))
}
check() {
	local name="$1"
	shift
	if "$@"; then pass "$name"; else fail "$name"; fi
}

source "$REPO_DIR/scripts/lib/tty.sh"
source "$REPO_DIR/scripts/lib/menu_render.sh"
source "$REPO_DIR/scripts/lib/repo_update.sh"
source "$REPO_DIR/scripts/lib/wsl_conf.sh"
source "$REPO_DIR/scripts/lib/components/registry.sh"
source "$REPO_DIR/scripts/lib/components/probes.sh"
source "$REPO_DIR/scripts/lib/installers/stow.sh"
source "$REPO_DIR/scripts/lib/components/install_dispatch.sh"
DOTFILES_DIR="$REPO_DIR"
source "$REPO_DIR/scripts/menus/initial_setup.sh"
source "$REPO_DIR/scripts/menus/agentbot.sh"
source "$REPO_DIR/scripts/lib/update_components.sh"
source "$REPO_DIR/scripts/lib/update_workflow.sh"

test_repository_approval_uses_explicit_event_contract() (
	declare -A state=(
		[state]=behind
		[behind]=2
		[label]='dotfiles repo'
		[dir]="$REPO_DIR"
		[safe]=1
		[dirty]=0
		[upstream]=origin/main
		[approved]=0
	)
	decision() {
		[[ "$1" == pull-behind ]] || return 1
		[[ "$2" == 'Pull 2 commit(s) with --ff-only?' ]]
	}
	repo_update_request_approval state decision >/dev/null
	[[ "${state[approved]}" == 1 ]]
)

test_agentbot_preflights_both_repositories_before_approval_or_apply() (
	local events="$TEST_HARNESS_ROOT/agentbot-update-order"
	: >"$events"
	AGENTBOT_HOME="$TEST_HARNESS_ROOT/agentbot-home"
	mkdir -p "$AGENTBOT_HOME"
	repo_update_preflight() {
		local _dir="$1" label="$2" result_name="$3"
		local -n result_ref="$result_name"
		result_ref=([dir]="$_dir" [label]="$label" [state]=current [safe]=1 [approved]=1 [outcome]=current)
		printf 'preflight:%s\n' "$label" >>"$events"
	}
	repo_update_request_approval() {
		local -n result_ref="$1"
		printf 'approval:%s\n' "${result_ref[label]}" >>"$events"
	}
	repo_update_apply() {
		local -n result_ref="$1"
		printf 'apply:%s\n' "${result_ref[label]}" >>"$events"
	}
	dotfiles_agentbot_update_all
	mapfile -t actual <"$events"
	[[ "${actual[0]}" == 'preflight:dotfiles repo' ]]
	[[ "${actual[1]}" == 'preflight:agentbot repo' ]]
	[[ "${actual[2]}" == approval:* ]]
)

test_reload_wait_is_noop_without_a_tty() (
	DOTFILES_TTY_INPUT="$TEST_HARNESS_ROOT/missing-input"
	DOTFILES_TTY_OUTPUT="$TEST_HARNESS_ROOT/missing-output/tty"
	local errors="$TEST_HARNESS_ROOT/no-tty-errors"
	repo_update_wait_for_reload 2>"$errors"
	[[ ! -s "$errors" ]]
)

test_terminal_geometry_is_quiet_without_a_tty() (
	DOTFILES_TTY_INPUT="$TEST_HARNESS_ROOT/missing-geometry-input"
	DOTFILES_TTY_OUTPUT="$TEST_HARNESS_ROOT/missing-geometry-output"
	local errors="$TEST_HARNESS_ROOT/geometry-errors" cols
	cols="$(menu_tty_cols 2>"$errors")"
	[[ "$cols" =~ ^[0-9]+$ && ! -s "$errors" ]]
)

test_noninteractive_install_runs_repository_gate_first() (
	local events="$TEST_HARNESS_ROOT/noninteractive-install-order"
	: >"$events"
	DOTFILES_INTERACTIVE_TTY=false
	_dotfiles_install_repo_gate() { printf 'gate\n' >>"$events"; }
	apply_dotfiles_components_env() { printf 'components\n' >>"$events"; }
	_apply_noninteractive_git_defaults() { :; }
	_run_setup_header() { :; }
	show_plan() { :; }
	run_install() { printf 'install\n' >>"$events"; }
	run_initial_setup_flow
	[[ "$(<"$events")" == $'gate\ncomponents\ninstall' ]]
)

test_python_probe_requires_python_pip_and_venv() (
	local fake_bin="$TEST_HARNESS_ROOT/python-empty-bin"
	mkdir -p "$fake_bin"
	local output
	output="$(PATH="$fake_bin" _comp_probe_python)"
	[[ "$output" == missing\|* ]]
)

test_go_probe_does_not_treat_empty_asdf_as_installed() (
	local fake_bin="$TEST_HARNESS_ROOT/go-empty-bin"
	mkdir -p "$fake_bin"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/asdf"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$fake_bin/go"
	chmod +x "$fake_bin/asdf" "$fake_bin/go"
	local output
	output="$(PATH="$fake_bin:/usr/bin:/bin" _comp_probe_go)"
	[[ "$output" == missing\|* ]]
)

test_dotfiles_probe_requires_every_managed_link() (
	local fake_home="$TEST_HARNESS_ROOT/partial-dotfiles-home"
	mkdir -p "$fake_home/bin"
	: >"$fake_home/bin/ex"
	local output
	output="$(HOME="$fake_home" _comp_probe_dotfiles)"
	[[ "$output" == missing\|* || "$output" == check\|* ]]
)

test_wsl_probe_requires_both_settings() (
	local conf="$TEST_HARNESS_ROOT/wsl.conf"
	printf '[boot]\nsystemd=true\n' >"$conf"
	local output
	output="$(DOTFILES_WSL_CONF="$conf" _comp_probe_wsl_conf)"
	[[ "$output" == check\|* ]]
)

test_component_registry_validates_dependencies_and_install_order() (
	comp_registry_validate
)

test_absent_optional_components_are_counted_as_missing() (
	local fake_home="$TEST_HARNESS_ROOT/absent-components-home"
	local git_config="$TEST_HARNESS_ROOT/empty-gitconfig"
	mkdir -p "$fake_home"
	: >"$git_config"
	[[ "$(HOME="$fake_home" GIT_CONFIG_GLOBAL="$git_config" GIT_CONFIG_NOSYSTEM=1 _comp_probe_git_identity)" == missing\|* ]]
	[[ "$(HOME="$fake_home" _comp_probe_ssh_key)" == missing\|* ]]
)

test_backup_includes_existing_dotfiles_launcher() (
	local fake_home="$TEST_HARNESS_ROOT/stow-home"
	local fake_repo="$TEST_HARNESS_ROOT/stow-repo"
	mkdir -p "$fake_home/bin" "$fake_repo"
	printf 'old launcher\n' >"$fake_home/bin/dotfiles"
	log_step() { :; }
	log_ok() { :; }
	HOME="$fake_home" DOTFILES_DIR="$fake_repo" backup_existing_dotfiles
	[[ ! -e "$fake_home/bin/dotfiles" ]]
	find "$fake_repo" -path '*/bin/dotfiles' -type f -print -quit | grep -q .
)

test_failed_stow_restores_backed_up_user_files() (
	local fake_home="$TEST_HARNESS_ROOT/stow-rollback-home"
	local fake_repo="$TEST_HARNESS_ROOT/stow-rollback-repo"
	mkdir -p "$fake_home/bin" "$fake_repo"
	printf 'user bashrc\n' >"$fake_home/.bashrc"
	printf 'user launcher\n' >"$fake_home/bin/dotfiles"
	log_step() { :; }
	log_ok() { :; }
	stow() { return 23; }
	HOME="$fake_home" DOTFILES_DIR="$fake_repo" backup_existing_dotfiles
	if HOME="$fake_home" DOTFILES_DIR="$fake_repo" stow_dotfiles >/dev/null 2>&1; then return 1; fi
	[[ "$(<"$fake_home/.bashrc")" == 'user bashrc' ]]
	[[ "$(<"$fake_home/bin/dotfiles")" == 'user launcher' ]]
)

test_update_all_calls_supported_command() (
	local calls="$TEST_HARNESS_ROOT/update-all-calls"
	: >"$calls"
	dotfiles() { printf '%s\n' "$*" >>"$calls"; }
	DOTFILES_DIR="$REPO_DIR"
	source "$REPO_DIR/bash/.bash_aliases"
	update-all
	[[ "$(<"$calls")" == 'update --all' ]]
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

test_selected_component_install_failures_propagate() (
	install_graphify_cli() { return 23; }
	set +e
	_comp_install_graphify_cli >/dev/null
	local rc=$?
	set -e
	[[ "$rc" == 23 ]]
)

test_install_orchestrator_collects_failures_and_finishes_selected_work() (
	local calls="$TEST_HARNESS_ROOT/install-failure-calls"
	: >"$calls"
	COMP_INSTALL_ORDER=(first second)
	declare -gA COMP_ON=([first]=1 [second]=1)
	LOG_FILE="$TEST_HARNESS_ROOT/install.log"
	is_on() { [[ "${COMP_ON[$1]}" == 1 ]]; }
	_run_install_preamble() { :; }
	_log_legend_line() { :; }
	print_install_summary() { printf 'summary\n' >>"$calls"; }
	log_warn() { :; }
	comp_install() {
		printf '%s\n' "$1" >>"$calls"
		[[ "$1" != first ]]
	}
	set +e
	run_install >/dev/null
	local rc=$?
	set -e
	[[ "$rc" == 1 ]] || return 1
	[[ "$(<"$calls")" == $'first\nsecond\nsummary' ]]
)

test_terminal_device_access_is_centralized() (
	! rg -n '/dev/tty' "$REPO_DIR/scripts" "$REPO_DIR/bin/bin/dotfiles" \
		--glob '!**/lib/tty.sh' --glob '!tests/**'
)

test_dotfiles_cli_is_a_thin_adapter_over_update_modules() (
	[[ -f "$REPO_DIR/scripts/lib/update_components.sh" ]]
	[[ -f "$REPO_DIR/scripts/lib/update_workflow.sh" ]]
	(("$(wc -l <"$REPO_DIR/bin/bin/dotfiles")" < 400))
	! rg -n '^(install_lazygit_from_github|install_lazydocker_from_github|install_monaspace_fonts|_repo_update_change_count|_repo_update_history_detail)\(\)' \
		"$REPO_DIR/bin/bin/dotfiles"
)

test_four_column_table_layout_has_one_shared_implementation() (
	rg -q '^rt_print_four_column_header\(\)' "$REPO_DIR/scripts/lib/report_table.sh"
	rg -q '^rt_print_four_column_row\(\)' "$REPO_DIR/scripts/lib/report_table.sh"
	! rg -n '^(_update|_repo_update)_(fit_text|table_rule|print_plain_cell|print_colored_cell)\(\)' \
		"$REPO_DIR/scripts/lib/update_workflow.sh" "$REPO_DIR/scripts/lib/repo_update.sh"
)

test_single_repository_install_and_update_use_one_runner() (
	declare -F repo_update_run >/dev/null
	[[ "$(declare -f _dotfiles_install_repo_gate)" == *repo_update_run* ]]
	[[ "$(declare -f cmd_update)" == *repo_update_run* ]]
)

test_update_probes_find_vendor_local_bin_installations() (
	local local_bin="$HOME/.local/bin" output
	mkdir -p "$local_bin"
	printf '#!/usr/bin/env bash\nprintf "cursor-local\\n"\n' >"$local_bin/agent"
	printf '#!/usr/bin/env bash\nprintf "claude-local\\n"\n' >"$local_bin/claude"
	chmod +x "$local_bin/agent" "$local_bin/claude"
	output="$(PATH="$TEST_FAKE_BIN:/usr/bin:/bin" cursor_installed_version)"
	[[ "$output" == cursor-local ]] || return 1
	output="$(PATH="$TEST_FAKE_BIN:/usr/bin:/bin" claude_installed_version)"
	[[ "$output" == claude-local ]]
)

test_monaspace_upgrade_requests_a_replacement_install() (
	[[ "$(declare -f upgrade_monaspace)" == *'install_monaspace_fonts --replace'* ]]
)

test_remote_shell_installers_are_downloaded_before_execution() (
	! rg -n 'curl[^|]*\|[[:space:]]*(bash|sh)' "$REPO_DIR/scripts/lib/installers" "$REPO_DIR/scripts/lib/update_components.sh"
)

test_portainer_uses_an_explicit_image_version() (
	! rg -n 'portainer/portainer-ce:latest' "$REPO_DIR/scripts/lib/installers/docker.sh"
	rg -q 'PORTAINER_IMAGE' "$REPO_DIR/scripts/lib/installers/docker.sh"
)

test_wsl_config_renderer_updates_only_the_requested_section() (
	local conf="$TEST_HARNESS_ROOT/wsl-render.conf" rendered="$TEST_HARNESS_ROOT/wsl-rendered.conf"
	printf '%s\n' '[interop]' 'systemd=true' 'appendWindowsPath=false' '' '[boot]' 'appendWindowsPath=true' >"$conf"
	wsl_conf_render_required "$conf" >"$rendered"
	wsl_conf_has_setting "$rendered" boot systemd true || return 1
	wsl_conf_has_setting "$rendered" interop appendWindowsPath true || return 1
	grep -Fqx 'systemd=true' "$rendered"
)

test_repository_has_one_validation_entrypoint_and_ci() (
	[[ -x "$REPO_DIR/tests/run.sh" && -x "$REPO_DIR/scripts/validate.sh" ]]
	rg -q 'test_\*\.sh' "$REPO_DIR/tests/run.sh"
	rg -q 'scripts/validate.sh' "$REPO_DIR/.github/workflows/validate.yml"
)

test_installer_help_exits_before_log_initialization() (
	local help_line log_line
	help_line="$(rg -n '^if \[\[.*(--help|-h)' "$REPO_DIR/scripts/install.sh" | head -n1 | cut -d: -f1)"
	log_line="$(rg -n '^LOG_DIR=' "$REPO_DIR/scripts/install.sh" | cut -d: -f1)"
	[[ -n "$help_line" && -n "$log_line" && "$help_line" -lt "$log_line" ]]
)

check 'repository approval uses explicit event and prompt arguments' test_repository_approval_uses_explicit_event_contract
check 'Agentbot preflights both repositories before approval or mutation' test_agentbot_preflights_both_repositories_before_approval_or_apply
check 'repository reload wait is safe without a controlling TTY' test_reload_wait_is_noop_without_a_tty
check 'terminal geometry falls back quietly without a controlling TTY' test_terminal_geometry_is_quiet_without_a_tty
check 'non-interactive install runs the repository gate before setup' test_noninteractive_install_runs_repository_gate_first
check 'Python probe verifies interpreter pip and venv support' test_python_probe_requires_python_pip_and_venv
check 'Go probe rejects an asdf installation without a selected Go version' test_go_probe_does_not_treat_empty_asdf_as_installed
check 'Dotfiles probe requires every managed Stow target' test_dotfiles_probe_requires_every_managed_link
check 'WSL probe verifies both required settings' test_wsl_probe_requires_both_settings
check 'component registry validates dependencies and installation order' test_component_registry_validates_dependencies_and_install_order
check 'absent optional components remain visible in status rollups' test_absent_optional_components_are_counted_as_missing
check 'Stow backup includes an existing dotfiles launcher' test_backup_includes_existing_dotfiles_launcher
check 'failed Stow application restores backed-up user files' test_failed_stow_restores_backed_up_user_files
check 'update-all calls dotfiles update --all' test_update_all_calls_supported_command
check '.bashrc registers the Dotfiles prompt hook only once' test_bashrc_registers_prompt_hook_once
check 'selected component installer failures propagate to the orchestrator' test_selected_component_install_failures_propagate
check 'install orchestration reports failures after attempting all selected components' test_install_orchestrator_collects_failures_and_finishes_selected_work
check 'all terminal device access goes through the shared TTY adapter' test_terminal_device_access_is_centralized
check 'dotfiles CLI is a thin adapter over shared update modules' test_dotfiles_cli_is_a_thin_adapter_over_update_modules
check 'four-column reports share one ANSI-safe table layout implementation' test_four_column_table_layout_has_one_shared_implementation
check 'Dotfiles install and update use the same repository runner' test_single_repository_install_and_update_use_one_runner
check 'update probes find Cursor and Claude in the vendor local bin directory' test_update_probes_find_vendor_local_bin_installations
check 'Monaspace upgrades replace an older installed release' test_monaspace_upgrade_requests_a_replacement_install
check 'remote shell installers are downloaded before execution' test_remote_shell_installers_are_downloaded_before_execution
check 'Portainer uses an explicit image version' test_portainer_uses_an_explicit_image_version
check 'WSL config rendering updates settings only in their required sections' test_wsl_config_renderer_updates_only_the_requested_section
check 'repository has one local validation entrypoint wired into CI' test_repository_has_one_validation_entrypoint_and_ci
check 'installer help exits before log initialization' test_installer_help_exits_before_log_initialization

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
test_harness_cleanup
((failed == 0))
