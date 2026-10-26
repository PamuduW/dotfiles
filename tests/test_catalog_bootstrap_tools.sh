#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
printf '{"untrusted":"not a qualification context"}\n' >"$TEST_HARNESS_ROOT/context.json"
rc=0
bash "$REPO_DIR/scripts/catalog/bootstrap-tools.sh" "$TEST_HARNESS_ROOT/context.json" "$TEST_HARNESS_ROOT/bootstrap-home" "$TEST_HARNESS_ROOT/tools.json" >"$TEST_HARNESS_ROOT/output" 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$TEST_HARNESS_ROOT/bootstrap-home" && ! -e "$TEST_HARNESS_ROOT/tools.json" ]] || {
	printf 'FAIL: bootstrap tooling did not reject invalid context before mutation (exit %s)\n' "$rc" >&2
	exit 1
}
printf 'PASS: initial discovery tooling rejects invalid qualification context before mutation\n'
