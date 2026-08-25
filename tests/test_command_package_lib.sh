#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Dynamic sources and indirect negative-test doubles.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=tests/lib/harness.sh
# shellcheck disable=SC1091
source "$TEST_DIR/lib/harness.sh"
test_harness_init

NO_COLOR=1
export NO_COLOR
PKG_FILE="$REPO_DIR/packages/packages.txt"
export PKG_FILE

# Source the read-only presentation and component metadata dependencies.
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/lib/shared/tui/menu_render.sh"
source "$REPO_DIR/scripts/lib/shared/tui/tty.sh"
source "$REPO_DIR/scripts/lib/shared/tui/report_table.sh"
source "$REPO_DIR/scripts/lib/shared/tui/ui.sh"
source "$REPO_DIR/scripts/lib/shared/tui/menu_paging.sh"
source "$REPO_DIR/scripts/lib/components/registry.sh"
source "$REPO_DIR/scripts/lib/components/probes.sh"
ui_init_colors

[[ -f "$REPO_DIR/scripts/lib/command_metadata.sh" ]] && source "$REPO_DIR/scripts/lib/command_metadata.sh"
[[ -f "$REPO_DIR/scripts/menus/command_lib.sh" ]] && source "$REPO_DIR/scripts/menus/command_lib.sh"
[[ -f "$REPO_DIR/scripts/menus/package_lib.sh" ]] && source "$REPO_DIR/scripts/menus/package_lib.sh"

test_harness_report_init

count_exact_line() {
	local expected="$1" file="$2"
	awk -v expected="$expected" '$0 == expected { count++ } END { print count + 0 }' "$file"
}

test_authoritative_command_metadata() {
	declare -F dotfiles_command_metadata_validate >/dev/null || return 1
	dotfiles_command_metadata_validate || return 1
	local expected=(menu update full-update doctor status commands packages logs restow help)
	[[ "${#DOTFILES_COMMAND_KEYS[@]}" -eq "${#expected[@]}" ]] || return 1
	local i key class
	for i in "${!expected[@]}"; do
		key="${expected[$i]}"
		[[ "${DOTFILES_COMMAND_KEYS[$i]}" == "$key" ]] || return 1
		class="${DOTFILES_COMMAND_CLASS[$key]:-}"
		[[ "$class" == read-only || "$class" == mutating ]] || return 1
		[[ -n "${DOTFILES_COMMAND_DESCRIPTION[$key]:-}" ]] || return 1
	done
	[[ "${DOTFILES_COMMAND_CLASS[status]}" == read-only ]]
}

test_removed_commands_report_migration_guidance() {
	local command output rc
	for command in summary upgrade self; do
		set +e
		output="$("$REPO_DIR/bin/bin/dotfiles" "$command" 2>&1)"
		rc=$?
		set -e
		[[ "$rc" -ne 0 ]] || return 1
		case "$command" in
		summary) [[ "$output" == *'dotfiles status'* ]] ;;
		upgrade) [[ "$output" == *'dotfiles update [--all]'* ]] ;;
		self) [[ "$output" == *'dotfiles update'* && "$output" == *'dotfiles restow'* ]] ;;
		esac || return 1
	done
}

test_help_commands_and_dispatch_share_metadata() {
	declare -F dotfiles_command_print_table >/dev/null || return 1
	local expected_table_file="$TEST_HARNESS_ROOT/commands.expected"
	local help_output="$TEST_HARNESS_ROOT/help.output"
	local commands_output="$TEST_HARNESS_ROOT/commands.output"
	dotfiles_command_print_table >"$expected_table_file"
	"$REPO_DIR/bin/bin/dotfiles" help >"$help_output" || return 1
	"$REPO_DIR/bin/bin/dotfiles" commands >"$commands_output" || return 1
	grep -Fq "$(sed -n '1p' "$expected_table_file")" "$help_output" || return 1
	cmp -s "$expected_table_file" "$commands_output" || return 1
	dotfiles_command_metadata_validate || return 1
}

test_dispatch_parity_rejects_missing_or_invalid_handlers() {
	dotfiles_command_metadata_validate || return 1
	local saved="${DOTFILES_COMMAND_HANDLERS[status]}"
	unset 'DOTFILES_COMMAND_HANDLERS[status]'
	if dotfiles_command_metadata_validate; then return 1; fi
	DOTFILES_COMMAND_HANDLERS[status]='not a handler'
	if dotfiles_command_metadata_validate; then return 1; fi
	DOTFILES_COMMAND_HANDLERS[status]="$saved"
	dotfiles_command_metadata_validate
}

test_report_path_shortening_preserves_exact_width() {
	local value output
	value='/mnt/c/Program Files/Microsoft/Windows/Credential Manager/git-credential-manager.exe'
	output="$(_rt_shorten_path "$value" 40)"
	[[ "${#output}" -eq 40 ]] || return 1
	[[ "$output" == *'…'* ]]
}

test_command_lib_is_metadata_only() {
	declare -F command_lib_render >/dev/null || return 1
	local output="$TEST_HARNESS_ROOT/command-lib.output"
	test_harness_reset_logs
	command_lib_render 80 >"$output" || return 1
	grep -Fq '=== Command Lib ===' "$output" || return 1
	grep -Fq 'Dotfiles › Command Lib' "$output" || return 1
	local key
	for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
		[[ "$(grep -Ec "^  ${key}[^|]*\\|" "$output")" -eq 1 ]] || return 1
	done
	[[ ! -s "$TEST_COMMAND_LOG" && ! -s "$TEST_URL_LOG" ]]
}

test_command_lib_documents_full_help_catalog() {
	local output
	output="$(NO_COLOR=1 dotfiles_command_print_table 100)"
	dotfiles_command_metadata_validate
	for needle in \
		'update [--all]' \
		'--all' \
		'Node.js, npm, Go, and Monaspace' \
		'DOTFILES_COMPONENTS' \
		'GITHUB_TOKEN' \
		'install.sh --initial' \
		'stow'; do
		[[ "$output" == *"$needle"* ]] || {
			printf 'missing Dotfiles Command Lib detail: %s\n' "$needle" >&2
			return 1
		}
	done
	[[ "$output" != *'Agentbot integration'* && "$output" != *'AGENT_BOOTSTRAP_HOME'* && "$output" != *'AGENTBOT_HOME'* ]] || return 1
}

test_installer_help_has_no_agentbot_route() {
	local output
	output="$("$REPO_DIR/scripts/install.sh" --help)"
	[[ "$output" != *'--agents'* ]]
}

test_command_lib_details_fit_narrow_terminal() {
	local output line
	output="$(NO_COLOR=1 dotfiles_command_print_table 48)"
	while IFS= read -r line; do
		((${#line} <= 48)) || {
			printf 'line exceeds 48 columns (%d): %s\n' "${#line}" "$line" >&2
			return 1
		}
	done <<<"$output"
}

test_command_details_use_orange_sections_and_yellow_topics() {
	local output colored_output heading_index config_index
	colored_output="$(NO_COLOR='' FORCE_COLOR=1 dotfiles_command_print_details 100)"
	[[ "$colored_output" == *"${C_BOLD}${C_ORANGE}=== Command details ===${C_RESET}"* ]] || return 1
	[[ "$colored_output" == *"${C_BOLD}${C_YELLOW}Command: menu${C_RESET}"* ]] || return 1
	[[ "$colored_output" == *"${C_BOLD}${C_ORANGE}=== Configuration and environment ===${C_RESET}"* ]] || return 1
	[[ "$colored_output" == *"${C_BOLD}${C_ORANGE}=== System surfaces ===${C_RESET}"* ]] || return 1
	NO_COLOR=1
	ui_init_colors
	output="$(dotfiles_command_print_details 100)"
	heading_index="$(printf '%s\n' "$output" | grep -n '^  === Command details ===$' | cut -d: -f1)"
	[[ "$(printf '%s\n' "$output" | sed -n "$((heading_index + 1))p")" == '  Command: menu' ]] || return 1
	config_index="$(printf '%s\n' "$output" | grep -n '^  === Configuration and environment ===$' | cut -d: -f1)"
	[[ "$(printf '%s\n' "$output" | sed -n "$((config_index + 1))p")" != '' ]] || return 1
	[[ "$output" == *"Command: menu"* ]] || return 1
}

test_command_lib_colors_behavior_cells_when_enabled() {
	local output
	NO_COLOR='' FORCE_COLOR=1 output="$(dotfiles_command_print_table 80)"
	[[ "$output" == *$'\033[33mmutating\033[0m'* ]] || return 1
	[[ "$output" == *$'\033[32mread-only\033[0m'* ]]
}

test_topic_headers_use_orange() {
	local output
	NO_COLOR='' FORCE_COLOR=1 ui_init_colors
	output="$(ui_print_header 'Update' 'Dotfiles › Update' 80)"
	grep -Fq $'\033[38;5;208m=== Update ===' <<<"$output" || return 1
	output="$(ui_print_header 'Dotfiles' 'Dotfiles' 80)"
	grep -Fq $'\033[38;5;208m=== Dotfiles ===' <<<"$output"
}

test_table_column_headers_are_bold_white() {
	local output
	NO_COLOR='' FORCE_COLOR=1 ui_init_colors
	output="$(rt_print_table_columns)"
	grep -Fq $'\033[1mcomponent' <<<"$output" || return 1
	! grep -Fq $'\033[93m' <<<"$output"
}

test_component_registry_has_exact_22_with_boost() {
	local expected=(
		git_identity system_packages python graphify_cli boost_cli powershell go nodejs direnv docker portainer lazygit
		lazydocker cursor_cli codex_cli claude_cli copilot_cli monaspace_fonts ssh_key dotfiles
		wsl_conf git_credential
	)
	[[ "${#COMP_KEYS[@]}" -eq 22 && "${#COMP_LABELS[@]}" -eq 22 ]] || return 1
	local i
	for i in "${!expected[@]}"; do
		[[ "${COMP_KEYS[$i]}" == "${expected[$i]}" ]] || return 1
		[[ -n "${COMP_LABELS[$i]}" ]] || return 1
		comp_description "${COMP_KEYS[$i]}" >/dev/null || return 1
	done
	local git_config_idx description
	git_config_idx="$(comp_index_of git_credential)" || return 1
	[[ "${COMP_LABELS[$git_config_idx]}" == 'Git config (credentials + submodules)' ]] || return 1
	description="$(comp_description git_credential)"
	for setting in credential.helper submodule.recurse fetch.recurseSubmodules \
		push.recurseSubmodules status.submoduleSummary; do
		[[ "$description" == *"$setting"* ]] || return 1
	done
}

test_boost_description_does_not_claim_a_pin() {
	# The installer resolves the latest release every run, so a "pinned"
	# claim or a hardcoded version number in the UI text goes stale on the
	# next upstream release -- Boost ships one every day or two.
	local description detail
	description="$(comp_description boost_cli)" || return 1
	detail="${COMP_PLAN_DETAILS[boost_cli]:-}"
	[[ -n "$detail" ]] || return 1
	[[ "$description" != *pinned* && "$detail" != *pinned* ]] || return 1
	[[ ! "$description" =~ v[0-9]+\.[0-9]+\.[0-9]+ ]] || return 1
	[[ ! "$detail" =~ v[0-9]+\.[0-9]+\.[0-9]+ ]] || return 1
	[[ "$description" == *SHA-256* ]] || return 1
	[[ "$description" == *"disabled by default"* ]]
}

test_install_defaults_match_requested_selection() {
	local key
	comp_registry_init
	[[ "${#COMP_KEYS[@]}" -eq 22 ]] || return 1
	for key in "${COMP_KEYS[@]}"; do
		case "$key" in
		git_identity | ssh_key | boost_cli)
			[[ "${COMP_ON[$key]:-}" -eq 0 ]] || return 1
			;;
		*)
			[[ "${COMP_ON[$key]:-}" -eq 1 ]] || return 1
			;;
		esac
	done
	[[ "$(comp_dependency graphify_cli)" == python ]] || return 1
	[[ "${COMP_ON[graphify_cli]:-}" -eq 1 && "${COMP_ON[python]:-}" -eq 1 ]] || return 1
	[[ "${COMP_ON[boost_cli]:-}" -eq 0 ]]
}

test_package_metadata_has_exact_30_with_descriptions() {
	declare -F package_metadata_load >/dev/null || return 1
	package_metadata_load "$PKG_FILE" || return 1
	[[ "${#PACKAGE_LIB_NAMES[@]}" -eq 30 ]] || return 1
	local expected=(
		git curl ca-certificates bash-completion bubblewrap stow shellcheck shfmt tree
		python3 python3-pip python3-venv
		duf ripgrep fd-find fzf zoxide eza jq gh moreutils
		lshw mtr-tiny glances lsof wslu rsync unp poppler-utils magic-wormhole
	)
	local -A expected_counts=([core]=9 [python]=3 [cli]=9 [system]=9)
	local -A actual_counts=()
	local -A seen=()
	local i name tag description
	for i in "${!PACKAGE_LIB_NAMES[@]}"; do
		name="${PACKAGE_LIB_NAMES[$i]}"
		[[ "$name" == "${expected[$i]}" ]] || return 1
		tag="${PACKAGE_LIB_TAGS[$i]}"
		description="${PACKAGE_LIB_DESCRIPTIONS[$i]}"
		[[ -z "${seen[$name]+x}" ]] || return 1
		seen["$name"]=1
		actual_counts["$tag"]=$((${actual_counts[$tag]:-0} + 1))
		[[ -n "$description" ]] || return 1
	done
	for tag in core python cli system; do
		[[ "${actual_counts[$tag]:-0}" -eq "${expected_counts[$tag]}" ]] || return 1
	done
}

test_package_lib_components_are_metadata_only() (
	declare -F package_lib_render_components >/dev/null || return 1
	local output="$TEST_HARNESS_ROOT/package-components.output" probe_calls=0 install_calls=0
	comp_probe() { probe_calls=$((probe_calls + 1)); }
	comp_probe() { probe_calls=$((probe_calls + 1)); }
	comp_install() { install_calls=$((install_calls + 1)); }
	test_harness_reset_logs
	package_lib_render_components 80 >"$output" || return 1
	grep -Fq '=== Package Lib ===' "$output" || return 1
	grep -Fq 'Dotfiles › Package Lib' "$output" || return 1
	local key
	for key in "${COMP_KEYS[@]}"; do
		[[ "$(grep -Ec "^[[:space:]]*${key}([[:space:]]|$)" "$output")" -eq 1 ]] || return 1
	done
	[[ "$probe_calls" -eq 0 && "$install_calls" -eq 0 ]] || return 1
	[[ ! -s "$TEST_COMMAND_LOG" && ! -s "$TEST_URL_LOG" ]]
)

test_package_menu_opens_system_packages_directly() (
	declare -F package_lib_menu >/dev/null || return 1
	local calls=0
	menu_simple_run() { return 99; }
	package_lib_packages_menu() { calls=$((calls + 1)); }
	package_lib_menu || return 1
	[[ "$calls" -eq 1 ]]
)

test_package_lib_all_view_has_no_paging_controls() (
	package_metadata_load "$PKG_FILE" || return 1
	local output="$TEST_HARNESS_ROOT/package-all.output"
	package_lib_render_packages_all 100 >"$output" || return 1
	grep -Fq '=== Package Lib ===' "$output" || return 1
	grep -Fq 'package            | category   | description' "$output" || return 1
	[[ "$(grep -c 'Page ' "$output")" -eq 0 ]] || return 1
	[[ "$(grep -c '^  [^|].*|' "$output")" -ge 31 ]] || return 1
)

test_install_summary_uses_report_table_alignment() (
	local output="$TEST_HARNESS_ROOT/install-summary.output"
	NO_COLOR=1
	ui_init_colors
	COMP_KEYS=(git_identity system_packages)
	COMP_LABELS=('Git identity' 'System packages')
	is_on() { return 0; }
	comp_probe() {
		case "$1" in
		git_identity) printf 'configured|Pamudu Wijesingha <pamuduwijesingha2k20@gmail.com>\n' ;;
		system_packages) printf 'installed|30 apt packages\n' ;;
		esac
	}
	print_install_summary >"$output" || return 1
	grep -Fq '  component              | detail                                   | result' "$output" || return 1
	grep -Fq '  Git identity           | Pamudu Wijesingha <pamuduwijesingha2k...' "$output" || return 1
	grep -Fq '  System packages        | 30 apt packages                          | ' "$output" || return 1
)

test_narrow_reports_remain_bounded() {
	declare -F command_lib_render >/dev/null || return 1
	declare -F package_lib_render_components >/dev/null || return 1
	local output="$TEST_HARNESS_ROOT/narrow.output"
	{
		command_lib_render 40
		package_lib_render_components 40
	} >"$output"
	local line stripped
	while IFS= read -r line; do
		stripped="$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g')"
		((${#stripped} <= 40)) || return 1
	done <"$output"
}

expect_success 'command metadata exactly matches the ten-command dispatch contract' test_authoritative_command_metadata
expect_success 'help, commands output, and dispatch consume authoritative metadata' test_help_commands_and_dispatch_share_metadata
expect_success 'dispatch parity rejects missing or invalid command handlers' test_dispatch_parity_rejects_missing_or_invalid_handlers
expect_success 'removed commands fail with migration guidance' test_removed_commands_report_migration_guidance
expect_success 'report path shortening preserves the fixed detail width' test_report_path_shortening_preserves_exact_width
expect_success 'Command Lib renders all metadata once without side effects' test_command_lib_is_metadata_only
expect_success 'Command Lib documents the full command/config catalog' test_command_lib_documents_full_help_catalog
expect_success 'installer help exposes no Agentbot route' test_installer_help_has_no_agentbot_route
expect_success 'Command Lib wraps details to the terminal width' test_command_lib_details_fit_narrow_terminal
expect_success 'Command details use orange sections and yellow topics' test_command_details_use_orange_sections_and_yellow_topics
expect_success 'Command Lib colors mutating and read-only behavior cells' test_command_lib_colors_behavior_cells_when_enabled
expect_success 'topic headers use the orange palette' test_topic_headers_use_orange
expect_success 'table column headers remain bold white' test_table_column_headers_are_bold_white
expect_success 'component registry exposes the exact 22 described component IDs' test_component_registry_has_exact_22_with_boost
expect_success 'Boost component text does not claim a version pin' test_boost_description_does_not_claim_a_pin
expect_success 'install defaults exclude identity key generation and preview Boost' test_install_defaults_match_requested_selection
expect_success 'package metadata contains 30 unique described names in 9/3/9/9 tags' test_package_metadata_has_exact_30_with_descriptions
expect_success 'Package Lib renders all 22 components without probes or side effects' test_package_lib_components_are_metadata_only
expect_success 'Package Lib opens the system package table directly' test_package_menu_opens_system_packages_directly
expect_success 'Package Lib all view has no paging controls' test_package_lib_all_view_has_no_paging_controls
expect_success 'install summary uses the report table alignment' test_install_summary_uses_report_table_alignment
expect_success 'Command and Package Lib narrow rendering remains bounded' test_narrow_reports_remain_bounded

finish_tests
