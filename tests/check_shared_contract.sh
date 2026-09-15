#!/usr/bin/env bash
# The vendored copy is gone, so there is no drift to check. What can still go
# wrong is version skew: this checkout and the dotfiles-shared checkout beside
# it moving independently. Resolving it here fails the gate with the required
# and found revisions rather than letting a suite die on a missing source.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/shared_resolve.sh
source "$ROOT/scripts/lib/shared_resolve.sh"
dotfiles_shared_require "$ROOT" || exit 1

printf 'Shared CONTRACT %s satisfied by %s\n' \
	"$DOTFILES_SHARED_CONTRACT_REQUIRED" "$DOTFILES_SHARED_ROOT"
