#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

source "$ROOT/scripts/lib/installers/logging.sh"
# shellcheck source=scripts/lib/updates/common.sh
source "$ROOT/scripts/lib/updates/common.sh"
# shellcheck source=scripts/lib/installers/obsidian.sh
source "$ROOT/scripts/lib/installers/obsidian.sh"

DEB_DIGEST=''

# Releases as the API returns them: the newest is Android-only, one is a
# prerelease, and the first desktop release carries the .deb.
releases_json() {
	cat <<JSON
[
  {"tag_name": "v1.13.8", "draft": false, "prerelease": false,
   "assets": [{"name": "Obsidian-1.13.8.apk", "digest": "sha256:$(printf 'a%.0s' {1..64})",
               "browser_download_url": "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.13.8/Obsidian-1.13.8.apk"}]},
  {"tag_name": "v1.14.0", "draft": false, "prerelease": true,
   "assets": [{"name": "obsidian_1.14.0_amd64.deb", "digest": "sha256:$(printf 'b%.0s' {1..64})",
               "browser_download_url": "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.14.0/obsidian_1.14.0_amd64.deb"}]},
  {"tag_name": "v1.13.7", "draft": false, "prerelease": false,
   "assets": [{"name": "obsidian_1.13.7_amd64.deb", "digest": "sha256:$DEB_DIGEST",
               "browser_download_url": "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.13.7/obsidian_1.13.7_amd64.deb"}]}
]
JSON
}

make_fixture_deb() {
	printf 'fixture deb bytes\n' >"$TEST_HARNESS_ROOT/obsidian.deb"
	DEB_DIGEST="$(sha256sum "$TEST_HARNESS_ROOT/obsidian.deb" | awk '{print $1}')"
}

# github_curl serves the release list, or copies the fixture for a download.
stub_network() {
	github_curl() {
		local out='' arg
		while [[ $# -gt 0 ]]; do
			if [[ "$1" == -o ]]; then
				out="$2"
				shift 2
				continue
			fi
			arg="$1"
			shift
		done
		if [[ -n "$out" ]]; then
			cp -- "$TEST_HARNESS_ROOT/obsidian.deb" "$out"
		else
			releases_json
		fi
	}
}

stub_system() {
	STUB_INSTALLED="${1:-}"
	CALLS="$TEST_HARNESS_ROOT/calls"
	: >"$CALLS"
	dpkg-query() {
		[[ -n "$STUB_INSTALLED" ]] || return 1
		printf 'install ok installed\t%s\n' "$STUB_INSTALLED"
	}
	dpkg-deb() {
		case "$3" in
		Package) printf 'obsidian\n' ;;
		Version) printf '1.13.7\n' ;;
		esac
	}
	sudo() { printf 'sudo %s\n' "$*" >>"$CALLS"; }
	uname() { printf 'x86_64\n'; }
	command() {
		if [[ "$1" == -v && "${2:-}" == obsidian ]]; then return 1; fi
		builtin command "$@"
	}
}

test_metadata_picks_the_newest_desktop_release_with_a_digest() (
	make_fixture_deb
	stub_network
	local -a metadata=()
	mapfile -t metadata < <(obsidian_release_metadata)
	[[ "${metadata[0]}" == 1.13.7 ]] || return 1
	[[ "${metadata[1]}" == obsidian_1.13.7_amd64.deb ]] || return 1
	[[ "${metadata[2]}" == https://github.com/obsidianmd/obsidian-releases/releases/download/v1.13.7/obsidian_1.13.7_amd64.deb ]] || return 1
	[[ "${metadata[3]}" == "$DEB_DIGEST" ]]
)

test_a_deb_without_a_published_digest_fails_closed() (
	make_fixture_deb
	stub_network
	releases_json() {
		command cat <<'JSON'
[{"tag_name": "v1.13.7", "draft": false, "prerelease": false,
  "assets": [{"name": "obsidian_1.13.7_amd64.deb", "digest": null,
              "browser_download_url": "https://github.com/x/y/z.deb"}]}]
JSON
	}
	! obsidian_release_metadata >/dev/null 2>&1
)

test_fresh_install_verifies_then_installs_the_downloaded_file() (
	make_fixture_deb
	stub_network
	stub_system
	DISPLAY=:0
	install_obsidian >/dev/null
	grep -q '^sudo apt-get .*install -y .*/obsidian_1.13.7_amd64.deb$' "$CALLS"
)

test_checksum_mismatch_refuses_installation() (
	make_fixture_deb
	stub_network
	stub_system
	obsidian_install_release 1.13.7 obsidian_1.13.7_amd64.deb https://github.com/x "$(printf 'c%.0s' {1..64})" >/dev/null 2>&1 && return 1
	[[ ! -s "$CALLS" ]]
)

test_a_package_that_is_not_obsidian_is_refused() (
	make_fixture_deb
	stub_network
	stub_system
	dpkg-deb() { [[ "$3" == Package ]] && printf 'something-else\n' || printf '1.13.7\n'; }
	obsidian_install_release 1.13.7 obsidian_1.13.7_amd64.deb https://github.com/x "$DEB_DIGEST" >/dev/null 2>&1 && return 1
	[[ ! -s "$CALLS" ]]
)

test_the_current_version_is_not_reinstalled() (
	make_fixture_deb
	stub_network
	stub_system 1.13.7
	DISPLAY=:0
	install_obsidian >/dev/null
	[[ ! -s "$CALLS" ]]
)

test_an_obsidian_from_elsewhere_is_preserved() (
	make_fixture_deb
	stub_network
	stub_system
	command() {
		if [[ "$1" == -v && "${2:-}" == obsidian ]]; then
			printf '/home/me/Applications/Obsidian.AppImage\n'
			return 0
		fi
		builtin command "$@"
	}
	DISPLAY=:0
	install_obsidian >/dev/null
	[[ ! -s "$CALLS" ]]
)

test_no_gui_display_skips_installation() (
	make_fixture_deb
	stub_network
	stub_system
	unset DISPLAY WAYLAND_DISPLAY
	obsidian_gui_available() { return 1; }
	install_obsidian >/dev/null
	[[ ! -s "$CALLS" ]]
)

test_update_check_reports_each_state() (
	make_fixture_deb
	stub_network
	stub_system
	[[ "$(check_obsidian || true)" == 'Obsidian|not installed|—|skip' ]] || return 1
	stub_system 1.12.7
	[[ "$(check_obsidian || true)" == 'Obsidian|1.12.7|1.13.7|upgrade' ]] || return 1
	stub_system 1.13.7
	[[ "$(check_obsidian || true)" == 'Obsidian|1.13.7|1.13.7|current' ]]
)

test_update_upgrades_an_older_deb() (
	make_fixture_deb
	stub_network
	stub_system 1.12.7
	upgrade_obsidian >/dev/null
	[[ "$UPGRADE_STEP_ACTIVE_RESULT" == updated ]] || return 1
	grep -q 'apt-get .*install -y' "$CALLS"
)

expect_success 'Obsidian release lookup picks the newest desktop release with a digest' test_metadata_picks_the_newest_desktop_release_with_a_digest
expect_success 'Obsidian .deb without a published digest fails closed' test_a_deb_without_a_published_digest_fails_closed
expect_success 'fresh Obsidian install verifies then installs the downloaded file' test_fresh_install_verifies_then_installs_the_downloaded_file
expect_success 'Obsidian checksum mismatch refuses installation' test_checksum_mismatch_refuses_installation
expect_success 'a package that is not Obsidian is refused' test_a_package_that_is_not_obsidian_is_refused
expect_success 'the current Obsidian version is not reinstalled' test_the_current_version_is_not_reinstalled
expect_success 'an Obsidian installed another way is preserved' test_an_obsidian_from_elsewhere_is_preserved
expect_success 'no GUI display skips the Obsidian install' test_no_gui_display_skips_installation
expect_success 'Obsidian update check reports each state' test_update_check_reports_each_state
expect_success 'Obsidian update upgrades an older .deb' test_update_upgrades_an_older_deb

finish_tests
