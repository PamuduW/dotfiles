#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$TEST_DIR/lib/update_test_fixture.sh"
((${#UPDATE_STEP_KEYS[@]} >= 27))
for key in "${UPDATE_STEP_KEYS[@]}"; do
	[[ "$key" == apt ]] && continue
	[[ "${UPDATE_STEP_RETRY[$key]}" == 'dotfiles update' ]] || {
		printf 'FAIL: %s retry bypasses catalog ownership or locks: %s\n' "$key" "${UPDATE_STEP_RETRY[$key]}" >&2
		exit 1
	}
done
sudo() { :; }
npm_available_version() { printf '12.0.2\n'; }
_run_upgrade_step() {
	[[ "$1" == 'apt packages' || "$2" == 'dotfiles update' ]] || {
		printf 'FAIL: actual %s retry bypasses catalog: %s\n' "$1" "$2" >&2
		return 1
	}
	UPGRADE_STEP_RESULT["$1"]=ok
}
_run_update_downstream >/dev/null
printf 'PASS: every managed retry stays within the approved catalog workflow\n'
