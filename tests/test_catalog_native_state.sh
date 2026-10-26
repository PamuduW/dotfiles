#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$REPO_DIR/scripts/lib/catalog_state.sh"
export NVM_DIR="$HOME/.nvm"
prefix="$NVM_DIR/versions/node/v24.1.0"
mkdir -p "$prefix/bin" "$HOME/.local/bin" "$HOME/.local/share/dotfiles-catalog"
printf '%s\n' '#!/usr/bin/env bash' 'echo "v24.1.0"' >"$prefix/bin/node"
chmod +x "$prefix/bin/node"
ln -s "$prefix/bin/node" "$HOME/.local/bin/node"
receipt="$HOME/.local/share/dotfiles-catalog/nodejs.native"
printf 'native-runtime-v1\nnvm\n24.1.0\n%064d\n%040d\n%s\n%064d\n' 0 0 "$prefix" 0 >"$receipt"
if ! dotfiles_catalog_owned nodejs; then
	echo 'FAIL: native NVM ownership is not recognized' >&2
	exit 1
fi
cp "$receipt" "$TEST_HARNESS_ROOT/receipt.before"
printf corrupt >"$receipt"
if dotfiles_catalog_owned nodejs; then
	echo 'FAIL: malformed native receipt accepted' >&2
	exit 1
fi
cp "$TEST_HARNESS_ROOT/receipt.before" "$receipt"
external="$HOME/external"
mkdir -p "$external"
cp "$prefix/bin/node" "$external/node"
rm "$prefix/bin/node"
ln -s "$external/node" "$prefix/bin/node"
if dotfiles_catalog_owned nodejs; then
	echo 'FAIL: native binary escaped its owned prefix' >&2
	exit 1
fi
printf 'PASS: native NVM ownership requires bounded paths and exact receipt structure\n'
