#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# Both tools now report whether their checkout has updates waiting. Knowing
# requires a fetch, so the reading is separated from the asking exactly as the
# component probes are: every state is one call, and none of them needs a
# repository in that state to exist.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=scripts/lib/shared_resolve.sh
source "$REPO_DIR/scripts/lib/shared_resolve.sh"
dotfiles_shared_require "$REPO_DIR" || exit 1
export PYTHONDONTWRITEBYTECODE=1

if ! command -v python3 >/dev/null 2>&1; then
	printf 'ok - repo status skipped; python3 unavailable\n'
	exit 0
fi

passed=0
failed=0
py() { python3 -c "
import sys
sys.path.insert(0, '$DOTFILES_SHARED_LIB/python')
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

if python3 - "$DOTFILES_SHARED_LIB/python" <<'PY'; then
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, sys.argv.pop())
import repo_status as rs


class LocalHistoryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / "repo"
        (self.repo / ".git").mkdir(parents=True)
        binary = self.root / "bin"
        binary.mkdir()
        git = binary / "git"
        git.write_text('''#!/bin/sh
case "$3" in
rev-parse) printf 'origin/main\\n' ;;
fetch) printf 'fetch\\n' >>"$GIT_CALLS"; exit "${GIT_FETCH_STATUS:-0}" ;;
rev-list)
    case "$GIT_COUNT_CASE" in
    failed) exit 9 ;;
    timeout) /bin/sleep 1 ;;
    *) printf '%s\\n' "$GIT_COUNTS" ;;
    esac ;;
*) exit 99 ;;
esac
''')
        git.chmod(0o755)
        self.calls = self.root / "calls"
        environment = {
            "PATH": str(binary), "HOME": str(self.root), "GIT_CALLS": str(self.calls),
            "GIT_COUNT_CASE": "counts", "GIT_COUNTS": "0 0", "GIT_FETCH_STATUS": "0",
        }
        patcher = patch.dict(os.environ, environment)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_unavailable_history_is_never_reported_current(self):
        for kind, counts in (
            ("failed", ""), ("timeout", ""), ("counts", ""), ("counts", "0"),
            ("counts", "0 0 extra"), ("counts", "zero 0"), ("counts", "-1 0"),
            ("counts", "0 1.5"), ("counts", "+1 0"), ("counts", "١ 0"),
        ):
            for fetch in (False, True):
                with self.subTest(kind=kind, counts=counts, fetch=fetch):
                    self.calls.unlink(missing_ok=True)
                    with patch.dict(os.environ, {"GIT_COUNT_CASE": kind, "GIT_COUNTS": counts}):
                        try:
                            actual = rs.check(self.repo, timeout=0.05, fetch=fetch)
                        except ValueError as error:
                            actual = f"raised {type(error).__name__}"
                    self.assertEqual("origin/main: unchecked (local history unavailable)|check", actual)
                    self.assertEqual("fetch\n" if fetch else "",
                                     self.calls.read_text() if self.calls.exists() else "")

    def test_successful_local_counts_remain_network_quiet(self):
        for counts, expected in (
            ("0 0", "origin/main: up to date as of last fetch|ok"),
            ("0 3", "origin/main: 3 commit(s) behind as of last fetch — run update|check"),
            ("2 0", "origin/main: 2 commit(s) ahead, nothing to pull|ok"),
            ("2 3", "origin/main: diverged, 2 ahead and 3 behind as of last fetch|check"),
        ):
            with self.subTest(counts=counts), patch.dict(os.environ, {"GIT_COUNTS": counts}):
                self.assertEqual(expected, rs.check(self.repo))
                self.assertFalse(self.calls.exists())

    def test_failed_fetch_stays_unchecked_with_valid_local_counts(self):
        with patch.dict(os.environ, {"GIT_FETCH_STATUS": "9"}):
            self.assertEqual("origin/main: unchecked (fetch failed or timed out)|skipped",
                             rs.check(self.repo, fetch=True))
        self.assertEqual("fetch\n", self.calls.read_text())


unittest.main()
PY
	passed=$((passed + 1))
else
	failed=$((failed + 1))
fi

printf '\nRan %d repo-status test(s); %d failure(s).\n' "$((passed + failed))" "$failed"
((failed == 0))
