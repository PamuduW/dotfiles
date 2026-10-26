#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$REPO_DIR/scripts/lib/software_catalog.sh"
source "$REPO_DIR/scripts/lib/catalog_runtimes.sh"
# Stop at catalog resolution: contention must be refused before any staging,
# version execution, downloads, or publication can begin.
dotfiles_catalog_begin() {
	printf 'begin\n' >>"$TEST_COMMAND_LOG"
	return 91
}
for key in nvm nodejs go; do
	root="$(dotfiles_catalog_root "$key")"
	mkdir -p "$root"
	exec {held_lock}>"$root/install.lock"
	flock -n "$held_lock"
	rc=0
	case "$key" in
	nvm) dotfiles_catalog_source_install nvm >/dev/null 2>&1 || rc=$? ;;
	nodejs) dotfiles_catalog_node_install >/dev/null 2>&1 || rc=$? ;;
	go) dotfiles_catalog_go_install >/dev/null 2>&1 || rc=$? ;;
	esac
	[[ "$rc" == 75 && ! -s "$TEST_COMMAND_LOG" ]] || {
		printf 'FAIL: concurrent %s install entered catalog/staging (exit %s)\n' "$key" "$rc" >&2
		exit 1
	}
	exec {held_lock}>&-
done
rc=0
dotfiles_catalog_node_install >/dev/null 2>&1 || rc=$?
[[ "$rc" == 91 && "$(cat "$TEST_COMMAND_LOG")" == begin ]]
root="$(dotfiles_catalog_root go)"
rm "$root/install.lock"
ln -s "$TEST_HARNESS_ROOT/foreign" "$root/install.lock"
: >"$TEST_COMMAND_LOG"
rc=0
dotfiles_catalog_go_install >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 && ! -s "$TEST_COMMAND_LOG" && ! -e "$TEST_HARNESS_ROOT/foreign" ]]
printf 'PASS: concurrent native/source installation is refused before work; locks release and reject symlinks\n'

# Generic, fonts and vendor package publication need the same exclusion.
dotfiles_catalog_begin() { SOFTWARE_CATALOG_REVISION="$(printf '%040d' 0)"; }
dotfiles_catalog_get() {
	case "$2" in
	owner) echo dotfiles ;;
	kind) echo software ;;
	*)
		printf 'version-or-artifact-work\n' >>"$TEST_COMMAND_LOG"
		return 93
		;;
	esac
}
for key in lazygit ubuntu_sans_mono_fonts apt-vendor; do
	: >"$TEST_COMMAND_LOG"
	root="$(dotfiles_catalog_root "$key")"
	mkdir -p "$root"
	exec {held_lock}>"$root/install.lock"
	flock -n "$held_lock"
	rc=0
	case "$key" in
	lazygit) dotfiles_catalog_install lazygit >/dev/null 2>&1 || rc=$? ;;
	ubuntu_sans_mono_fonts) dotfiles_catalog_fonts >/dev/null 2>&1 || rc=$? ;;
	apt-vendor) dotfiles_catalog_install_debs powershell >/dev/null 2>&1 || rc=$? ;;
	esac
	[[ "$rc" == 75 && ! -s "$TEST_COMMAND_LOG" ]] || {
		printf 'FAIL: concurrent %s publication entered work (exit %s)\n' "$key" "$rc" >&2
		exit 1
	}
	exec {held_lock}>&-
done
printf 'PASS: generic, fonts and vendor package transactions refuse competing publication\n'
