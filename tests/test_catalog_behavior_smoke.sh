#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
[[ -f "$root/scripts/catalog/qualify-behavior.sh" ]] || {
	printf 'FAIL: missing real behavior smoke driver\n' >&2
	exit 1
}
rc=0
bash "$root/scripts/catalog/qualify-behavior.sh" "$temporary/missing-context" \
	"$temporary/evidence.json" >"$temporary/output" 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$temporary/evidence.json" ]]
printf 'PASS: behavior smoke rejects an invalid context before writing evidence\n'
