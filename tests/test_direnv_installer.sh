#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Repository loaders and indirect test doubles.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

setup_direnv_fixture() {
	HOME="$TEST_HARNESS_ROOT/direnv-$BASHPID"
	mkdir -p "$HOME/.local/bin"
	local old_version="${1:-2.38.2}"
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$old_version" >"$HOME/.local/bin/direnv"
	chmod +x "$HOME/.local/bin/direnv"
	fixture_payload="$HOME/payload"
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "2.38.2"\n' >"$fixture_payload"
	fixture_digest="$(sha256sum "$fixture_payload" | awk '{print $1}')"
	fixture_latest=2.38.2 fixture_mode=ok fixture_arch=x86_64
	fixture_downloads="$HOME/downloads"
	: >"$fixture_downloads"
	DOTFILES_FORCE_REINSTALL=0
	uname() { if [[ "$1" == -m ]]; then printf '%s\n' "$fixture_arch"; else printf 'Linux\n'; fi; }
	github_api_release_json() {
		[[ "$1" == direnv/direnv && "$fixture_mode" != metadata ]] || return 1
		printf '{"tag_name":"v%s","assets":[{"name":"direnv.linux-amd64","digest":"sha256:%s"},{"name":"direnv.linux-arm64","digest":"sha256:%s"}]}\n' \
			"$fixture_latest" "$fixture_digest" "$fixture_digest"
	}
	github_curl() {
		local destination='' arg
		printf '%s\n' "$*" >>"$fixture_downloads"
		while (($#)); do
			arg="$1"
			shift
			if [[ "$arg" == -o ]]; then
				destination="$1"
				shift
			fi
		done
		[[ -n "$destination" ]] || return 1
		if [[ "$fixture_mode" == download ]]; then
			printf 'partial binary' >"$destination"
			return 56
		fi
		cp "$fixture_payload" "$destination"
	}
	run_vendor_shell_installer() {
		printf 'unexpected vendor installer\n' >&2
		return 99
	}
}

test_current_direnv_skips_download_and_repairs_shortcut() (
	setup_direnv_fixture
	local current
	for current in 2.38.2 2.39.0; do
		printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$current" >"$HOME/.local/bin/direnv"
		install_direnv >/dev/null || return 1
		[[ ! -s "$fixture_downloads" ]] || return 1
		[[ "$("$HOME/bin/direnv" version)" == "$current" ]] || return 1
	done
)

test_direnv_upgrade_is_verified_and_download_is_bounded() (
	setup_direnv_fixture 2.37.1
	install_direnv >/dev/null || return 1
	[[ "$("$HOME/.local/bin/direnv" version)" == 2.38.2 ]] || return 1
	[[ "$("$HOME/bin/direnv" version)" == 2.38.2 ]] || return 1
	local args
	args="$(<"$fixture_downloads")"
	[[ "$args" == *'--retry 2'* && "$args" == *'--retry-all-errors'* && "$args" == *'--retry-max-time 180'* ]] || return 1
	[[ "$args" == *'--connect-timeout 10'* && "$args" == *'--max-time 180'* ]] || return 1
	[[ "$args" == *'https://github.com/direnv/direnv/releases/download/v2.38.2/direnv.linux-amd64'* ]]
)

test_forced_and_fresh_direnv_install() (
	setup_direnv_fixture
	DOTFILES_FORCE_REINSTALL=1 install_direnv >/dev/null || return 1
	[[ -s "$fixture_downloads" ]] || return 1
	rm "$HOME/.local/bin/direnv"
	fixture_arch=aarch64
	install_direnv >/dev/null || return 1
	[[ "$("$HOME/.local/bin/direnv" version)" == 2.38.2 ]] || return 1
	grep -q 'direnv.linux-arm64' "$fixture_downloads"
)

test_failed_direnv_refresh_preserves_working_binary() (
	local failure rc before
	for failure in metadata download checksum version missing-digest invalid-tag; do
		setup_direnv_fixture 2.37.1
		before="$(sha256sum "$HOME/.local/bin/direnv")"
		fixture_mode="$failure"
		case "$failure" in
		checksum) printf 'broken download\n' >"$fixture_payload" ;;
		version)
			printf '#!/usr/bin/env bash\nprintf "2.37.1\\n"\n' >"$fixture_payload"
			fixture_digest="$(sha256sum "$fixture_payload" | awk '{print $1}')"
			;;
		missing-digest) fixture_digest='' ;;
		invalid-tag) fixture_latest='../invalid' ;;
		esac
		rc=0
		install_direnv >/dev/null 2>&1 || rc=$?
		[[ "$rc" -ne 0 && "$(sha256sum "$HOME/.local/bin/direnv")" == "$before" ]] || return 1
		[[ -z "$(find "$HOME/.local/bin" -maxdepth 1 -name '.direnv.*' -print -quit)" ]] || return 1
	done
)

expect_success 'current or newer direnv skips downloads and maintains its shortcut' test_current_direnv_skips_download_and_repairs_shortcut
expect_success 'direnv upgrades verify the binary and bound retry downloads' test_direnv_upgrade_is_verified_and_download_is_bounded
expect_success 'forced and fresh direnv installs support the host architecture' test_forced_and_fresh_direnv_install
expect_success 'failed direnv refreshes preserve the working executable and clean temporary files' test_failed_direnv_refresh_preserves_working_binary

test_harness_cleanup
finish_tests
