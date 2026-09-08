#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# Both tools now report whether their checkout has updates waiting. Knowing
# requires a fetch, so the reading is separated from the asking exactly as the
# component probes are: every state is one call, and none of them needs a
# repository in that state to exist.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1

if ! command -v python3 >/dev/null 2>&1; then
	printf 'ok - repo status skipped; python3 unavailable\n'
	exit 0
fi

passed=0
failed=0
py() { python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/scripts/lib/shared/python')
import repo_status as rs
print(rs.classify($1))
"; }

expect() {
	local label="$1" want="$2" got="$3"
	if [[ "$got" == "$want" ]]; then
		printf 'ok - %s\n' "$label"
		passed=$((passed + 1))
	else
		printf 'not ok - %s\n     want: %s\n     got:  %s\n' "$label" "$want" "$got"
		failed=$((failed + 1))
	fi
}

expect 'up to date' \
	'origin/main: up to date|ok' \
	"$(py "upstream='origin/main', fetched=True, ahead=0, behind=0")"

expect 'behind says what to run' \
	'origin/main: 3 commit(s) behind — run update|check' \
	"$(py "upstream='origin/main', fetched=True, ahead=0, behind=3")"

# Ahead is not a problem to solve: there is nothing to pull, so it is not
# something the operator needs to act on from a status.
expect 'ahead only is ok, not a warning' \
	'origin/main: 2 commit(s) ahead, nothing to pull|ok' \
	"$(py "upstream='origin/main', fetched=True, ahead=2, behind=0")"

expect 'diverged names both counts' \
	'origin/main: diverged, 2 ahead and 3 behind|check' \
	"$(py "upstream='origin/main', fetched=True, ahead=2, behind=3")"

# A failed fetch must never be read as "up to date": that is the one wrong
# answer a status can give here, and it is the shape of defect 5 again.
expect 'a failed fetch is unchecked, never up to date' \
	'origin/main: unchecked (fetch failed or timed out)|skipped' \
	"$(py "upstream='origin/main', fetched=False, ahead=0, behind=0")"

expect 'no upstream is a check, not a skip' \
	'no upstream branch configured|check' \
	"$(py "upstream='', fetched=True, ahead=0, behind=0")"

printf '\nRan %d repo-status test(s); %d failure(s).\n' "$((passed + failed))" "$failed"
((failed == 0))
