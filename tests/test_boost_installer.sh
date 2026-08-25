#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

source "$ROOT/scripts/lib/installers/logging.sh"
if [[ -f "$ROOT/scripts/lib/installers/boost.sh" ]]; then
	# shellcheck source=scripts/lib/installers/boost.sh
	source "$ROOT/scripts/lib/installers/boost.sh"
fi

make_boost_archive() {
	local version="${1:-0.12.6}" fixture_dir="$TEST_HARNESS_ROOT/boost-fixture"
	rm -rf -- "$fixture_dir"
	mkdir -p "$fixture_dir"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		"if [[ \"\${1:-}\" == version ]]; then printf \"boost v${version}\\\\n\"; exit 0; fi" \
		'printf "unexpected boost invocation: %s\\n" "$*" >&2' \
		'exit 97' >"$fixture_dir/boost"
	chmod +x "$fixture_dir/boost"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fixture_dir/boost-ci"
	chmod +x "$fixture_dir/boost-ci"
	tar -czf "$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz" -C "$fixture_dir" boost boost-ci
}

make_boost_archive_with_members() {
	# Same fixture, but the caller chooses the archive member list. Upstream
	# ships a new release every day or two; the gate has to survive a member
	# being added or reordered while still refusing anything that escapes the
	# extraction directory.
	local fixture_dir="$TEST_HARNESS_ROOT/boost-fixture"
	make_boost_archive 0.12.6
	printf 'license\n' >"$fixture_dir/LICENSE"
	tar -czf "$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz" -C "$fixture_dir" "$@"
}

install_fixture_release() {
	local digest
	# Tests share $HOME, and an earlier install would otherwise satisfy the
	# "nothing was installed" assertions in the refusal cases.
	rm -f -- "$HOME/.local/bin/boost"
	digest="$(sha256sum "$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz" | awk '{print $1}')"
	github_curl() {
		local out="" arg
		while [[ $# -gt 0 ]]; do
			[[ "$1" == '-o' ]] && {
				out="$2"
				shift 2
				continue
			}
			arg="$1"
			shift
		done
		cp -- "$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz" "$out"
	}
	boost_platform_arch() { printf 'amd64\n'; }
	boost_install_release v0.12.6 "$digest"
}

test_extra_archive_members_do_not_block_installation() (
	declare -F boost_install_release >/dev/null || return 1
	make_boost_archive_with_members LICENSE boost boost-ci
	install_fixture_release >/dev/null || return 1
	[[ -x "$HOME/.local/bin/boost" ]] || return 1
	[[ ! -e "$HOME/.local/bin/LICENSE" && ! -e "$HOME/.local/bin/boost-ci" ]]
)

test_archive_without_the_boost_binary_is_refused() (
	declare -F boost_install_release >/dev/null || return 1
	make_boost_archive_with_members LICENSE boost-ci
	! install_fixture_release >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/boost" ]]
)

test_archive_member_escaping_the_extraction_directory_is_refused() (
	declare -F boost_install_release >/dev/null || return 1
	local fixture_dir="$TEST_HARNESS_ROOT/boost-fixture"
	make_boost_archive 0.12.6
	tar -czf "$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz" \
		-C "$fixture_dir" --transform 's|^boost-ci|../escape|' boost boost-ci
	! install_fixture_release >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/boost" ]]
)

test_fresh_install_uses_latest_verified_release_and_only_installs_boost_binary() (
	declare -F install_boost_cli >/dev/null || return 1
	local calls="$TEST_HARNESS_ROOT/boost-install.calls" fixture_archive digest
	: >"$calls"
	make_boost_archive 0.12.7
	fixture_archive="$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz"
	digest="$(sha256sum "$fixture_archive" | awk '{print $1}')"
	boost_command() {
		[[ -x "$HOME/.local/bin/boost" ]] || return 1
		printf '%s\n' "$HOME/.local/bin/boost"
	}
	boost_latest_release_metadata() { printf 'v0.12.7\n%s\n' "$digest"; }
	github_curl() {
		printf 'download:%s\n' "${*: -1}" >>"$calls"
		cp "$fixture_archive" "$3"
	}

	install_boost_cli >/dev/null

	[[ "$("$HOME/.local/bin/boost" version)" == 'boost v0.12.7' ]] || return 1
	[[ -f "$HOME/.local/share/dotfiles/boost-cli.version" ]] || return 1
	[[ "$(<"$HOME/.local/share/dotfiles/boost-cli.version")" == 'v0.12.7' ]] || return 1
	grep -Fqx 'download:https://github.com/jfrog/boost/releases/download/v0.12.7/boost-linux-amd64.tar.gz' "$calls" || return 1
	! grep -R -Fq 'boost init' "$HOME"
)

test_update_installs_latest_verified_release_and_advances_stamp() (
	declare -F upgrade_boost_cli >/dev/null || return 1
	local fixture_archive digest
	mkdir -p "$HOME/.local/bin" "$HOME/.local/share/dotfiles"
	printf '%s\n' '#!/usr/bin/env bash' 'printf "boost v0.12.6\\n"' >"$HOME/.local/bin/boost"
	chmod +x "$HOME/.local/bin/boost"
	printf 'v0.12.6\n' >"$HOME/.local/share/dotfiles/boost-cli.version"
	make_boost_archive 0.12.7
	fixture_archive="$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz"
	digest="$(sha256sum "$fixture_archive" | awk '{print $1}')"
	boost_command() { printf '%s\n' "$HOME/.local/bin/boost"; }
	boost_latest_release_metadata() { printf 'v0.12.7\n%s\n' "$digest"; }
	github_curl() { cp "$fixture_archive" "$3"; }

	upgrade_boost_cli >/dev/null

	[[ "$("$HOME/.local/bin/boost" version)" == 'boost v0.12.7' ]] || return 1
	[[ "$(<"$HOME/.local/share/dotfiles/boost-cli.version")" == 'v0.12.7' ]] || return 1
	install_boost_cli >/dev/null
	[[ "$("$HOME/.local/bin/boost" version)" == 'boost v0.12.7' ]]
)

test_update_without_published_digest_preserves_owned_binary() (
	declare -F upgrade_boost_cli >/dev/null || return 1
	mkdir -p "$HOME/.local/bin" "$HOME/.local/share/dotfiles"
	printf '%s\n' '#!/usr/bin/env bash' 'printf "boost v0.12.6\\n"' >"$HOME/.local/bin/boost"
	chmod +x "$HOME/.local/bin/boost"
	printf 'v0.12.6\n' >"$HOME/.local/share/dotfiles/boost-cli.version"
	boost_command() { printf '%s\n' "$HOME/.local/bin/boost"; }
	boost_latest_release_metadata() { return 1; }

	if upgrade_boost_cli >/dev/null 2>&1; then
		return 1
	fi
	[[ "$("$HOME/.local/bin/boost" version)" == 'boost v0.12.6' ]] || return 1
	[[ "$(<"$HOME/.local/share/dotfiles/boost-cli.version")" == 'v0.12.6' ]]
)

test_latest_metadata_returns_matching_tag_and_asset_digest() (
	declare -F boost_latest_release_metadata >/dev/null || return 1
	local output
	github_api_release_json() {
		[[ "$1" == 'jfrog/boost' ]] || return 97
		printf '%s\n' '{"tag_name":"v0.12.7","assets":[{"name":"boost-linux-amd64.tar.gz","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"name":"boost-linux-arm64.tar.gz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}'
	}

	output="$(boost_latest_release_metadata amd64)" || return 1

	[[ "$(sed -n '1p' <<<"$output")" == 'v0.12.7' ]] || return 1
	[[ "$(sed -n '2p' <<<"$output")" == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ]]
)

test_checksum_mismatch_refuses_installation() (
	declare -F install_boost_cli >/dev/null || return 1
	rm -f -- "$HOME/.local/bin/boost" "$HOME/.local/share/dotfiles/boost-cli.version"
	make_boost_archive
	boost_command() { return 1; }
	boost_latest_release_metadata() { printf 'v0.12.7\n%064d\n' 0; }
	github_curl() { cp "$TEST_HARNESS_ROOT/boost-linux-amd64.tar.gz" "$3"; }

	if install_boost_cli >/dev/null 2>&1; then
		return 1
	fi
	[[ ! -e "$HOME/.local/bin/boost" ]]
)

test_fresh_install_without_verifiable_release_metadata_installs_nothing() (
	declare -F install_boost_cli >/dev/null || return 1
	local calls="$TEST_HARNESS_ROOT/boost-metadata-failure.calls"
	: >"$calls"
	rm -f -- "$HOME/.local/bin/boost" "$HOME/.local/share/dotfiles/boost-cli.version"
	boost_command() { return 1; }
	boost_latest_release_metadata() {
		printf 'metadata\n' >>"$calls"
		return 1
	}

	if install_boost_cli >/dev/null 2>&1; then
		return 1
	fi
	[[ ! -e "$HOME/.local/bin/boost" && ! -e "$HOME/.local/share/dotfiles/boost-cli.version" ]] || return 1
	[[ "$(<"$calls")" == 'metadata' ]]
)

test_existing_unowned_binary_is_preserved() (
	declare -F install_boost_cli >/dev/null || return 1
	rm -f -- "$HOME/.local/share/dotfiles/boost-cli.version"
	local calls="$TEST_HARNESS_ROOT/boost-unowned.calls"
	: >"$calls"
	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'printf "boost v9.9.9\\n"' >"$HOME/.local/bin/boost"
	chmod +x "$HOME/.local/bin/boost"
	boost_command() { printf '%s\n' "$HOME/.local/bin/boost"; }
	github_curl() {
		printf 'download\n' >>"$calls"
		return 97
	}

	install_boost_cli >/dev/null

	[[ "$("$HOME/.local/bin/boost" version)" == 'boost v9.9.9' ]] || return 1
	[[ ! -s "$calls" ]]
)

test_unsupported_architecture_fails_closed() (
	declare -F install_boost_cli >/dev/null || return 1
	rm -f -- "$HOME/.local/bin/boost" "$HOME/.local/share/dotfiles/boost-cli.version"
	boost_command() { return 1; }
	uname() {
		case "$1" in
		-s) printf 'Linux\n' ;;
		-m) printf 'riscv64\n' ;;
		*) return 97 ;;
		esac
	}

	! install_boost_cli >/dev/null 2>&1
)

expect_success 'fresh Boost install uses the latest verified release and only installs the CLI binary' test_fresh_install_uses_latest_verified_release_and_only_installs_boost_binary
expect_success 'Boost checksum mismatch refuses installation' test_checksum_mismatch_refuses_installation
expect_success 'fresh Boost install fails closed when release metadata is unverifiable' test_fresh_install_without_verifiable_release_metadata_installs_nothing
expect_success 'existing unowned Boost binary is preserved' test_existing_unowned_binary_is_preserved
expect_success 'unsupported Boost architecture fails closed' test_unsupported_architecture_fails_closed
expect_success 'Boost update installs the latest verified release and advances ownership' test_update_installs_latest_verified_release_and_advances_stamp
expect_success 'Boost update preserves the owned binary when release metadata is unverifiable' test_update_without_published_digest_preserves_owned_binary
expect_success 'Boost update returns the matching release tag and asset digest' test_latest_metadata_returns_matching_tag_and_asset_digest
expect_success 'extra Boost archive members do not block installation' test_extra_archive_members_do_not_block_installation
expect_success 'Boost archive without the CLI binary is refused' test_archive_without_the_boost_binary_is_refused
expect_success 'Boost archive member escaping the extraction directory is refused' test_archive_member_escaping_the_extraction_directory_is_refused

finish_tests
