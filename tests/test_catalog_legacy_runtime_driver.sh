#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
driver="$root/scripts/catalog/qualify-legacy-runtimes.sh"
[[ -f "$driver" ]] || {
	echo 'FAIL: missing real legacy runtime migration driver' >&2
	exit 1
}
mkdir "$temporary/home"
printf 'preserve\n' >"$temporary/home/user-state"
status=0
HOME="$temporary/home" bash "$driver" "$temporary/missing-context" "$temporary/evidence.json" >"$temporary/log" 2>&1 || status=$?
[[ "$status" == 2 && ! -e "$temporary/evidence.json" ]]
[[ "$(cat "$temporary/home/user-state")" == preserve ]]
[[ "$(find "$temporary/home" -mindepth 1 | wc -l)" == 1 ]]
printf 'PASS: legacy runtime driver refuses unsupported input without changing the home\n'
# Load only the assertion functions; never execute the vendor fixture locally.
sed -n '/^verify_preserved_state() {$/,/^}$/p; /^expect_failed_download() {$/,/^}$/p' "$driver" >"$temporary/assertions.sh"
# shellcheck source=/dev/null
source "$temporary/assertions.sh"
declare -F verify_preserved_state >/dev/null
declare -F expect_failed_download >/dev/null
export HOME="$temporary/home" NVM_DIR="$temporary/home/.nvm"
mkdir -p "$NVM_DIR/versions/node/v1.0.0/bin" "$NVM_DIR/versions/node/v2.0.0/bin"
printf '%s\n' '#!/bin/sh' 'printf legacy-preserved' >"$NVM_DIR/versions/node/v1.0.0/bin/legacy-runtime-probe"
chmod +x "$NVM_DIR/versions/node/v1.0.0/bin/legacy-runtime-probe"
export PATH="$NVM_DIR/versions/node/v1.0.0/bin:$PATH"
printf 'fund=false\n' >"$HOME/.npmrc"
printf 'legacy-other 1.0\n' >"$HOME/.tool-versions"
dotfiles_catalog_get() { printf '2.0.0\n'; }
if verify_preserved_state; then
	echo 'FAIL: retained old global command masked a missing migrated command' >&2
	exit 1
fi
cp "$NVM_DIR/versions/node/v1.0.0/bin/legacy-runtime-probe" "$NVM_DIR/versions/node/v2.0.0/bin/legacy-runtime-probe"
verify_preserved_state
early_failure() { return 2; }
download_failure() { dotfiles_catalog_download nodejs unused || return $?; }
swallowed_failure() { dotfiles_catalog_download nodejs unused || true; }
if expect_failed_download early_failure "$temporary/early"; then exit 1; fi
if expect_failed_download swallowed_failure "$temporary/swallowed"; then exit 1; fi
expect_failed_download download_failure "$temporary/reached"
printf 'PASS: preservation and failure assertions reject false-positive evidence\n'
