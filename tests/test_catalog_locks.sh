#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
REAL_NPM="$(command -v npm)"
REAL_NODE="$(command -v node)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$(dirname -- "$REAL_NODE"):$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/installers/npm_cli.sh"
# This suite exercises real npm integrity behavior; native runtime ownership
# is covered separately and replaced here by the fixed local compiler port.
dotfiles_catalog_npm_runtime() { printf '%s\n%s\n' "$REAL_NODE" "$REAL_NPM"; }
fixture="$TEST_HARNESS_ROOT/catalog"
mkdir -p "$fixture/locks" "$TEST_HARNESS_ROOT/package"
cat >"$TEST_HARNESS_ROOT/package/package.json" <<'JSON'
{"name":"cspell","version":"1.2.3","bin":{"cspell":"cli.js"}}
JSON
printf '%s\n' '#!/usr/bin/env node' 'console.log("cspell 1.2.3")' >"$TEST_HARNESS_ROOT/package/cli.js"
chmod +x "$TEST_HARNESS_ROOT/package/cli.js"
(cd "$TEST_HARNESS_ROOT/package" && "$REAL_NPM" pack --ignore-scripts --quiet >/dev/null)
"$REAL_NPM" install --package-lock-only --ignore-scripts --no-audit --no-fund --prefix "$fixture/locks" \
	"$TEST_HARNESS_ROOT/package/cspell-1.2.3.tgz" >/dev/null
lock_digest="$(sha256sum "$fixture/locks/package-lock.json")"
printf '%s\n' $'cspell\towner\tany\tdotfiles' $'cspell\tkind\tany\tsoftware' \
	$'cspell\tversion\tany\t1.2.3' $'cspell\tarchive\tany\tnpm-lock' \
	$'cspell\tpackage\tany\tcspell' $'cspell\tbinary\tany\tnode_modules/.bin/cspell' \
	$'cspell\tlock\tany\tlocks/package-lock.json' $'cspell\tdigest\tany\tsha256:'"${lock_digest%% *}" | catalog_fixture_seal "$fixture"
catalog_fixture_use "$fixture"
install_npm_cli cspell
[[ "$("$HOME/.local/bin/cspell" --version)" == 'cspell 1.2.3' ]]
# Frozen transitive bytes are checked again on every operation.
printf '\n' >>"$fixture/locks/package-lock.json"
if DOTFILES_FORCE_REINSTALL=1 install_npm_cli cspell; then
	echo 'FAIL: changed lock accepted' >&2
	exit 1
fi
[[ "$("$HOME/.local/bin/cspell" --version)" == 'cspell 1.2.3' ]]
printf 'PASS: real npm ci installs from a frozen lock; changed lock preserves command\n'
