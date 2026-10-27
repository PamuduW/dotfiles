#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
test_harness_report_init
PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/installers/logging.sh"
source "$ROOT/scripts/lib/installers/graphify.sh"

# Mock the SDK acquisition boundary and uv process. Catalog lookup, artifact/lock verification, owned
# staging, version probes and publication remain real; no dependency is fetched.
source "$TEST_DIR/lib/graphify_catalog_fixture.sh"

test_forced_reinstall_reaches_the_installer() (
	graphify_reset
	install_graphify_cli
	: >"$TEST_COMMAND_LOG"
	install_graphify_cli
	[[ ! -s "$TEST_COMMAND_LOG" ]] || return 1
	DOTFILES_FORCE_REINSTALL=1 install_graphify_cli
	grep -q '^uv:pip sync .*--require-hashes' "$TEST_COMMAND_LOG"
)

test_external_graphify_is_preserved_even_when_forced() (
	graphify_reset
	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'echo "graphify 9.9.9"' >"$HOME/.local/bin/graphify"
	chmod +x "$HOME/.local/bin/graphify"
	DOTFILES_FORCE_REINSTALL=1 install_graphify_cli
	[[ "$("$HOME/.local/bin/graphify" --version)" == 'graphify 9.9.9' && ! -L "$HOME/.local/bin/graphify" ]] || return 1
	[[ ! -s "$TEST_COMMAND_LOG" && ! -e "$HOME/.local/bin/uv" ]]
)

test_missing_graphify_uses_frozen_official_package() (
	graphify_reset
	install_graphify_cli
	[[ "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.3' ]] || return 1
	[[ -f "$HOME/.local/share/dotfiles-catalog/graphify_cli/current/.catalog-receipt" ]] || return 1
	grep -q '^uv:pip sync .*--require-hashes' "$TEST_COMMAND_LOG"
)

test_owned_graphify_is_idempotent() (
	graphify_reset
	install_graphify_cli
	: >"$TEST_COMMAND_LOG"
	install_graphify_cli
	[[ ! -s "$TEST_COMMAND_LOG" ]]
)

test_missing_uv_uses_verified_artifact_without_vendor_script() (
	graphify_reset
	ensure_graphify_uv
	[[ "$("$HOME/.local/bin/uv" --version)" == 'uv 0.12.0' ]] || return 1
	[[ -f "$HOME/.local/share/dotfiles-catalog/uv/current/.catalog-receipt" ]]
)

test_failed_frozen_sync_preserves_working_graphify() (
	graphify_reset
	install_graphify_cli
	local previous
	previous="$(readlink "$HOME/.local/share/dotfiles-catalog/graphify_cli/current")"
	export TEST_GRAPHIFY_SYNC_FAILS=1
	if DOTFILES_FORCE_REINSTALL=1 install_graphify_cli; then return 1; fi
	[[ "$(readlink "$HOME/.local/share/dotfiles-catalog/graphify_cli/current")" == "$previous" ]] || return 1
	[[ "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.3' ]]
)

test_shadowed_outdated_uv_is_not_used_for_installation() (
	graphify_reset
	ensure_graphify_uv
	graphify_fixture 1.2.3 0.13.0
	printf '%s\n' '#!/usr/bin/env bash' 'echo external' >"$TEST_FAKE_BIN/uv"
	chmod +x "$TEST_FAKE_BIN/uv"
	PATH="$TEST_FAKE_BIN:$HOME/.local/bin:/usr/bin:/bin"
	: >"$TEST_COMMAND_LOG"
	if install_graphify_cli; then
		echo 'FAIL: Graphify ran an owned uv version outside the selected snapshot' >&2
		return 1
	fi
	[[ ! -e "$HOME/.local/bin/graphify" ]] || return 1
	! grep -Eq '^uv:(venv|pip)' "$TEST_COMMAND_LOG"
)

test_frozen_sync_retries_trusted_system_certificates_quietly() (
	graphify_reset
	export TEST_GRAPHIFY_CERT_RETRY=1
	local output
	output="$(install_graphify_cli 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	[[ "$(grep -c '^uv:pip sync ' "$TEST_COMMAND_LOG")" == 2 ]] || return 1
	grep -Fxq certs:false "$TEST_COMMAND_LOG" || return 1
	grep -Fxq certs:true "$TEST_COMMAND_LOG" || return 1
	[[ "$output" != *UnknownIssuer* ]] || return 1
	[[ "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.3' ]]
)

test_failed_frozen_sync_reports_both_attempts_without_publication() (
	graphify_reset
	export TEST_GRAPHIFY_SYNC_FAILS=1
	local output rc=0
	output="$(install_graphify_cli 2>&1)" || rc=$?
	[[ "$rc" != 0 && ! -e "$HOME/.local/bin/graphify" ]] || return 1
	[[ "$(grep -c '^uv:pip sync ' "$TEST_COMMAND_LOG")" == 2 ]] || return 1
	[[ "$output" == *'frozen sync failed'* ]]
)

test_same_version_new_uv_refreshes_the_owned_closure() (
	graphify_reset
	install_graphify_cli || return 1
	local previous
	previous="$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" || return 1
	graphify_fixture 1.2.3 0.13.0
	: >"$TEST_COMMAND_LOG"
	install_graphify_cli || return 1
	[[ "$("$HOME/.local/bin/uv" --version)" == 'uv 0.13.0' &&
	"$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" != "$previous" ]] || {
		echo 'FAIL: unchanged Graphify skipped its newly approved uv dependency' >&2
		return 1
	}
	grep -q '^uv:pip sync .*--require-hashes' "$TEST_COMMAND_LOG"
)

test_same_version_lock_change_is_not_skipped() (
	graphify_reset
	install_graphify_cli || return 1
	local previous fixture="$TEST_HARNESS_ROOT/catalog-graphify"
	previous="$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" || return 1
	# An extra blank line changes the approved lock digest without changing
	# the declared top-level version or the dependency parsed by the fake uv.
	printf '\n' >>"$fixture/locks/graphify.txt"
	python3 - "$fixture" <<'PYLOCKCHANGE'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1]); digest=hashlib.sha256((root/'locks/graphify.txt').read_bytes()).hexdigest()
rows=root.joinpath('rows').read_text().splitlines()
rows=['\t'.join((*x.split('\t')[:3],'sha256:'+digest)) if x.startswith('graphify_cli\tdigest\t') else x for x in rows]
root.joinpath('changed-rows').write_text('\n'.join(rows)+'\n')
PYLOCKCHANGE
	catalog_fixture_seal "$fixture" <"$fixture/changed-rows"
	catalog_fixture_use "$fixture"
	# shellcheck source=/dev/null
	source "$ROOT/scripts/lib/updates/common.sh"
	[[ "$(check_graphify_cli || true)" == 'Graphify CLI|1.2.3|1.2.3|upgrade' ]] || {
		echo 'FAIL: changed approved lock was reported current' >&2
		return 1
	}
	upgrade_graphify_cli || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == updated ]] || {
		echo 'FAIL: refreshed approved lock was reported unchanged' >&2
		return 1
	}
	[[ "$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" != "$previous" ]] || {
		echo 'FAIL: unchanged Graphify skipped its changed approved lock' >&2
		return 1
	}
)

test_graphify_uses_the_selected_private_python() (
	graphify_reset
	local selected="$TEST_GRAPHIFY_SELECTED_PYTHON"
	install_graphify_cli || return 1
	grep -Fq -- "uv:venv --python $selected " "$TEST_COMMAND_LOG" || {
		echo 'FAIL: Graphify did not select the private catalog interpreter' >&2
		return 1
	}
)

test_same_graphify_version_new_python_refreshes_the_environment() (
	graphify_reset
	install_graphify_cli || return 1
	local previous selected
	previous="$(readlink "$(dotfiles_catalog_root graphify_cli)/current")"
	selected="$TEST_GRAPHIFY_SELECTED_PYTHON"
	graphify_fixture 1.2.3 0.12.0 3.12.16+20261027
	: >"$TEST_COMMAND_LOG"
	install_graphify_cli || return 1
	[[ "$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" != "$previous" && -x "$selected" ]] || return 1
	grep -Fq -- "uv:venv --python $TEST_GRAPHIFY_SELECTED_PYTHON " "$TEST_COMMAND_LOG"
)

test_failed_python_acquisition_preserves_the_environment() (
	graphify_reset
	install_graphify_cli || return 1
	local previous
	previous="$(readlink "$(dotfiles_catalog_root graphify_cli)/current")"
	graphify_fixture 1.2.3 0.12.0 3.12.16+20261027
	export TEST_GRAPHIFY_RUNTIME_FAILS=1
	: >"$TEST_COMMAND_LOG"
	if install_graphify_cli; then return 1; fi
	[[ "$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" == "$previous" && "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.3' ]] || return 1
	! grep -q '^uv:venv ' "$TEST_COMMAND_LOG"
)

test_wrong_python_base_cannot_publish() (
	graphify_reset
	install_graphify_cli || return 1
	local previous output
	previous="$(readlink "$(dotfiles_catalog_root graphify_cli)/current")"
	export TEST_GRAPHIFY_WRONG_BASE=1
	: >"$TEST_COMMAND_LOG"
	if output="$(DOTFILES_FORCE_REINSTALL=1 install_graphify_cli 2>&1)"; then return 1; fi
	[[ "$output" == *'does not use the selected private runtime'* ]] || return 1
	[[ "$(readlink "$(dotfiles_catalog_root graphify_cli)/current")" == "$previous" && "$("$HOME/.local/bin/graphify" --version)" == 'graphify 1.2.3' ]] || return 1
	! grep -q '^uv:pip sync ' "$TEST_COMMAND_LOG"
)

expect_success 'a changed Python runtime rebuilds unchanged Graphify and retains the old release' test_same_graphify_version_new_python_refreshes_the_environment
expect_success 'failed Python acquisition preserves the working Graphify environment' test_failed_python_acquisition_preserves_the_environment
expect_success 'a different Python base is rejected before package installation and publication' test_wrong_python_base_cannot_publish
expect_success 'Graphify uses the selected private Python instead of the host ABI' test_graphify_uses_the_selected_private_python
expect_success 'unchanged Graphify refreshes when its approved uv dependency changes' test_same_version_new_uv_refreshes_the_owned_closure
expect_success 'unchanged Graphify refreshes when its approved lock changes' test_same_version_lock_change_is_not_skipped
expect_success 'frozen Graphify sync retries system trust without leaking recovered errors' test_frozen_sync_retries_trusted_system_certificates_quietly
expect_success 'failed frozen Graphify sync reports diagnostics and publishes nothing' test_failed_frozen_sync_reports_both_attempts_without_publication
expect_success 'forced Graphify reinstall applies the frozen closure' test_forced_reinstall_reaches_the_installer
expect_success 'external Graphify is preserved even when forced' test_external_graphify_is_preserved_even_when_forced
expect_success 'missing Graphify installs the frozen graphifyy package' test_missing_graphify_uses_frozen_official_package
expect_success 'owned Graphify installation is idempotent' test_owned_graphify_is_idempotent
expect_success 'missing uv uses its verified artifact instead of a vendor script' test_missing_uv_uses_verified_artifact_without_vendor_script
expect_success 'failed frozen sync preserves working Graphify' test_failed_frozen_sync_preserves_working_graphify
expect_success 'shadowed outdated uv cannot satisfy an approved dependency' test_shadowed_outdated_uv_is_not_used_for_installation
finish_tests
