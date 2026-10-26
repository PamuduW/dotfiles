#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
test_harness_report_init
source "$REPO_DIR/scripts/lib/installers/fonts.sh"

windows_handoff() (
	local rc=0
	export WSL_DISTRO_NAME=Ubuntu
	log_step() { :; }
	log_skip() { :; }
	log_ok() { :; }
	log_warn() { :; }
	wslpath() { printf '%s\n' "C:\\Users\\Font User\\O'Neil\\fonts"; }
	powershell.exe() {
		[[ "$*" == *'-EncodedCommand '* ]] || return 1
		python3 - "${!#}" <<'PY'
import base64, sys
text = base64.b64decode(sys.argv[1]).decode('utf-16le')
assert "-FontDirectory 'C:\\Users\\Font User\\O''Neil\\fonts'" in text
assert 'AddFontResourceEx' in text
assert 'HKCU:' in text
PY
		return "${WINDOWS_FONT_STATUS:-0}"
	}
	install_ubuntu_sans_mono_windows "$TEST_HARNESS_ROOT/fonts" || rc=$?
	[[ "$rc" == "${WINDOWS_FONT_STATUS:-0}" ]]
)
check 'Windows font handoff uses encoded PowerShell and quotes paths' windows_handoff
windows_failure() (
	export WINDOWS_FONT_STATUS=7
	windows_handoff
)
# Run the function in a subshell so its mocks never touch the real Windows host.
check 'Windows font installation failure is not reported as success' windows_failure

windows_unavailable() (
	unset WSL_DISTRO_NAME WSL_INTEROP
	local invoked="$TEST_HARNESS_ROOT/windows-invoked" output
	powershell.exe() { : >"$invoked"; }
	log_warn() { printf '%s\n' "$*"; }
	output="$(install_ubuntu_sans_mono_windows "$TEST_HARNESS_ROOT/fonts")" || return 1
	[[ ! -e "$invoked" && "$output" == *manually* ]]
)
windows_retry_when_wsl_installed() (
	local rc=0
	export HOME="$TEST_HARNESS_ROOT/already-installed"
	mkdir -p "$HOME/.local/share/fonts/ubuntu-sans-mono"
	: >"$HOME/.local/share/fonts/ubuntu-sans-mono/UbuntuSansMono-Regular.ttf"
	printf '1.0\n' >"$HOME/.local/share/fonts/ubuntu-sans-mono/.version"
	printf '%064d\n' 0 >"$HOME/.local/share/fonts/ubuntu-sans-mono/.catalog-receipt"
	printf '%s\n' $'ubuntu_sans_mono_fonts\towner\tany\tdotfiles' \
		$'ubuntu_sans_mono_fonts\tkind\tany\tsoftware' $'ubuntu_sans_mono_fonts\tversion\tany\t1.0' \
		$'ubuntu_sans_mono_fonts\tarchive\tany\tzip' | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-font-retry"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-font-retry"
	skip_unless_forced() { return 0; }
	install_ubuntu_sans_mono_windows() { return 7; }
	install_ubuntu_sans_mono_fonts || rc=$?
	[[ "$rc" == 7 ]]
)
check 'missing Windows interop warns and preserves WSL-only installation' windows_unavailable
check 'an existing WSL install still retries a failed Windows installation' windows_retry_when_wsl_installed

test_harness_cleanup
finish_tests
