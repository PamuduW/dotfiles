#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
REAL_NODE="$(readlink -f "$(command -v node)")"
REAL_NPM_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v npm)")")")"
NODE_VERSION="$(node --version)"
NPM_VERSION="$(npm --version)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
source "$REPO_DIR/scripts/lib/software_catalog.sh"
source "$REPO_DIR/scripts/lib/catalog_sources.sh"
source "$REPO_DIR/scripts/lib/installers/cli_tools.sh"
if [[ -f "$REPO_DIR/scripts/lib/catalog_runtimes.sh" ]]; then source "$REPO_DIR/scripts/lib/catalog_runtimes.sh"; fi
if ! declare -F dotfiles_catalog_node_install >/dev/null; then
	echo 'FAIL: native exact Node/npm adapter is missing' >&2
	exit 1
fi
export NVM_DIR="$HOME/.nvm"
tools="$TEST_HARNESS_ROOT/tools"
mkdir "$tools"
for tool in bash python3 uname dirname readlink realpath head grep tr chmod mkdir cp rm mv ln stat sha256sum sha512sum mktemp env tar gzip cat awk sort flock xz timeout find sed basename wc id install; do
	ln -s "$(command -v "$tool")" "$tools/$tool"
done
PATH="$HOME/.local/bin:$tools"
export PATH
bundle="node-v${NODE_VERSION#v}-linux-x64"
mkdir -p "$TEST_HARNESS_ROOT/sdk/$bundle/bin"
cp "$REAL_NODE" "$TEST_HARNESS_ROOT/sdk/$bundle/bin/node"
tar -czf "$TEST_HARNESS_ROOT/node.tgz" -C "$TEST_HARNESS_ROOT/sdk" "$bundle"
tar -czf "$TEST_HARNESS_ROOT/npm.tgz" --transform='s,^npm,package,' -C "${REAL_NPM_ROOT%/*}" npm
node_digest="$(sha256sum "$TEST_HARNESS_ROOT/node.tgz")"
npm_digest="$(sha256sum "$TEST_HARNESS_ROOT/npm.tgz")"
printf '%s\n' $'nodejs\towner\tany\tdotfiles' $'nodejs\tkind\tany\tsoftware' \
	$'nodejs\tversion\tany\t'"${NODE_VERSION#v}" $'nodejs\tarchive\tany\ttar.gz' \
	$'nodejs\tbinary\tany\t'"$bundle/bin/node" $'nodejs\turl\tany\thttps://fixture.invalid/node.tgz' \
	$'nodejs\tdigest\tany\tsha256:'"${node_digest%% *}" \
	$'npm\towner\tany\tdotfiles' $'npm\tkind\tany\tsoftware' $'npm\tversion\tany\t'"$NPM_VERSION" \
	$'npm\tarchive\tany\ttgz' $'npm\tbinary\tany\tpackage/bin/npm-cli.js' \
	$'npm\turl\tany\thttps://fixture.invalid/npm.tgz' $'npm\tdigest\tany\tsha256:'"${npm_digest%% *}" \
	$'nvm\towner\tany\tdotfiles' $'nvm\tkind\tany\tgit-source' $'nvm\tsource\tany\tnvm-sh/nvm' \
	$'nvm\tversion\tany\t0.40.8' $'nvm\trevision\tany\t'"$(printf '%040d' 1)" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog"
catalog_fixture_use "$TEST_HARNESS_ROOT/catalog"
# This unit replaces only the independently tested Git/source operation and
# NVM process. Node ELF, npm closure, native paths/receipts and rollback are real.
TEST_NATIVE_SOURCE_CHECKOUT="$TEST_HARNESS_ROOT/nvm-source"
mkdir -p "$TEST_NATIVE_SOURCE_CHECKOUT" "$(dotfiles_catalog_root nvm)"
cat >"$TEST_NATIVE_SOURCE_CHECKOUT/nvm.sh" <<'NVM'
nvm() {
	case "$1" in
	--version) echo 0.40.8 ;;
	alias) mkdir -p "$NVM_DIR/alias"; printf '%s\n' "$3" >"$NVM_DIR/alias/$2" ;;
	*) return 96 ;;
	esac
}
nvm_get_artifact_compression() { echo tar.gz; }
nvm_install_binary_extract() {
	printf 'extract\n' >>"$TEST_COMMAND_LOG"
	[[ "${TEST_NATIVE_NVM_FAIL:-0}" != 1 ]] || return 27
	mkdir -p "$NVM_DIR/versions/node/$2"
	tar -xzf "$4" --strip-components=1 -C "$NVM_DIR/versions/node/$2"
}
NVM
printf '%s\n' '# fixture completion' >"$TEST_NATIVE_SOURCE_CHECKOUT/bash_completion"
printf '%s\n' '#!/bin/sh' 'exec "$@"' >"$TEST_NATIVE_SOURCE_CHECKOUT/nvm-exec"
chmod +x "$TEST_NATIVE_SOURCE_CHECKOUT/nvm-exec"
ln -s "$TEST_NATIVE_SOURCE_CHECKOUT" "$(dotfiles_catalog_root nvm)/current"
dotfiles_catalog_source_install() { [[ "$1" == nvm ]] && printf '%s\n' "$TEST_NATIVE_SOURCE_CHECKOUT"; }
dotfiles_catalog_source_owned() { [[ "$1" == nvm ]]; }
curl() {
	printf 'download\n' >>"$TEST_HARNESS_ROOT/downloads"
	local output='' url="${*: -1}"
	while (($#)); do
		if [[ "$1" == -o ]]; then
			output="$2"
			break
		fi
		shift
	done
	case "$url" in
	https://fixture.invalid/node.tgz) cp "${TEST_NATIVE_NODE_ARCHIVE:-$TEST_HARNESS_ROOT/node.tgz}" "$output" ;;
	https://fixture.invalid/npm.tgz) cp "$TEST_HARNESS_ROOT/npm.tgz" "$output" ;;
	*) return 97 ;;
	esac
}
install_node_via_nvm
prefix="$NVM_DIR/versions/node/$NODE_VERSION"
[[ "$(node --version)" == "$NODE_VERSION" && "$(npm --version)" == "$NPM_VERSION" && "$(npx --version)" == "$NPM_VERSION" ]]
[[ "$(node -p process.execPath)" == "$prefix/bin/node" ]]
[[ "$(npm config get prefix)" == "$prefix" ]]
[[ "$(cat "$NVM_DIR/alias/default")" == "$NODE_VERSION" ]]
for sidecar in bash_completion nvm-exec; do
	[[ -L "$NVM_DIR/$sidecar" && "$(readlink "$NVM_DIR/$sidecar")" == "$(dotfiles_catalog_root nvm)/current/$sidecar" ]] || {
		echo "FAIL: selected NVM companion is missing: $sidecar" >&2
		exit 1
	}
done
dotfiles_catalog_owned nodejs
dotfiles_catalog_owned npm
rm "$NVM_DIR/bash_completion"
printf 'keep external completion\n' >"$NVM_DIR/bash_completion"
rc=0
DOTFILES_FORCE_REINSTALL=1 install_node_via_nvm || rc=$?
[[ "$rc" == 2 && "$(cat "$NVM_DIR/bash_completion")" == 'keep external completion' ]]
rm "$NVM_DIR/bash_completion"
ln -s "$(dotfiles_catalog_root nvm)/current/bash_completion" "$NVM_DIR/bash_completion"
before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
install_node_via_nvm
[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
rm "$HOME/.local/bin/npx"
install_node_via_nvm
[[ -x "$HOME/.local/bin/npx" ]] || {
	echo 'FAIL: native runtime did not repair missing owned npx alias' >&2
	exit 1
}
mkdir -p "$prefix/lib/node_modules/user-package"
printf 'keep user package\n' >"$prefix/lib/node_modules/user-package/marker"
printf 'keep user command\n' >"$prefix/bin/user-command"
DOTFILES_FORCE_REINSTALL=1 install_node_via_nvm
[[ "$(cat "$prefix/lib/node_modules/user-package/marker")" == 'keep user package' ]]
[[ "$(cat "$prefix/bin/user-command")" == 'keep user command' ]]
export TEST_NATIVE_NVM_FAIL=1
rc=0
DOTFILES_FORCE_REINSTALL=1 install_node_via_nvm || rc=$?
[[ "$rc" == 27 && "$(node --version)" == "$NODE_VERSION" && "$(npm --version)" == "$NPM_VERSION" ]]
[[ "$(cat "$prefix/lib/node_modules/user-package/marker")" == 'keep user package' ]]
unset TEST_NATIVE_NVM_FAIL
mv() {
	if [[ "${*: -1}" == "$HOME/.local/bin/npm" && "${*: -2:1}" == */public-npm ]]; then return 29; fi
	command mv "$@"
}
rc=0
DOTFILES_FORCE_REINSTALL=1 install_node_via_nvm || rc=$?
unset -f mv
[[ "$rc" == 29 && "$(node --version)" == "$NODE_VERSION" && "$(npm --version)" == "$NPM_VERSION" ]]
[[ "$(cat "$prefix/lib/node_modules/user-package/marker")" == 'keep user package' ]]
dotfiles_catalog_native_owned nodejs
dotfiles_catalog_native_owned npm
rm "$NVM_DIR/bash_completion"
mv() {
	if [[ "${*: -1}" == "$HOME/.nvm/nvm-exec" && "${*: -2:1}" == */nvm-exec ]]; then return 33; fi
	command mv "$@"
}
rc=0
DOTFILES_FORCE_REINSTALL=1 install_node_via_nvm || rc=$?
unset -f mv
[[ "$rc" == 33 && ! -e "$NVM_DIR/bash_completion" && ! -L "$NVM_DIR/bash_completion" ]]
[[ "$(node --version)" == "$NODE_VERSION" && "$(npm --version)" == "$NPM_VERSION" ]]
[[ "$(readlink "$NVM_DIR/nvm-exec")" == "$(dotfiles_catalog_root nvm)/current/nvm-exec" ]]
ln -s "$(dotfiles_catalog_root nvm)/current/bash_completion" "$NVM_DIR/bash_completion"
# A different prior version exercises the real prefix transition; the old Node
# process is a fixture wrapper, while the destination SDK and npm are real.
(
	export HOME="$TEST_HARNESS_ROOT/upgrade-home" NVM_DIR="$TEST_HARNESS_ROOT/upgrade-home/.nvm"
	export PATH="$HOME/.local/bin:$tools"
	mkdir -p "$HOME" "$TEST_HARNESS_ROOT/old-sdk/node-v0.0.1-linux-x64/bin" "$(dotfiles_catalog_root nvm)"
	ln -s "$TEST_NATIVE_SOURCE_CHECKOUT" "$(dotfiles_catalog_root nvm)/current"
	old_node="$TEST_HARNESS_ROOT/old-sdk/node-v0.0.1-linux-x64/bin/node"
	{
		printf '%s\n' '#!/usr/bin/env bash' 'if [[ "${1:-}" == --version ]]; then echo v0.0.1; exit 0; fi'
		printf 'exec %q "$@"\n' "$REAL_NODE"
	} >"$old_node"
	chmod +x "$old_node"
	tar -czf "$TEST_HARNESS_ROOT/old-node.tgz" -C "$TEST_HARNESS_ROOT/old-sdk" node-v0.0.1-linux-x64
	python3 - "$TEST_HARNESS_ROOT/catalog/rows" "$TEST_HARNESS_ROOT/old-node.tgz" <<'ROWS' | catalog_fixture_seal "$TEST_HARNESS_ROOT/old-catalog"
import hashlib,pathlib,sys
updates={'version':'0.0.1','binary':'node-v0.0.1-linux-x64/bin/node',
         'digest':'sha256:'+hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    fields=line.split('\t')
    if fields[0]=='nodejs' and fields[1] in updates: fields[3]=updates[fields[1]]
    print('\t'.join(fields))
ROWS
	catalog_fixture_use "$TEST_HARNESS_ROOT/old-catalog"
	export TEST_NATIVE_NODE_ARCHIVE="$TEST_HARNESS_ROOT/old-node.tgz"
	install_node_via_nvm
	old_prefix="$NVM_DIR/versions/node/v0.0.1"
	mkdir -p "$old_prefix/lib/node_modules/user-global" "$old_prefix/etc"
	printf '%s\n' '{"name":"user-global","version":"1.0.0"}' >"$old_prefix/lib/node_modules/user-global/package.json"
	printf '%s\n' '#!/usr/bin/env node' 'console.log("retained global")' >"$old_prefix/lib/node_modules/user-global/cli.js"
	chmod +x "$old_prefix/lib/node_modules/user-global/cli.js"
	ln -s ../lib/node_modules/user-global/cli.js "$old_prefix/bin/user-global"
	printf 'fund=false\n' >"$old_prefix/etc/npmrc"
	[[ "$(node --version)" == v0.0.1 ]]
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog"
	unset TEST_NATIVE_NODE_ARCHIVE
	mv() {
		if [[ "${*: -1}" == "$HOME/.local/bin/npm" && "${*: -2:1}" == */public-npm ]]; then return 29; fi
		command mv "$@"
	}
	rc=0
	install_node_via_nvm || rc=$?
	unset -f mv
	[[ "$rc" == 29 && "$(node --version)" == v0.0.1 ]]
	[[ ! -e "$NVM_DIR/versions/node/$NODE_VERSION" && -f "$old_prefix/lib/node_modules/user-global/package.json" ]]
	dotfiles_catalog_native_owned nodejs
	dotfiles_catalog_native_owned npm
	install_node_via_nvm
	new_prefix="$NVM_DIR/versions/node/$NODE_VERSION"
	[[ "$(node --version)" == "$NODE_VERSION" && "$(npm root -g)" == "$new_prefix/lib/node_modules" ]]
	[[ -f "$new_prefix/lib/node_modules/user-global/package.json" && -x "$new_prefix/bin/user-global" ]] || {
		echo 'FAIL: a Node version upgrade stranded an owned global package or command' >&2
		exit 1
	}
	[[ "$(PATH="$new_prefix/bin:$PATH" "$new_prefix/bin/user-global")" == 'retained global' ]]
	[[ "$(npm config get fund)" == false ]]
	[[ -f "$old_prefix/lib/node_modules/user-global/package.json" ]]
)
rm "$HOME/.local/bin/npx"
printf '%s\n' '#!/usr/bin/env bash' 'echo external-npx' >"$HOME/.local/bin/npx"
chmod +x "$HOME/.local/bin/npx"
before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
rc=0
DOTFILES_FORCE_REINSTALL=1 install_node_via_nvm || rc=$?
[[ "$rc" != 0 && "$("$HOME/.local/bin/npx")" == external-npx ]] || {
	echo 'FAIL: native force replaced an external npx alias' >&2
	exit 1
}
[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
printf 'PASS: native NVM prefix exposes approved Node/npm/npx, preserves globals and survives failed import\n'
