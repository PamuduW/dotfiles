#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$TEST_DIR/lib/dotfiles_env.sh"
fixture="$TEST_HARNESS_ROOT/manual-catalog"
printf '%s\n' $'cursor_cli\towner\tany\tdotfiles' $'cursor_cli\tkind\tany\texternal' | catalog_fixture_seal "$fixture"
catalog_fixture_use "$fixture"
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nprintf "Cursor 2026.10.26\\n"\n' >"$HOME/.local/bin/agent"
chmod +x "$HOME/.local/bin/agent"
export PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
curl() {
	printf 'FAIL: manual Cursor was downloaded\n' >&2
	return 99
}
output="$(DOTFILES_FORCE_REINSTALL=1 install_cursor_cli)"
[[ "$output" == *'outside automatic catalog management'* ]]
UPGRADE_STEP_ACTIVE_RESULT=''
upgrade_cursor_cli >"$TEST_HARNESS_ROOT/upgrade-output"
[[ "$UPGRADE_STEP_ACTIVE_RESULT" == skipped ]]
row="$(check_cursor_cli || true)"
[[ "$row" == 'Cursor CLI|Cursor 2026.10.26|—|external' ]] || {
	printf 'FAIL: unexpected manual status: %s\n' "$row" >&2
	exit 1
}
[[ "$("$HOME/.local/bin/agent" --version)" == 'Cursor 2026.10.26' ]]
rm "$HOME/.local/bin/agent"
row="$(check_cursor_cli || true)"
[[ "$row" == 'Cursor CLI|not installed|—|external' ]]
printf 'PASS: manual Cursor reports version and skips installs/updates without network\n'
