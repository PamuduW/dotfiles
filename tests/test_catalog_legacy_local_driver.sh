#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
driver="$root/scripts/catalog/qualify-legacy-local.sh"
[[ -f "$driver" ]] || {
	echo 'FAIL: missing real local-tool migration driver' >&2
	exit 1
}
mkdir "$temporary/home"
printf 'preserve\n' >"$temporary/home/user-state"
status=0
HOME="$temporary/home" bash "$driver" "$temporary/missing-context" "$temporary/evidence.json" >"$temporary/log" 2>&1 || status=$?
[[ "$status" == 2 && ! -e "$temporary/evidence.json" ]]
[[ "$(cat "$temporary/home/user-state")" == preserve ]]
[[ "$(find "$temporary/home" -mindepth 1 | wc -l)" == 1 ]]
printf 'PASS: local migration driver rejects invalid context without changing the home\n'
