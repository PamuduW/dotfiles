#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
source "$REPO_DIR/scripts/lib/software_catalog.sh"
if ! declare -F dotfiles_catalog_npm_runtime >/dev/null; then
	echo 'FAIL: approved npm runtime resolver is missing' >&2
	exit 1
fi
export NVM_DIR="$HOME/.nvm"
prefix="$NVM_DIR/versions/node/v24.1.0"
mkdir -p "$prefix/bin" "$prefix/lib/node_modules/npm/bin" "$HOME/.local/bin" "$HOME/.local/share/dotfiles-catalog"
printf '%s\n' '#!/usr/bin/env bash' 'echo v24.1.0' >"$prefix/bin/node"
printf '%s\n' '#!/usr/bin/env bash' 'echo 12.0.2' >"$prefix/lib/node_modules/npm/bin/npm-cli.js"
chmod +x "$prefix/bin/node" "$prefix/lib/node_modules/npm/bin/npm-cli.js"
ln -s ../lib/node_modules/npm/bin/npm-cli.js "$prefix/bin/npm"
ln -s "$prefix/bin/node" "$HOME/.local/bin/node"
ln -s "$prefix/bin/npm" "$HOME/.local/bin/npm"
printf '%s\n' $'nodejs\towner\tany\tdotfiles' $'nodejs\tversion\tany\t24.1.0' \
	$'npm\towner\tany\tdotfiles' $'npm\tversion\tany\t12.0.2' | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog"
catalog_fixture_use "$TEST_HARNESS_ROOT/catalog"
printf 'native-runtime-v1\nnvm\n24.1.0\n%064d\n%040d\n%s\n%064d\n' 0 0 "$prefix" 0 >"$HOME/.local/share/dotfiles-catalog/nodejs.native"
printf 'native-runtime-v1\nnvm\n12.0.2\n%064d\n%040d\n%s\n%064d\n' 0 0 "$prefix" 0 >"$HOME/.local/share/dotfiles-catalog/npm.native"
resolved="$(dotfiles_catalog_npm_runtime)"
[[ "$resolved" == "$prefix/bin/node"$'\n'"$prefix/bin/npm" ]]
printf '%s\n' '#!/usr/bin/env bash' 'echo v24.0.0' >"$prefix/bin/node"
if dotfiles_catalog_npm_runtime; then
	echo 'FAIL: npm resolver accepted a stale owned Node version' >&2
	exit 1
fi
printf '%s\n' '#!/usr/bin/env bash' 'echo v24.1.0' >"$prefix/bin/node"
rm "$HOME/.local/bin/node"
printf '#!/usr/bin/env bash\n: >%q\necho v24.1.0\n' "$TEST_HARNESS_ROOT/external-executed" >"$HOME/.local/bin/node"
chmod +x "$HOME/.local/bin/node"
if dotfiles_catalog_npm_runtime; then
	echo 'FAIL: npm resolver accepted unowned Node' >&2
	exit 1
fi
[[ ! -e "$TEST_HARNESS_ROOT/external-executed" ]]
printf 'PASS: npm package operations require the owned approved Node/npm runtime before execution\n'
