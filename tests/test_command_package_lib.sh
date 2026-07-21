#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Dynamic sources and indirect negative-test doubles.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=tests/lib/test_harness.sh
# shellcheck disable=SC1091
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

NO_COLOR=1
export NO_COLOR
PKG_FILE="$REPO_DIR/packages/packages.txt"
export PKG_FILE

# Source the read-only presentation and component metadata dependencies.
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/lib/menu_render.sh"
source "$REPO_DIR/scripts/lib/tty.sh"
source "$REPO_DIR/scripts/lib/report_table.sh"
source "$REPO_DIR/scripts/lib/ui.sh"
source "$REPO_DIR/scripts/lib/menu_paging.sh"
source "$REPO_DIR/scripts/lib/components/registry.sh"
source "$REPO_DIR/scripts/lib/components/descriptions.sh"
ui_init_colors

[[ -f "$REPO_DIR/scripts/lib/command_metadata.sh" ]] && source "$REPO_DIR/scripts/lib/command_metadata.sh"
[[ -f "$REPO_DIR/scripts/menus/command_lib.sh" ]] && source "$REPO_DIR/scripts/menus/command_lib.sh"
[[ -f "$REPO_DIR/scripts/menus/package_lib.sh" ]] && source "$REPO_DIR/scripts/menus/package_lib.sh"

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

expect_success() {
	local name="$1"
	shift
	if "$@"; then
		pass "$name"
	else
		fail "$name"
	fi
}

count_exact_line() {
	local expected="$1" file="$2"
	awk -v expected="$expected" '$0 == expected { count++ } END { print count + 0 }' "$file"
}

test_authoritative_command_metadata() {
	declare -F dotfiles_command_metadata_validate >/dev/null || return 1
	dotfiles_command_metadata_validate || return 1
	local expected=(menu update status commands packages restow help)
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
	declare -F dotfiles_command_dispatch_keys >/dev/null || return 1
	declare -F dotfiles_command_metadata_validate_dispatch >/dev/null || return 1
	local expected_table_file="$TEST_HARNESS_ROOT/commands.expected"
	local help_output="$TEST_HARNESS_ROOT/help.output"
	local commands_output="$TEST_HARNESS_ROOT/commands.output"
	local -a dispatch_keys=()
	dotfiles_command_print_table >"$expected_table_file"
	"$REPO_DIR/bin/bin/dotfiles" help >"$help_output" || return 1
	"$REPO_DIR/bin/bin/dotfiles" commands >"$commands_output" || return 1
	grep -Fq "$(sed -n '1p' "$expected_table_file")" "$help_output" || return 1
	cmp -s "$expected_table_file" "$commands_output" || return 1
	dotfiles_command_metadata_validate_dispatch "$REPO_DIR/bin/bin/dotfiles" || return 1
	mapfile -t dispatch_keys < <(dotfiles_command_dispatch_keys "$REPO_DIR/bin/bin/dotfiles")
	[[ "${#dispatch_keys[@]}" -eq "${#DOTFILES_COMMAND_KEYS[@]}" ]] || return 1
	local i
	for i in "${!DOTFILES_COMMAND_KEYS[@]}"; do
		[[ "${dispatch_keys[$i]}" == "${DOTFILES_COMMAND_KEYS[$i]}" ]] || return 1
	done
}

test_dispatch_parity_rejects_extra_duplicate_and_missing_keys() {
	declare -F dotfiles_command_metadata_validate_dispatch >/dev/null || return 1
	local valid="$TEST_HARNESS_ROOT/dispatch-valid.sh"
	local duplicate="$TEST_HARNESS_ROOT/dispatch-duplicate.sh"
	local extra="$TEST_HARNESS_ROOT/dispatch-extra.sh"
	local missing="$TEST_HARNESS_ROOT/dispatch-missing.sh"
	local key

	{
		printf '%s\n' 'main() {' "  case \"\${1:-}\" in"
		for key in "${DOTFILES_COMMAND_KEYS[@]}"; do
			if [[ "$key" == help ]]; then
				printf '%s\n' '    help | -h | --help) : ;;'
			else
				printf '    %s) : ;;\n' "$key"
			fi
		done
		printf '%s\n' "    '') : ;;" '    *) : ;;' '  esac' '}'
	} >"$valid"
	cp "$valid" "$duplicate"
	sed -i '/^[[:space:]]*menu)/a\    menu) : ;;' "$duplicate"
	cp "$valid" "$extra"
	sed -i '/^[[:space:]]*help /i\    surprise) : ;;' "$extra"
	grep -v '^[[:space:]]*status)' "$valid" >"$missing"

	dotfiles_command_metadata_validate_dispatch "$valid" || return 1
	if dotfiles_command_metadata_validate_dispatch "$duplicate"; then return 1; fi
	if dotfiles_command_metadata_validate_dispatch "$extra"; then return 1; fi
	if dotfiles_command_metadata_validate_dispatch "$missing"; then return 1; fi
}

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
		'Include Node.js, Go, and Monaspace' \
		'DOTFILES_COMPONENTS' \
		'AGENT_BOOTSTRAP_HOME' \
		'GITHUB_TOKEN' \
		'install.sh --initial' \
		'Agentbot integration' \
		'stow'; do
		[[ "$output" == *"$needle"* ]] || {
			printf 'missing Dotfiles Command Lib detail: %s\n' "$needle" >&2
			return 1
		}
	done
}

test_command_lib_details_fit_narrow_terminal() {
	local output line
	output="$(NO_COLOR=1 dotfiles_command_print_table 48)"
	while IFS= read -r line; do
		(( ${#line} <= 48 )) || {
			printf 'line exceeds 48 columns (%d): %s\n' "${#line}" "$line" >&2
			return 1
		}
	done <<<"$output"
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

test_component_registry_has_exact_20() {
	local expected=(
		git_identity system_packages python powershell go nodejs direnv docker portainer lazygit
		lazydocker cursor_cli codex_cli claude_cli copilot_cli monaspace_fonts ssh_key dotfiles
		wsl_conf git_credential
	)
	[[ "${#COMP_KEYS[@]}" -eq 20 && "${#COMP_LABELS[@]}" -eq 20 ]] || return 1
	local i
	for i in "${!expected[@]}"; do
		[[ "${COMP_KEYS[$i]}" == "${expected[$i]}" ]] || return 1
		[[ -n "${COMP_LABELS[$i]}" ]] || return 1
		comp_description "${COMP_KEYS[$i]}" >/dev/null || return 1
	done
}

test_package_metadata_has_exact_28_with_descriptions() {
	declare -F package_metadata_load >/dev/null || return 1
	package_metadata_load "$PKG_FILE" || return 1
	[[ "${#PACKAGE_LIB_NAMES[@]}" -eq 28 ]] || return 1
	local expected=(
		git curl ca-certificates bash-completion bubblewrap stow shellcheck shfmt tree
		python3 python3-pip python3-venv
		duf ripgrep fd-find fzf zoxide eza moreutils
		lshw mtr-tiny glances lsof wslu rsync unp poppler-utils magic-wormhole
	)
	local -A expected_counts=([core]=9 [python]=3 [cli]=7 [system]=9)
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
		actual_counts["$tag"]=$(( ${actual_counts[$tag]:-0} + 1 ))
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
	_install_summary_probe() { probe_calls=$((probe_calls + 1)); }
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

test_package_pages_cover_all_28_once() {
	declare -F package_lib_render_packages_page >/dev/null || return 1
	package_metadata_load "$PKG_FILE" || return 1
	local output="$TEST_HARNESS_ROOT/package-pages.output"
	local page page_count page_size=7
	: >"$output"
	page_count="$(menu_page_count "${#PACKAGE_LIB_NAMES[@]}" "$page_size")"
	for ((page = 0; page < page_count; page++)); do
		package_lib_render_packages_page "$page" "$page_size" 52 >>"$output" || return 1
	done
	local name
	for name in "${PACKAGE_LIB_NAMES[@]}"; do
		[[ "$(grep -Ec "^[[:space:]]*${name}([[:space:]]|$)" "$output")" -eq 1 ]] || return 1
	done
	[[ "$(grep -c 'Page ' "$output")" -eq "$page_count" ]]
	grep -Fq 'package' "$output" || return 1
	grep -Fq 'category' "$output" || return 1
	grep -Fq 'description' "$output"
}

test_package_menu_opens_system_packages_directly() (
	declare -F package_lib_menu >/dev/null || return 1
	local calls=0
	menu_simple_run() { return 99; }
	package_lib_packages_menu() { calls=$((calls + 1)); }
	package_lib_menu || return 1
	[[ "$calls" -eq 1 ]]
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

expect_success 'command metadata exactly matches the seven-command dispatch contract' test_authoritative_command_metadata
expect_success 'help, commands output, and dispatch consume authoritative metadata' test_help_commands_and_dispatch_share_metadata
expect_success 'dispatch parity rejects extra, duplicate, and missing command keys' test_dispatch_parity_rejects_extra_duplicate_and_missing_keys
expect_success 'removed commands fail with migration guidance' test_removed_commands_report_migration_guidance
expect_success 'dotfiles status is local-only and reports freshness unchecked' test_status_is_local_read_only
expect_success 'report path shortening preserves the fixed detail width' test_report_path_shortening_preserves_exact_width
expect_success 'Command Lib renders all metadata once without side effects' test_command_lib_is_metadata_only
expect_success 'Command Lib documents the full command/config catalog' test_command_lib_documents_full_help_catalog
expect_success 'Command Lib wraps details to the terminal width' test_command_lib_details_fit_narrow_terminal
expect_success 'Command Lib colors mutating and read-only behavior cells' test_command_lib_colors_behavior_cells_when_enabled
expect_success 'topic headers use the orange palette' test_topic_headers_use_orange
expect_success 'table column headers remain bold white' test_table_column_headers_are_bold_white
expect_success 'component registry exposes the exact 20 described component IDs' test_component_registry_has_exact_20
expect_success 'package metadata contains 28 unique described names in 9/3/7/9 tags' test_package_metadata_has_exact_28_with_descriptions
expect_success 'Package Lib renders all 20 components without probes or side effects' test_package_lib_components_are_metadata_only
expect_success 'System package pages cover all 28 names exactly once' test_package_pages_cover_all_28_once
expect_success 'Package Lib opens the system package table directly' test_package_menu_opens_system_packages_directly
expect_success 'Command and Package Lib narrow rendering remains bounded' test_narrow_reports_remain_bounded

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
