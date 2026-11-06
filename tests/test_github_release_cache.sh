#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

# shellcheck source=scripts/lib/github_api.sh
source "$ROOT/scripts/lib/github_api.sh"

fixture_cache() {
	TMPDIR="$(mktemp -d "$TEST_HARNESS_ROOT/cache-test.XXXXXX")"
	github_api_release_json() {
		printf 'request\n' >>"$TMPDIR/requests"
		printf '{"tag_name": "v1.2.3"}\n'
	}
}

test_legacy_poisoned_cache_is_ignored() (
	fixture_cache
	mkdir -p "$TMPDIR/dotfiles-release-cache/$$"
	printf '9.9.9\n' >"$TMPDIR/dotfiles-release-cache/$$/owner__repo"
	[[ "$(github_latest_release_version owner/repo)" == 1.2.3 ]]
)

test_cache_directories_are_private_and_results_survive_subshells() (
	fixture_cache
	local dir
	dir="$(_github_release_cache_dir)" || return 1
	[[ "$(stat -c '%a' "$dir")" == 700 ]] || return 1
	[[ "$(stat -c '%a' "$(dirname -- "$dir")")" == 700 ]] || return 1
	[[ -O "$dir" && ! -L "$dir" ]] || return 1
	[[ "$(github_latest_release_version owner/repo)" == 1.2.3 ]] || return 1
	[[ "$(github_latest_release_version owner/repo)" == 1.2.3 ]] || return 1
	[[ "$(wc -l <"$TMPDIR/requests")" -eq 1 ]]
)

test_untrusted_cache_directory_falls_back_to_api() (
	local kind
	for kind in symlink public; do
		fixture_cache
		local base="$TMPDIR/dotfiles-release-cache-$UID"
		mkdir "$TMPDIR/attacker"
		if [[ "$kind" == symlink ]]; then
			ln -s "$TMPDIR/attacker" "$base"
		else
			mkdir -m 0777 "$base"
			chmod 0777 "$base"
		fi
		! _github_release_cache_dir >/dev/null || return 1
		[[ "$(github_latest_release_version owner/repo)" == 1.2.3 ]] || return 1
		[[ ! -e "$TMPDIR/attacker/$$" ]] || return 1
		[[ -f "$TMPDIR/requests" ]] || return 1
	done
)

test_symlink_entry_is_neither_read_nor_followed_for_write() (
	fixture_cache
	local dir target="$TMPDIR/target"
	dir="$(_github_release_cache_dir)" || return 1
	printf '9.9.9\n' >"$target"
	ln -s "$target" "$dir/owner__repo"
	[[ "$(github_latest_release_version owner/repo)" == 1.2.3 ]] || return 1
	[[ "$(<"$target")" == 9.9.9 ]]
)

test_failed_request_is_not_cached() (
	fixture_cache
	github_api_release_json() { return 1; }
	! github_latest_release_version owner/repo || return 1
	github_api_release_json() { printf '{"tag_name": "v1.2.3"}\n'; }
	[[ "$(github_latest_release_version owner/repo)" == 1.2.3 ]]
)

expect_success 'legacy poisoned release cache is ignored' test_legacy_poisoned_cache_is_ignored
expect_success 'private release cache shares results across subshells' test_cache_directories_are_private_and_results_survive_subshells
expect_success 'untrusted release cache directories fall back to the API' test_untrusted_cache_directory_falls_back_to_api
expect_success 'release cache entry symlinks cannot redirect reads or writes' test_symlink_entry_is_neither_read_nor_followed_for_write
expect_success 'failed release requests are not cached' test_failed_request_is_not_cached
finish_tests
