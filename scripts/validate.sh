#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
mode="${1:-check}"

mapfile -t shell_files < <(find "$REPO_DIR" \
	-path "$REPO_DIR/.git" -prune -o \
	-path "$REPO_DIR/log" -prune -o \
	-type f \( -name '*.sh' -o -path "$REPO_DIR/bash/.bashrc" -o -path "$REPO_DIR/bash/.bash_aliases" \
	-o -path "$REPO_DIR/bin/bin/*" -o -path "$REPO_DIR/install.sh" \) -print | sort)
mapfile -t json_files < <(find "$REPO_DIR" \
	-path "$REPO_DIR/.git" -prune -o \
	-path "$REPO_DIR/log" -prune -o \
	-type f -name '*.json' -print | sort)
production_files=()
test_files=()
for shell_file in "${shell_files[@]}"; do
	if [[ "$shell_file" == "$REPO_DIR/tests/"* ]]; then
		test_files+=("$shell_file")
	else
		production_files+=("$shell_file")
	fi
done

case "$mode" in
--format)
	command -v shfmt >/dev/null 2>&1 || {
		echo 'shfmt is required for --format.' >&2
		exit 1
	}
	shfmt -w "${shell_files[@]}"
	;;
check | '') ;;
*)
	echo "Usage: scripts/validate.sh [--format]" >&2
	exit 2
	;;
esac

printf 'Checking Bash syntax...\n'
bash -n "${shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
	printf 'Running ShellCheck on production code...\n'
	# Bash namerefs to associative arrays trigger SC2178/SC2313 false positives.
	shellcheck -x -e SC2034,SC1091,SC2178,SC2313 "${production_files[@]}"
	printf 'Running ShellCheck warning checks on test harnesses...\n'
	# Test namerefs and source-time metadata arrays produce known false positives.
	shellcheck -x -S warning -e SC1091,SC2034,SC2178,SC2313 "${test_files[@]}"
else
	printf 'ShellCheck not installed; skipping static analysis.\n' >&2
fi

if command -v shfmt >/dev/null 2>&1; then
	printf 'Checking shell formatting...\n'
	shfmt -d "${shell_files[@]}"
else
	printf 'shfmt not installed; skipping formatting check.\n' >&2
fi

if ((${#json_files[@]} > 0)); then
	if command -v jq >/dev/null 2>&1; then
		printf 'Checking JSON syntax...\n'
		jq empty "${json_files[@]}"
	else
		printf 'jq not installed; skipping JSON syntax checks.\n' >&2
	fi
fi

printf 'Checking diff whitespace...\n'
git -C "$REPO_DIR" diff --check

"$REPO_DIR/tests/run.sh"
