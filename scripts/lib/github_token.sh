# shellcheck shell=bash
# GitHub token storage and validation.
#
# The implementation is shared verbatim with the sibling repository and lives in
# scripts/lib/shared/. Edit the shared copy, then run scripts/sync-shared.sh to
# propagate it; the test suite fails if the two copies diverge.

# shellcheck source=scripts/lib/shared/github_token.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/shared/github_token.sh"
