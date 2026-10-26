#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/installers/load.sh"
source "$ROOT/scripts/lib/update_workflow.sh"
fixture="$TEST_HARNESS_ROOT/catalog"
mkdir -p "$TEST_HARNESS_ROOT/deb/DEBIAN"
cat >"$TEST_HARNESS_ROOT/deb/DEBIAN/control" <<'CONTROL'
Package: powershell
Version: 1.2.3
Architecture: amd64
Maintainer: Test <test@example.invalid>
Description: catalog fixture
CONTROL
dpkg-deb --build "$TEST_HARNESS_ROOT/deb" "$TEST_HARNESS_ROOT/powershell.deb" >/dev/null
digest="$(sha256sum "$TEST_HARNESS_ROOT/powershell.deb")"
printf '%s\n' $'powershell\towner\tany\tdotfiles' $'powershell\tkind\tany\tvendor-apt' \
	$'powershell\tversion\tany\t1.2.3' $'powershell\tarchive\tany\tdeb' \
	$'powershell\tpackage\tany\tpowershell' $'powershell\tbinary\tany\tpwsh' \
	$'powershell\turl\tany\thttps://fixture.invalid/powershell.deb' \
	$'powershell\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$fixture"
command() {
	if [[ "${1:-} ${2:-}" == "-v pwsh" ]]; then return 1; fi
	builtin command "$@"
}
catalog_fixture_use "$fixture"
curl() {
	while (($#)); do
		if [[ "$1" == -o ]]; then
			cp "$TEST_HARNESS_ROOT/powershell.deb" "$2"
			return
		fi
		shift
	done
	return 1
}
dpkg-query() {
	[[ -f "$TEST_HARNESS_ROOT/installed" ]] || return 1
	cat "$TEST_HARNESS_ROOT/installed"
}
sudo() {
	printf '%s\n' "$*" >>"$TEST_COMMAND_LOG"
	case "$1" in
	apt-get)
		if [[ " $* " == *' install '* ]]; then
			printf '1.2.3\n' >"$TEST_HARNESS_ROOT/installed"
		fi
		;;
	apt-mark) [[ "$2 $3" == 'hold powershell' ]] || return 72 ;;
	*) return 73 ;;
	esac
}
install_powershell
[[ "$(cat "$TEST_HARNESS_ROOT/installed")" == 1.2.3 ]]
rg -q '^apt-mark hold powershell$' "$TEST_COMMAND_LOG"
row="$(dotfiles_catalog_check powershell PowerShell || true)"
[[ "$row" == 'PowerShell|1.2.3|1.2.3|current' ]] || {
	echo "FAIL: owned apt package was misreported: $row" >&2
	exit 1
}
TEST_APPROVED_CATALOG="$TEST_HARNESS_ROOT/missing-catalog"
row="$(dotfiles_catalog_check powershell PowerShell 2>/dev/null || true)"
[[ "$row" == 'PowerShell|1.2.3|—|blocked' ]] || {
	echo 'FAIL: unavailable catalog erased the observed apt package version' >&2
	exit 1
}
catalog_fixture_use "$fixture"
: >"$TEST_COMMAND_LOG"
install_powershell
[[ ! -s "$TEST_COMMAND_LOG" ]] || {
	echo 'FAIL: repeated install reinstalled the current apt package' >&2
	exit 1
}
upgrade_result_set() { printf '%s\n' "$1" >"$TEST_HARNESS_ROOT/result"; }
dotfiles_catalog_upgrade powershell >"$TEST_HARNESS_ROOT/current-output"
[[ "$(cat "$TEST_HARNESS_ROOT/result")" == already-current ]]
grep -Fq 1.2.3 "$TEST_HARNESS_ROOT/current-output" || {
	echo 'FAIL: current vendor package update is silent' >&2
	exit 1
}
printf '1.0.0\n' >"$TEST_HARNESS_ROOT/installed"
dotfiles_catalog_upgrade powershell
[[ "$(cat "$TEST_HARNESS_ROOT/result")" == updated ]]
receipt="$HOME/.local/share/dotfiles-catalog/powershell.apt"
cp "$receipt" "$TEST_HARNESS_ROOT/receipt.before"
printf 'powershell\n' >"$receipt"
: >"$TEST_COMMAND_LOG"
if install_powershell; then
	echo 'FAIL: malformed apt receipt was accepted as ownership proof' >&2
	exit 1
fi
row="$(dotfiles_catalog_check powershell PowerShell || true)"
[[ "$row" == 'PowerShell|1.2.3|1.2.3|blocked' ]]
if dotfiles_catalog_apt_holds; then
	echo 'FAIL: malformed apt receipt selected a package hold' >&2
	exit 1
fi
[[ ! -s "$TEST_COMMAND_LOG" ]]
cp "$TEST_HARNESS_ROOT/receipt.before" "$receipt"
if dotfiles_catalog_install_debs; then
	echo 'FAIL: empty vendor package batch reported success' >&2
	exit 1
fi
[[ ! -s "$TEST_COMMAND_LOG" ]]
# Ordinary distro maintenance must reapply the hold before upgrading OS packages.
_run_quiet_command() {
	shift
	"$@"
}
apt_upgradable_count() { echo 1; }
apt_check_sudo_compatibility() { return 0; }
upgrade_result_set() { :; }
_update_apt_packages
python3 - "$TEST_COMMAND_LOG" <<'PY'
import sys
rows=open(sys.argv[1]).read().splitlines()
upgrades=[i for i,x in enumerate(rows) if x.startswith('apt-get ') and ' upgrade ' in x]
assert upgrades and any('apt-mark hold powershell'==x for x in rows[:upgrades[-1]])
assert 'powershell=99' not in '\n'.join(rows)
PY
# A newer owned package is preserved before downloads or apt mutations.
printf '2.0.0\n' >"$TEST_HARNESS_ROOT/installed"
: >"$TEST_COMMAND_LOG"
if install_powershell; then
	echo 'FAIL: a newer managed apt package was downgraded' >&2
	exit 1
fi
[[ "$(cat "$TEST_HARNESS_ROOT/installed")" == 2.0.0 && ! -s "$TEST_COMMAND_LOG" ]]
printf '1.2.3\n' >"$TEST_HARNESS_ROOT/installed"
# An apt-installed package without our receipt remains externally owned.
rm "$HOME/.local/share/dotfiles-catalog/powershell.apt"
: >"$TEST_COMMAND_LOG"
DOTFILES_FORCE_REINSTALL=1 install_powershell
[[ ! -s "$TEST_COMMAND_LOG" ]]
printf 'PASS: exact vendor .deb, persistent hold, OS maintenance and external ownership\n'

# Docker cannot install only a subset and let apt choose the other vendors.
: >"$TEST_COMMAND_LOG"
rc=0
DOTFILES_FORCE_REINSTALL=1 install_docker || rc=$?
[[ "$rc" != 0 && ! -s "$TEST_COMMAND_LOG" ]] || {
	echo 'FAIL: Docker mutation preceded complete vendor pins' >&2
	exit 1
}
printf 'PASS: Docker resolves every vendor package before mutation\n'
