#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
test_harness_report_init

# A real chrome-headless-shell on the machine running the tests must never
# stand in for the fixture.
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"

source "$ROOT/scripts/lib/installers/logging.sh"
# shellcheck source=scripts/lib/installers/chrome_headless.sh
source "$ROOT/scripts/lib/installers/chrome_headless.sh"

uname() {
	case "$1" in
	-s) printf 'Linux\n' ;;
	-m) printf 'x86_64\n' ;;
	*) command uname "$@" ;;
	esac
}

fixture_url() {
	printf 'https://storage.googleapis.com/chrome-for-testing-public/%s/linux64/chrome-headless-shell-linux64.zip\n' "$1"
}

# make_archive <version> [reported-version] [extra-member]: a build whose shell
# prints the reported version (default <version>). An extra member named
# ESCAPE becomes ../escape; any other is added at the archive's top level.
make_archive() {
	local version="$1" reported="${2:-$1}" extra="${3:-}" dir archive
	dir="$TEST_HARNESS_ROOT/fixture/chrome-headless-shell-linux64"
	rm -rf -- "$TEST_HARNESS_ROOT/fixture"
	mkdir -p "$dir"
	printf '%s\n' '#!/usr/bin/env bash' "echo 'Google Chrome for Testing $reported'" >"$dir/chrome-headless-shell"
	chmod +x "$dir/chrome-headless-shell"
	printf 'resources\n' >"$dir/resources.pak"
	archive="$TEST_HARNESS_ROOT/chrome-headless-shell-linux64.zip"
	rm -f -- "$archive"
	(cd "$TEST_HARNESS_ROOT/fixture" && python3 -c '
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for root, _, files in os.walk("chrome-headless-shell-linux64"):
        for name in files:
            path = os.path.join(root, name)
            info = zipfile.ZipInfo.from_file(path, path)
            with open(path, "rb") as handle:
                z.writestr(info, handle.read())
    extra = sys.argv[2]
    if extra == "ESCAPE":
        z.writestr("../escape", "x")
    elif extra:
        z.writestr(extra, "x")
' "$archive" "$extra")
	printf '%s\n' "$archive"
}

# serve <version> <archive>: the version list and the download.
serve() {
	SERVED_VERSION="$1"
	SERVED_ARCHIVE="$2"
	local digest
	digest="$(sha256sum "$SERVED_ARCHIVE")"
	printf '%s\n' $'chrome_headless\towner\tany\tdotfiles' $'chrome_headless\tkind\tany\tsoftware' \
		$'chrome_headless\tversion\tany\t'"$SERVED_VERSION" $'chrome_headless\tarchive\tany\tzip' \
		$'chrome_headless\tbinary\tany\tchrome-headless-shell-linux64/chrome-headless-shell' \
		$'chrome_headless\turl\tany\t'"$(fixture_url "$SERVED_VERSION")" \
		$'chrome_headless\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-chrome"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-chrome"
	chrome_headless_versions_json() {
		printf '{"channels":{"Stable":{"version":"%s","downloads":{"chrome-headless-shell":[{"platform":"linux64","url":"%s"}]}}}}\n' \
			"$SERVED_VERSION" "$(fixture_url "$SERVED_VERSION")"
	}
	curl() {
		printf 'download:%s\n' "${*: -1}" >>"$TEST_URL_LOG"
		local output=''
		while (($#)); do
			if [[ "$1" == -o ]]; then
				output="$2"
				break
			fi
			shift
		done
		[[ -n "$output" ]] || return 97
		cp -- "$SERVED_ARCHIVE" "$output"
	}
}

reset_home() {
	rm -rf -- "$HOME/.local" "$TEST_URL_LOG"
	mkdir -p "$(dirname -- "$TEST_URL_LOG")"
	: >"$TEST_URL_LOG"
}

own() {
	serve "$1" "$(make_archive "$1")"
	install_chrome_headless >/dev/null
	: >"$TEST_URL_LOG"
}

test_fresh_install_unpacks_the_build_links_it_and_stamps_it() (
	reset_home
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39)"

	install_chrome_headless >/dev/null || return 1

	[[ -L "$HOME/.local/bin/chrome-headless-shell" ]] || return 1
	[[ -f "$HOME/.local/share/dotfiles-catalog/chrome_headless/current/payload/chrome-headless-shell-linux64/resources.pak" ]] || return 1
	[[ "$(chrome_headless_installed_tag)" == 155.0.8059.39 ]] || return 1
	[[ "$(<"$HOME/.local/share/dotfiles/chrome_headless.version")" == 155.0.8059.39 ]] || return 1
	grep -Fqx "download:$(fixture_url 155.0.8059.39)" "$TEST_URL_LOG" || return 1
	chrome_headless_is_dotfiles_owned
)

test_a_build_reporting_another_version_is_refused() (
	reset_home
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39 154.0.0.1)"

	! install_chrome_headless >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/chrome-headless-shell" && ! -e "$HOME/.local/share/chrome-headless-shell" ]] || return 1
	[[ ! -e "$HOME/.local/share/dotfiles/chrome_headless.version" ]]
)

test_an_archive_member_escaping_the_directory_is_refused() (
	reset_home
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39 155.0.8059.39 ESCAPE)"
	! install_chrome_headless >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/share/chrome-headless-shell" ]] || return 1

	serve 155.0.8059.39 "$(make_archive 155.0.8059.39 155.0.8059.39 stray-top-level)"
	! install_chrome_headless >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/share/chrome-headless-shell" ]]
)

test_metadata_refuses_a_url_outside_the_bucket() (
	chrome_headless_versions_json() {
		printf '%s\n' '{"channels":{"Stable":{"version":"155.0.8059.39","downloads":{"chrome-headless-shell":[{"platform":"linux64","url":"https://example.com/chrome-headless-shell-linux64.zip"}]}}}}'
	}
	! chrome_headless_latest_metadata >/dev/null || return 1

	chrome_headless_versions_json() {
		printf '%s\n' '{"channels":{"Stable":{"version":"latest","downloads":{}}}}'
	}
	! chrome_headless_latest_metadata >/dev/null
)

test_an_external_shell_is_preserved_even_when_forced() (
	reset_home
	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' "echo 'Google Chrome for Testing 1.0.0.0'" >"$HOME/.local/bin/chrome-headless-shell"
	chmod +x "$HOME/.local/bin/chrome-headless-shell"
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39)"

	DOTFILES_FORCE_REINSTALL=1 install_chrome_headless >/dev/null 2>&1 || return 1
	[[ ! -L "$HOME/.local/bin/chrome-headless-shell" && ! -s "$TEST_URL_LOG" ]] || return 1
	[[ "$(chrome_headless_installed_tag)" == 1.0.0.0 ]]
)

test_update_replaces_an_owned_build_and_its_stamp() (
	reset_home
	own 154.0.7000.1
	upgrade_result_set() { printf '%s\n' "$1" >"$TEST_HARNESS_ROOT/result"; }
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39)"

	upgrade_chrome_headless >/dev/null || return 1
	[[ "$(chrome_headless_installed_tag)" == 155.0.8059.39 ]] || return 1
	[[ "$(<"$HOME/.local/share/dotfiles/chrome_headless.version")" == 155.0.8059.39 ]] || return 1
	[[ "$(<"$TEST_HARNESS_ROOT/result")" == updated ]] || return 1
	! compgen -G "$HOME/.local/share/chrome-headless-shell.previous.*" >/dev/null || return 1

	upgrade_chrome_headless >/dev/null || return 1
	[[ "$(<"$TEST_HARNESS_ROOT/result")" == already-current ]]
)

test_update_without_an_approved_pin_preserves_the_build() (
	reset_home
	own 154.0.7000.1
	TEST_APPROVED_CATALOG="$TEST_HARNESS_ROOT/missing-chrome-catalog"

	! upgrade_chrome_headless >/dev/null 2>&1 || return 1
	[[ "$(chrome_headless_installed_tag)" == 154.0.7000.1 ]]
)

test_update_check_reports_installed_available_and_action() (
	reset_home
	local row
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39)"
	row="$(check_chrome_headless || true)"
	[[ "$row" == 'Chrome headless shell|not installed|155.0.8059.39|skip' ]] || return 1

	own 154.0.7000.1
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39)"
	row="$(check_chrome_headless)" || return 1
	[[ "$row" == 'Chrome headless shell|154.0.7000.1|155.0.8059.39|upgrade' ]] || return 1

	rm -f -- "$HOME/.local/share/dotfiles-catalog/chrome_headless/current/.catalog-receipt"
	row="$(check_chrome_headless || true)"
	[[ "$row" == 'Chrome headless shell|external installation|155.0.8059.39|external' ]]
)

test_unsupported_architecture_fails_closed() (
	reset_home
	serve 155.0.8059.39 "$(make_archive 155.0.8059.39)"
	uname() {
		case "$1" in
		-s) printf 'Linux\n' ;;
		-m) printf 'riscv64\n' ;;
		esac
	}
	! chrome_headless_platform >/dev/null || return 1
	! install_chrome_headless >/dev/null 2>&1
)

expect_success 'a fresh install unpacks the build, links it and stamps it' test_fresh_install_unpacks_the_build_links_it_and_stamps_it
expect_success 'a build reporting another version is refused' test_a_build_reporting_another_version_is_refused
expect_success 'an archive member outside the build directory is refused' test_an_archive_member_escaping_the_directory_is_refused
expect_success 'version metadata refuses a URL outside the Chrome for Testing bucket' test_metadata_refuses_a_url_outside_the_bucket
expect_success 'an external shell is preserved, forced or not' test_an_external_shell_is_preserved_even_when_forced
expect_success 'update replaces an owned build and its stamp' test_update_replaces_an_owned_build_and_its_stamp
expect_success 'update without an approved pin preserves the build' test_update_without_an_approved_pin_preserves_the_build
expect_success 'update check reports installed, available and action' test_update_check_reports_installed_available_and_action
expect_success 'an unsupported architecture fails closed' test_unsupported_architecture_fails_closed

finish_tests
