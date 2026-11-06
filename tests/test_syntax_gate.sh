#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
test_harness_init
fixture="$TEST_HARNESS_ROOT/syntax-gate"
mkdir -p "$fixture/scripts" "$fixture/tests" "$fixture/bin"
cp "$ROOT/scripts/validate.sh" "$fixture/scripts/validate.sh"
printf 'echo valid\n' >"$fixture/first.sh"
printf 'if then\n' >"$fixture/z broken.sh"
for tool in shellcheck shfmt zizmor git; do
	printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/$tool"
	chmod +x "$fixture/bin/$tool"
done
for script in run.sh check_shared_contract.sh; do
	printf '#!/bin/sh\nexit 0\n' >"$fixture/tests/$script"
	chmod +x "$fixture/tests/$script"
done
if PATH="$fixture/bin:/usr/bin:/bin" bash "$fixture/scripts/validate.sh" >"$fixture/output" 2>&1; then
	printf 'not ok - validation accepted an invalid later script\n' >&2
	exit 1
fi
grep -Fq 'z broken.sh' "$fixture/output"
printf 'echo valid\n' >"$fixture/z broken.sh"
PATH="$fixture/bin:/usr/bin:/bin" bash "$fixture/scripts/validate.sh" >"$fixture/output" 2>&1
printf 'ok - validation checks every script and handles spaces\n'
