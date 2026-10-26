#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$TEST_DIR/lib/catalog_fixture.sh"
source "$ROOT/scripts/lib/software_catalog.sh"
trusted="$TEST_HARNESS_ROOT/trusted"
forged="$TEST_HARNESS_ROOT/forged"
catalog_fixture_seal "$trusted" </dev/null
catalog_fixture_seal "$forged" </dev/null
calls=0
# Unit boundary: the shared freezer's actual Git-object provenance is tested
# separately. This assertion proves the product must call that boundary.
software_catalog_begin() {
	calls=$((calls + 1))
	software_catalog_load "$trusted"
}
software_catalog_load "$forged"
dotfiles_catalog_begin
[[ "$calls" == 1 && "$SOFTWARE_CATALOG_SNAPSHOT" == "$trusted" ]] || {
	echo 'FAIL: inherited local approval bypassed the approved Git freezer' >&2
	exit 1
}
dotfiles_catalog_begin
[[ "$calls" == 1 ]]
(
	dotfiles_catalog_begin
	[[ "$calls" == 2 ]]
)
# A newly self-consistent proof at the same pathname is still a different
# snapshot from the one whose Git provenance this process established.
cp -a "$trusted" "$TEST_HARNESS_ROOT/trusted.before"
printf '%s\n' $'newtool\towner\tany\tdotfiles' | catalog_fixture_seal "$trusted"
if dotfiles_catalog_begin; then
	echo 'FAIL: rewritten contents replaced the frozen operation snapshot' >&2
	exit 1
fi
if dotfiles_catalog_get newtool owner >/dev/null 2>&1; then
	echo 'FAIL: rejected snapshot remained accessible to catalog lookups' >&2
	exit 1
fi
rm -rf -- "$trusted"
cp -a "$TEST_HARNESS_ROOT/trusted.before" "$trusted"
SOFTWARE_CATALOG_SNAPSHOT="$forged"
if dotfiles_catalog_begin; then
	echo 'FAIL: the operation snapshot changed after initialization' >&2
	exit 1
fi
printf 'PASS: each operation establishes Git provenance and preserves its snapshot\n'
