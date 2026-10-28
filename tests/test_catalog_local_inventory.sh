#!/usr/bin/env bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$test_dir/.." && pwd)"
source "$test_dir/lib/harness.sh"
test_harness_init
source "$root/scripts/lib/catalog_legacy.sh"
declare -F dotfiles_catalog_local_inventory >/dev/null || {
	echo 'FAIL: bounded unreceipted local command inventory is missing' >&2
	exit 1
}

inventory_case() (
	local mode="$1" value='' status=0 extra=''
	export HOME="$TEST_HARNESS_ROOT/$mode/home"
	mkdir -p "$HOME/.local/bin" "$HOME/bin" "$HOME/tools"
	printf '%s\n' '#!/bin/sh' 'touch "$HOME/old-code-executed"' >"$HOME/.local/bin/uv"
	chmod +x "$HOME/.local/bin/uv"
	export PATH="$HOME/.local/bin:$HOME/bin:/usr/bin:/bin"
	case "$mode" in
	valid) ;;
	home-bin)
		mv "$HOME/.local/bin/uv" "$HOME/bin/uv"
		;;
	chained-alias)
		mv "$HOME/.local/bin/uv" "$HOME/tools/uv"
		ln -s "$HOME/tools/uv" "$HOME/bin/uv"
		ln -s "$HOME/bin/uv" "$HOME/.local/bin/uv"
		;;
	foreign-active)
		mkdir -p "$TEST_HARNESS_ROOT/$mode/foreign"
		cp "$HOME/.local/bin/uv" "$TEST_HARNESS_ROOT/$mode/foreign/uv"
		PATH="$TEST_HARNESS_ROOT/$mode/foreign:$PATH"
		;;
	escaped-target)
		mv "$HOME/.local/bin/uv" "$TEST_HARNESS_ROOT/$mode/foreign-uv"
		ln -s "$TEST_HARNESS_ROOT/$mode/foreign-uv" "$HOME/.local/bin/uv"
		;;
	conflicting-alias)
		cp "$HOME/.local/bin/uv" "$HOME/bin/uv"
		;;
	symlink-parent)
		mv "$HOME/.local/bin" "$HOME/tools/bin"
		ln -s "$HOME/tools/bin" "$HOME/.local/bin"
		;;
	broken-catalog)
		mkdir -p "$HOME/.local/share/dotfiles-catalog/uv"
		ln -s nowhere "$HOME/.local/share/dotfiles-catalog/uv/current"
		;;
	python-shim)
		printf '%s\n' '#!/bin/sh' 'touch "$HOME/old-code-executed"' 'exec /usr/bin/python3 "$@"' >"$HOME/.local/bin/python3"
		chmod +x "$HOME/.local/bin/python3"
		;;
	oversized) truncate -s 536870913 "$HOME/.local/bin/uv" ;;
	setgid) chmod g+s "$HOME/.local/bin/uv" ;;
	hardlink) ln "$HOME/.local/bin/uv" "$HOME/tools/uv-linked" ;;
	nvm-global)
		extra="$HOME/.nvm/versions/node/v24.22.1/bin/uv"
		mkdir -p "${extra%/*}"
		mv "$HOME/.local/bin/uv" "$extra"
		PATH="${extra%/*}:$PATH"
		;;
	esac
	value="$(dotfiles_catalog_local_inventory uv uv "$extra" 2>/dev/null)" || status=$?
	case "$mode" in
	valid | home-bin | chained-alias | python-shim | nvm-global)
		[[ "$status" == 0 && "${value%%$'\t'*}" =~ ^[0-9a-f]{64}$ ]]
		;;
	*) [[ "$status" != 0 ]] ;;
	esac
	[[ ! -e "$HOME/old-code-executed" ]]
)
for mode in valid home-bin chained-alias foreign-active escaped-target conflicting-alias symlink-parent broken-catalog python-shim oversized setgid hardlink nvm-global; do
	inventory_case "$mode"
	printf 'ok - bounded unreceipted local command: %s\n' "$mode"
done

# Version authority must not be delegated to a manager shim on PATH.
source "$root/scripts/lib/installers/load.sh"
mkdir -p "$HOME/.local/bin" "$HOME/bin"
printf '%s\n' '#!/bin/sh' 'echo "uv 9.0.0"' >"$HOME/.local/bin/uv"
printf '%s\n' '#!/bin/sh' 'touch "$HOME/python-order-executed"' 'exit 0' >"$HOME/bin/python3"
chmod +x "$HOME/.local/bin/uv" "$HOME/bin/python3"
PATH="$HOME/bin:/usr/bin:/bin"
if dotfiles_catalog_local_version_allowed "$HOME/.local/bin/uv" 1.2.3 --version; then
	echo 'FAIL: PATH Python shim authorized downgrading an unreceipted command' >&2
	exit 1
fi
[[ ! -e "$HOME/python-order-executed" ]]
printf 'ok - local version order uses trusted Python\n'
