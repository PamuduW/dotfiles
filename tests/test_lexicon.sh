#!/usr/bin/env bash
# The presentation contract's lexicon rule, checked over this repository.
#
# The rule and the checker live in dotfiles-shared, because both products print
# to the same operator and must not drift into two vocabularies again. This file
# only says which of this repository's trees the operator reads.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/shared_resolve.sh
source "$ROOT/scripts/lib/shared_resolve.sh"
dotfiles_shared_require "$ROOT" || exit 1

if ! output="$("${DOTFILES_PYTHON:-python3}" \
	"$DOTFILES_SHARED_ROOT/tests/lib/shared/lexicon.py" \
	"$ROOT" 'scripts/**/*.sh' 'bin/bin/*' 2>&1)"; then
	printf '%s\n' "$output"
	printf 'not ok - surfaces use one vocabulary and sentence-case headings\n'
	exit 1
fi

printf 'ok - surfaces use one vocabulary and sentence-case headings\n'
printf '\nRan 1 lexicon test(s); 0 failure(s).\n'
