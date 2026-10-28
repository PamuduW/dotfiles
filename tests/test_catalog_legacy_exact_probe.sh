#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
source "$root/scripts/lib/installers/load.sh"
source "$root/scripts/lib/catalog_legacy.sh"
printf '%s\n' '#!/bin/sh' 'echo "fixture 1.2.2"' >"$temporary/probe"
chmod +x "$temporary/probe"
if dotfiles_catalog_local_version_allowed "$temporary/probe" 1.2.3 --version '' '' exact; then
	echo 'FAIL: exact baseline probe accepted an incorrectly labelled version' >&2
	exit 1
fi
dotfiles_catalog_local_version_allowed "$temporary/probe" 1.2.2 --version '' '' exact
dotfiles_catalog_local_version_allowed "$temporary/probe" 1.2.3 --version
printf 'PASS: frozen baseline probes require exact versions; normal migration permits older versions\n'
