#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
[[ -f "$root/scripts/catalog/qualify-user-tools.py" ]] || {
	printf 'FAIL: missing real user-tools driver\n' >&2
	exit 1
}
rc=0
python3 "$root/scripts/catalog/qualify-user-tools.py" "$temporary/missing-context" \
	--output "$temporary/evidence.json" >"$temporary/output" 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$temporary/evidence.json" ]]
! rg -q Traceback "$temporary/output"
printf 'PASS: invalid user-tools context cannot start installation or write evidence\n'
