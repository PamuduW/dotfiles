#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
test_harness_report_init

source "$ROOT/scripts/lib/installers/logging.sh"
# shellcheck source=scripts/lib/updates/common.sh
source "$ROOT/scripts/lib/updates/common.sh"
# shellcheck source=scripts/lib/installers/antigravity.sh
source "$ROOT/scripts/lib/installers/antigravity.sh"

FIXTURE_URL='https://storage.googleapis.com/antigravity-public/antigravity-cli/1.3.4-1/linux-x64/cli_linux_x64.tar.gz'
FIXTURE_ARCHIVE="$TEST_HARNESS_ROOT/cli_linux_x64.tar.gz"
AGY_CALLS="$TEST_HARNESS_ROOT/agy.calls"

# The fixture binary answers --version and records every other invocation, so a
# test can prove `agy install` (the profile writer) never ran.
make_agy_archive() {
	local version="${1:-1.3.4}" fixture_dir="$TEST_HARNESS_ROOT/agy-fixture"
	shift || true
	rm -rf -- "$fixture_dir"
	mkdir -p "$fixture_dir"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		"if [[ \"\${1:-}\" == --version ]]; then printf '${version}\\n'; exit 0; fi" \
		"printf '%s\\n' \"\$*\" >>'${AGY_CALLS}'" >"$fixture_dir/antigravity"
	chmod +x "$fixture_dir/antigravity"
	printf 'license\n' >"$fixture_dir/LICENSE"
	if [[ $# -eq 0 ]]; then
		set -- antigravity
	fi
	tar -czf "$FIXTURE_ARCHIVE" -C "$fixture_dir" "$@"
}

fixture_manifest() {
	local version="$1" url="$2" sha512="$3"
	printf '{"version": "%s", "url": "%s", "sha512": "%s"}\n' "$version" "$url" "$sha512"
}

# Serves the manifest and the archive the way the release host does.
stub_release_host() {
	local version="$1" url="${2:-$FIXTURE_URL}" sha512="${3:-}"
	[[ -n "$sha512" ]] || sha512="$(sha512sum "$FIXTURE_ARCHIVE" | awk '{print $1}')"
	MANIFEST_JSON="$(fixture_manifest "$version" "$url" "$sha512")"
	printf '%s\n' $'antigravity_cli\towner\tany\tdotfiles' \
		$'antigravity_cli\tkind\tany\tsoftware' $'antigravity_cli\tversion\tany\t'"$version" \
		$'antigravity_cli\tarchive\tany\ttar' $'antigravity_cli\tbinary\tany\tantigravity' \
		$'antigravity_cli\turl\tany\t'"$url" \
		$'antigravity_cli\tdigest\tany\tsha512:'"$sha512" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-agy"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-agy"
	curl() {
		local out='' request=''
		while (($#)); do
			case "$1" in -o)
				out="$2"
				shift
				;;
			https://*) request="$1" ;; esac
			shift
		done
		[[ "$request" == "$FIXTURE_URL" && -n "$out" ]] || return 97
		cp -- "$FIXTURE_ARCHIVE" "$out"
	}
	antigravity_curl() {
		local out=''
		while [[ $# -gt 0 ]]; do
			if [[ "$1" == -o ]]; then
				out="$2"
				shift 2
				continue
			fi
			shift
		done
		if [[ -n "$out" ]]; then
			cp -- "$FIXTURE_ARCHIVE" "$out"
		else
			printf '%s\n' "$MANIFEST_JSON"
		fi
	}
	antigravity_platform() { printf 'linux_amd64\n'; }
}

reset_home() {
	rm -rf -- "$HOME/.local/bin/agy" "$HOME/.local/share/dotfiles-catalog" "$AGY_CALLS"
	printf '# sentinel bashrc\n' >"$HOME/.bashrc"
	printf '# sentinel profile\n' >"$HOME/.profile"
	PATH=/usr/bin:/bin
	make_agy_archive 1.3.4
	stub_release_host 1.3.4
}

test_fresh_install_places_verified_binary_and_leaves_profiles_alone() (
	reset_home
	make_agy_archive 1.3.4
	stub_release_host 1.3.4
	install_antigravity_cli >/dev/null || return 1
	[[ "$("$HOME/.local/bin/agy" --version)" == 1.3.4 ]] || return 1
	[[ ! -e "$HOME/.local/bin/LICENSE" ]] || return 1
	[[ "$(<"$HOME/.bashrc")" == '# sentinel bashrc' ]] || return 1
	[[ "$(<"$HOME/.profile")" == '# sentinel profile' ]] || return 1
	[[ ! -s "$AGY_CALLS" ]]
)

test_checksum_mismatch_refuses_installation() (
	reset_home
	make_agy_archive 1.3.4
	stub_release_host 1.3.4 "$FIXTURE_URL" "$(printf '0%.0s' {1..128})"
	! install_antigravity_cli >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/agy" ]]
)

test_manifest_pointing_outside_the_release_bucket_is_refused() (
	reset_home
	make_agy_archive 1.3.4
	stub_release_host 1.3.4 'https://example.com/cli_linux_x64.tar.gz'
	! antigravity_manifest_metadata linux_amd64 >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/agy" ]]
)

test_malformed_manifest_is_refused() (
	reset_home
	make_agy_archive 1.3.4
	stub_release_host 1.3.4
	MANIFEST_JSON='<html>proxy error</html>'
	! antigravity_manifest_metadata linux_amd64 >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/agy" ]]
)

test_archive_without_the_binary_is_refused() (
	reset_home
	make_agy_archive 1.3.4 LICENSE
	stub_release_host 1.3.4
	! install_antigravity_cli >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/agy" ]]
)

test_archive_member_escaping_the_extraction_directory_is_refused() (
	reset_home
	make_agy_archive 1.3.4
	tar -czf "$FIXTURE_ARCHIVE" -C "$TEST_HARNESS_ROOT/agy-fixture" \
		--transform 's|^LICENSE|../escape|' antigravity LICENSE
	stub_release_host 1.3.4
	! install_antigravity_cli >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/agy" ]]
)

test_binary_reporting_another_version_is_refused() (
	reset_home
	make_agy_archive 1.3.3
	stub_release_host 1.3.4
	! install_antigravity_cli >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/agy" ]]
)

test_existing_binary_is_kept_without_force() (
	reset_home
	mkdir -p "$HOME/.local/bin"
	printf '#!/usr/bin/env bash\nprintf "1.0.0\\n"\n' >"$HOME/.local/bin/agy"
	chmod +x "$HOME/.local/bin/agy"
	antigravity_curl() { return 97; }
	install_antigravity_cli >/dev/null || return 1
	[[ "$("$HOME/.local/bin/agy")" == 1.0.0 ]]
)

test_unsupported_architecture_fails_closed() (
	reset_home
	uname() {
		case "$1" in
		-s) printf 'Linux\n' ;;
		-m) printf 'riscv64\n' ;;
		*) return 97 ;;
		esac
	}
	! install_antigravity_cli >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/agy" ]]
)

test_downloads_ask_for_compressed_responses() (
	local args="$TEST_HARNESS_ROOT/curl.args"
	curl() { printf '%s\n' "$@" >"$args"; }
	antigravity_curl https://example.invalid/manifest.json
	grep -Fqx -- --compressed "$args" &&
		grep -Fqx -- '=https' "$args" &&
		grep -Fqx -- --connect-timeout "$args"
)

test_manifest_lookup_is_time_bounded() (
	local args="$TEST_HARNESS_ROOT/manifest.args"
	antigravity_curl() {
		printf '%s\n' "$@" >"$args"
		return 1
	}
	! antigravity_manifest_metadata linux_amd64 || return 1
	grep -Fqx -- --max-time "$args"
)

test_update_check_reads_installed_and_approved_versions() (
	local fixture_installed expected
	while IFS='|' read -r fixture_installed expected; do
		reset_home
		if [[ "$fixture_installed" != 'not installed' ]]; then
			local installed_pin="$fixture_installed"
			[[ "$installed_pin" != installed ]] || installed_pin=1.3.3
			make_agy_archive "$installed_pin"
			stub_release_host "$installed_pin"
			install_antigravity_cli >/dev/null || return 1
			if [[ "$fixture_installed" == installed ]]; then
				printf '%s\n' '#!/usr/bin/env bash' 'echo installed' >"$(dotfiles_catalog_root antigravity_cli)/current/payload/antigravity"
			fi
		fi
		make_agy_archive 1.3.4
		stub_release_host 1.3.4
		[[ "$(check_antigravity_cli || true)" == "$expected" ]] || {
			printf 'got %q\n' "$(check_antigravity_cli || true)" >&2
			return 1
		}
	done <<'EOF'
1.3.3|Antigravity CLI|1.3.3|1.3.4|upgrade
1.3.4|Antigravity CLI|1.3.4|1.3.4|current
1.3.5|Antigravity CLI|1.3.5|1.3.4|blocked
installed|Antigravity CLI|installed|1.3.4|blocked
not installed|Antigravity CLI|not installed|1.3.4|skip
EOF
)

test_unapproved_catalog_keeps_the_observed_installed_version() (
	reset_home
	install_antigravity_cli >/dev/null || return 1
	TEST_APPROVED_CATALOG="$TEST_HARNESS_ROOT/missing-catalog"
	[[ "$(check_antigravity_cli 2>/dev/null || true)" == 'Antigravity CLI|1.3.4|—|blocked' ]]
)

test_installed_version_ignores_startup_noise() (
	reset_home
	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' \
		'printf "ERROR: logging before google.Init: I1011 installer.go:27]\n" >&2' \
		'printf "1.3.3\n"' >"$HOME/.local/bin/agy"
	chmod +x "$HOME/.local/bin/agy"
	[[ "$(antigravity_installed_version)" == 1.3.3 ]]
)

test_upgrade_installs_the_pin_without_running_the_cli_updater() (
	reset_home
	make_agy_archive 1.3.3
	stub_release_host 1.3.3
	install_antigravity_cli >/dev/null || return 1
	make_agy_archive 1.3.4
	stub_release_host 1.3.4
	upgrade_antigravity_cli >/dev/null || return 1
	[[ "$("$HOME/.local/bin/agy" --version)" == 1.3.4 ]] || return 1
	[[ ! -s "$AGY_CALLS" ]] || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == updated ]]
)

test_upgrade_skips_when_not_installed() (
	reset_home
	upgrade_antigravity_cli >/dev/null || return 1
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == skipped ]]
)

expect_success 'fresh Antigravity install places the verified binary and leaves shell profiles alone' test_fresh_install_places_verified_binary_and_leaves_profiles_alone
expect_success 'Antigravity checksum mismatch refuses installation' test_checksum_mismatch_refuses_installation
expect_success 'Antigravity manifest pointing outside the release bucket is refused' test_manifest_pointing_outside_the_release_bucket_is_refused
expect_success 'malformed Antigravity manifest is refused' test_malformed_manifest_is_refused
expect_success 'Antigravity archive without the CLI binary is refused' test_archive_without_the_binary_is_refused
expect_success 'Antigravity archive member escaping the extraction directory is refused' test_archive_member_escaping_the_extraction_directory_is_refused
expect_success 'Antigravity binary reporting another version is refused' test_binary_reporting_another_version_is_refused
expect_success 'existing Antigravity binary is kept without force' test_existing_binary_is_kept_without_force
expect_success 'unsupported Antigravity architecture fails closed' test_unsupported_architecture_fails_closed
expect_success 'Antigravity downloads ask for compressed HTTPS responses' test_downloads_ask_for_compressed_responses
expect_success 'Antigravity manifest lookup is time-bounded' test_manifest_lookup_is_time_bounded
expect_success 'Antigravity update check reads installed and approved versions' test_update_check_reads_installed_and_approved_versions
expect_success 'unapproved catalog retains the observed Antigravity version' test_unapproved_catalog_keeps_the_observed_installed_version
expect_success 'Antigravity installed version ignores startup log noise' test_installed_version_ignores_startup_noise
expect_success 'Antigravity upgrade installs the pin without running its updater' test_upgrade_installs_the_pin_without_running_the_cli_updater
expect_success 'Antigravity upgrade skips when the CLI is not installed' test_upgrade_skips_when_not_installed

finish_tests
