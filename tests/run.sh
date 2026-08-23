#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
failed=0

# This runs the test files only. scripts/validate.sh is the full gate (syntax,
# ShellCheck, shfmt, JSON, whitespace, then this runner) and is what CI calls.
printf 'Running test files only. For the full gate run: scripts/validate.sh\n'

while IFS= read -r test_file; do
	printf '\n== %s ==\n' "$(basename "$test_file")"
	if ! bash "$test_file"; then
		failed=$((failed + 1))
	fi
done < <(find "$TEST_DIR" -maxdepth 1 -type f \( -name 'test_*.sh' -o -name 'regression_paths.sh' \) -print | sort)

if ((failed > 0)); then
	printf '\n%d test file(s) failed.\n' "$failed" >&2
	exit 1
fi
printf '\nAll test files passed.\n'
