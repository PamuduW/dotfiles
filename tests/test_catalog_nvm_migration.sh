#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
if [[ -f "$REPO_DIR/scripts/lib/catalog_legacy.sh" ]]; then source "$REPO_DIR/scripts/lib/catalog_legacy.sh"; fi
declare -F dotfiles_catalog_nvm_inventory >/dev/null || {
	echo 'FAIL: bounded legacy NVM inventory is missing' >&2
	exit 1
}

inventory_case() (
	local mode="$1" result='' rc=0 command_name prefix
	export HOME="$TEST_HARNESS_ROOT/$mode/home" NVM_DIR="$TEST_HARNESS_ROOT/$mode/home/.nvm"
	prefix="$NVM_DIR/versions/node/v24.1.0"
	mkdir -p "$prefix/bin" "$prefix/lib/node_modules/npm/bin" "$NVM_DIR/alias" "$HOME/.local/bin"
	for command_name in nvm.sh bash_completion nvm-exec; do
		printf 'touch "$HOME/legacy-code-executed"\n' >"$NVM_DIR/$command_name"
	done
	for command_name in node npm npx; do
		printf '%s\n' '#!/bin/sh' 'touch "$HOME/legacy-code-executed"' >"$prefix/bin/$command_name"
		chmod +x "$prefix/bin/$command_name"
	done
	mv "$prefix/bin/npm" "$prefix/lib/node_modules/npm/bin/npm-cli.js"
	mv "$prefix/bin/npx" "$prefix/lib/node_modules/npm/bin/npx-cli.js"
	ln -s ../lib/node_modules/npm/bin/npm-cli.js "$prefix/bin/npm"
	ln -s ../lib/node_modules/npm/bin/npx-cli.js "$prefix/bin/npx"
	PATH="$prefix/bin:/usr/bin:/bin"
	export PATH
	case "$mode" in
	valid) ;;
	python-shim)
		printf '%s\n' '#!/bin/sh' 'touch "$HOME/legacy-code-executed"' 'exec /usr/bin/python3 "$@"' >"$prefix/bin/python3"
		chmod +x "$prefix/bin/python3"
		;;
	foreign-npx)
		mkdir "$HOME/foreign"
		cp "$prefix/bin/node" "$HOME/foreign/npx"
		PATH="$HOME/foreign:$PATH"
		;;
	foreign-node-alias)
		mkdir "$HOME/foreign"
		ln -s "$prefix/bin/node" "$HOME/foreign/node"
		PATH="$HOME/foreign:$PATH"
		;;
	escaped-npm)
		cp "$prefix/bin/node" "$HOME/foreign-npm"
		rm "$prefix/bin/npm"
		ln -s "$HOME/foreign-npm" "$prefix/bin/npm"
		;;
	manager-symlink)
		mv "$NVM_DIR/nvm.sh" "$HOME/foreign-nvm.sh"
		ln -s "$HOME/foreign-nvm.sh" "$NVM_DIR/nvm.sh"
		;;
	conflicting-receipt)
		mkdir -p "$HOME/.local/share/dotfiles-catalog"
		printf corrupt >"$HOME/.local/share/dotfiles-catalog/nodejs.native"
		;;
	inactive-target) mkdir "$NVM_DIR/versions/node/v24.2.0" ;;
	foreign-alias) cp "$prefix/bin/node" "$HOME/.local/bin/node" ;;
	esac
	result="$(dotfiles_catalog_nvm_inventory 24.2.0 2>/dev/null)" || rc=$?
	if [[ "$mode" == valid || "$mode" == python-shim ]]; then
		[[ "$rc" == 0 && "$result" == "$prefix"$'\t'* && "${result##*$'\t'}" =~ ^[0-9a-f]{64}$ ]]
		printf changed >>"$NVM_DIR/bash_completion"
		[[ "$(dotfiles_catalog_nvm_inventory 24.2.0)" != "$result" ]]
	else
		[[ "$rc" != 0 ]]
	fi
	[[ ! -e "$HOME/legacy-code-executed" ]]
)
for mode in valid python-shim foreign-npx foreign-node-alias escaped-npm manager-symlink conflicting-receipt inactive-target foreign-alias; do
	inventory_case "$mode"
	printf 'ok - legacy NVM inventory: %s\n' "$mode"
done
