#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
PATH="$ORIGINAL_PATH"
export PATH

test_harness_report_init

DOTFILES_DIR="$ROOT"
export DOTFILES_DIR
source "$ROOT/scripts/lib/installers/logging.sh"
source "$ROOT/scripts/lib/installers/stow.sh"
source "$ROOT/scripts/lib/components/probes.sh"

reset_git_config() {
	rm -f -- "$HOME/.gitconfig" "$XDG_CONFIG_HOME/git/ignore"
}

test_submodule_defaults_are_configured_without_gcm() (
	reset_git_config
	find_windows_git_credential_manager() { return 1; }

	configure_git_settings >/dev/null || return 1

	[[ "$(git config --global --get submodule.recurse)" == true ]] || return 1
	[[ "$(git config --global --get fetch.recurseSubmodules)" == on-demand ]] || return 1
	[[ "$(git config --global --get push.recurseSubmodules)" == check ]] || return 1
	[[ "$(git config --global --get status.submoduleSummary)" == true ]] || return 1
	[[ -z "$(git config --global --get-all credential.helper || true)" ]]
)

test_existing_helper_is_preserved_when_gcm_is_missing() (
	reset_git_config
	git config --global credential.helper libsecret
	find_windows_git_credential_manager() { return 1; }

	configure_git_settings >/dev/null || return 1

	[[ "$(git config --global --get credential.helper)" == libsecret ]]
)

test_detected_gcm_and_submodule_defaults_are_all_configured() (
	reset_git_config
	find_windows_git_credential_manager() {
		printf '%s\n' '/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe'
	}

	configure_git_settings >/dev/null || return 1

	[[ "$(git config --global --get credential.helper)" == '/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe' ]] || return 1
	[[ "$(git config --global --get submodule.recurse)" == true ]] || return 1
	[[ "$(git config --global --get fetch.recurseSubmodules)" == on-demand ]] || return 1
	[[ "$(git config --global --get push.recurseSubmodules)" == check ]] || return 1
	[[ "$(git config --global --get status.submoduleSummary)" == true ]]
)

test_probe_distinguishes_complete_partial_and_incomplete_configuration() (
	reset_git_config
	git config --global credential.helper libsecret
	git config --global submodule.recurse true
	git config --global fetch.recurseSubmodules on-demand
	git config --global push.recurseSubmodules check
	git config --global status.submoduleSummary true
	[[ "$(_comp_probe_git_credential)" == 'configured|credential helper + recursive submodule defaults' ]] || return 1

	git config --global --unset-all credential.helper
	[[ "$(_comp_probe_git_credential)" == 'check|submodule defaults set; credential helper not configured' ]] || return 1

	git config --global --unset-all status.submoduleSummary
	[[ "$(_comp_probe_git_credential)" == 'check|Git configuration incomplete' ]]
)

test_global_ignores_are_added_once_and_keep_existing_lines() (
	reset_git_config
	local ignore="$XDG_CONFIG_HOME/git/ignore"
	mkdir -p "$(dirname "$ignore")"
	printf '%s' '**/.claude/settings.local.json' >"$ignore"
	find_windows_git_credential_manager() { return 1; }

	configure_git_settings >/dev/null || return 1
	configure_git_settings >/dev/null || return 1

	[[ "$(cat "$ignore")" == $'**/.claude/settings.local.json\n**/.boost/hook-meta/' ]]
)

test_global_ignores_follow_core_excludes_file() (
	reset_git_config
	# shellcheck disable=SC2088  # Git expands the tilde itself; that is under test.
	git config --global core.excludesFile '~/custom-ignore'
	find_windows_git_credential_manager() { return 1; }

	configure_git_settings >/dev/null || return 1

	grep -Fxq '**/.boost/hook-meta/' "$HOME/custom-ignore" || return 1
	[[ ! -e "$XDG_CONFIG_HOME/git/ignore" ]]
)

expect_success 'submodule defaults do not depend on Windows GCM' test_submodule_defaults_are_configured_without_gcm
expect_success 'missing GCM preserves an existing credential helper' test_existing_helper_is_preserved_when_gcm_is_missing
expect_success 'detected GCM is configured with all submodule defaults' test_detected_gcm_and_submodule_defaults_are_all_configured
expect_success 'Git configuration probe distinguishes full and partial states' test_probe_distinguishes_complete_partial_and_incomplete_configuration
expect_success 'global ignores are added once and keep existing lines' test_global_ignores_are_added_once_and_keep_existing_lines
expect_success 'global ignores follow core.excludesFile' test_global_ignores_follow_core_excludes_file

finish_tests
