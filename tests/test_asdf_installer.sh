#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

source "$ROOT/scripts/lib/installers/logging.sh"
# shellcheck source=scripts/lib/installers/cli_tools.sh
source "$ROOT/scripts/lib/installers/cli_tools.sh"

fixture_asdf() {
	local reported="${1:-0.19.0}" rc="${2:-0}" member="${3:-asdf}"
	HOME="$(mktemp -d "$TEST_HARNESS_ROOT/asdf-home.XXXXXX")"
	export HOME
	mkdir -p "$HOME/.asdf/bin" "$HOME/.asdf/plugins/golang" "$HOME/fixture/$(dirname -- "$member")"
	printf '%s\n' '#!/usr/bin/env bash' 'echo legacy-asdf' >"$HOME/.asdf/bin/asdf"
	chmod +x "$HOME/.asdf/bin/asdf"
	printf 'plugin-data\n' >"$HOME/.asdf/plugins/golang/sentinel"
	printf '%s\n' '#!/bin/sh' "echo 'asdf version $reported'" "exit $rc" >"$HOME/fixture/$member"
	chmod +x "$HOME/fixture/$member"
	tar -czf "$HOME/release.tar.gz" -C "$HOME/fixture" "$member"
	github_latest_release_version() { printf '0.19.0\n'; }
	github_release_asset_sha256() { sha256sum "$HOME/release.tar.gz" | awk '{print $1}'; }
	github_curl() { cp "$HOME/release.tar.gz" "$3"; }
}

legacy_is_preserved() {
	[[ "$("$HOME/.asdf/bin/asdf")" == legacy-asdf ]] || return 1
	[[ "$(<"$HOME/.asdf/plugins/golang/sentinel")" == plugin-data ]]
}

test_extraction_failure_preserves_legacy_executable() (
	fixture_asdf
	tar() { return 9; }
	! ensure_asdf_installed >/dev/null 2>&1 || return 1
	legacy_is_preserved
)

test_failed_or_wrong_probe_preserves_legacy_executable() (
	local reported rc
	for reported in 0.19.0 0.19.00; do
		rc=0
		[[ "$reported" != 0.19.0 ]] || rc=9
		fixture_asdf "$reported" "$rc"
		! ensure_asdf_installed >/dev/null 2>&1 || return 1
		legacy_is_preserved || return 1
	done
)

test_failed_activation_preserves_legacy_executable() (
	fixture_asdf
	mv() { return 9; }
	! ensure_asdf_installed >/dev/null 2>&1 || return 1
	legacy_is_preserved
)

test_verified_migration_preserves_plugins() (
	local member
	for member in asdf release/asdf; do
		fixture_asdf 0.19.0 0 "$member"
		ensure_asdf_installed >/dev/null || return 1
		[[ "$("$HOME/.asdf/bin/asdf" version)" == 'asdf version 0.19.0' ]] || return 1
		[[ "$(command -v asdf)" == "$HOME/.asdf/bin/asdf" ]] || return 1
		[[ "$(<"$HOME/.asdf/plugins/golang/sentinel")" == plugin-data ]] || return 1
	done
)

expect_success 'asdf extraction failure preserves the legacy executable' test_extraction_failure_preserves_legacy_executable
expect_success 'asdf failed or inexact version probe preserves the legacy executable' test_failed_or_wrong_probe_preserves_legacy_executable
expect_success 'asdf activation failure preserves the legacy executable' test_failed_activation_preserves_legacy_executable
expect_success 'verified asdf migration preserves plugins for flat and nested archives' test_verified_migration_preserves_plugins
finish_tests
