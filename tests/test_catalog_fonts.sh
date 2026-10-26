#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/installers/fonts.sh"
source "$ROOT/scripts/lib/updates/integrations.sh"
fixture="$TEST_HARNESS_ROOT/catalog"
python3 - "$TEST_HARNESS_ROOT/fonts.zip" <<'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1],'w') as z:z.writestr('fonts/Mono.ttf','fixture font')
PY
digest="$(sha256sum "$TEST_HARNESS_ROOT/fonts.zip")"
printf '%s\n' $'ubuntu_sans_mono_fonts\towner\tany\tdotfiles' $'ubuntu_sans_mono_fonts\tkind\tany\tsoftware' \
	$'ubuntu_sans_mono_fonts\tversion\tany\t1.2.3' $'ubuntu_sans_mono_fonts\tarchive\tany\tzip' \
	$'ubuntu_sans_mono_fonts\turl\tany\thttps://fixture.invalid/fonts.zip' \
	$'ubuntu_sans_mono_fonts\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$fixture"
catalog_fixture_use "$fixture"
curl() {
	printf 'download\n' >>"$TEST_HARNESS_ROOT/downloads"
	while (($#)); do
		if [[ "$1" == -o ]]; then
			cp "$TEST_HARNESS_ROOT/fonts.zip" "$2"
			return
		fi
		shift
	done
	return 1
}
install_ubuntu_sans_mono_windows() { :; }
fc-cache() { :; }
install_ubuntu_sans_mono_fonts
[[ "$(cat "$HOME/.local/share/fonts/ubuntu-sans-mono/Mono.ttf")" == 'fixture font' ]]
row="$(check_ubuntu_sans_mono || true)"
[[ "$row" == 'Ubuntu Sans Mono fonts|1.2.3|1.2.3|current' ]] || {
	echo 'FAIL: font status treated a managed font bundle as a missing binary' >&2
	exit 1
}
printf '1.0.0\n' >"$HOME/.local/share/fonts/ubuntu-sans-mono/.version"
upgrade_result_set() { printf '%s\n' "$1" >"$TEST_HARNESS_ROOT/result"; }
upgrade_ubuntu_sans_mono
[[ "$(cat "$HOME/.local/share/fonts/ubuntu-sans-mono/.version")" == 1.2.3 ]]
[[ "$(cat "$TEST_HARNESS_ROOT/result")" == updated ]]
upgrade_ubuntu_sans_mono
[[ "$(cat "$TEST_HARNESS_ROOT/result")" == already-current ]]
printf '9.9.9\n' >"$HOME/.local/share/fonts/ubuntu-sans-mono/.version"
before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
if DOTFILES_FORCE_REINSTALL=1 install_ubuntu_sans_mono_fonts; then
	echo 'FAIL: newer owned fonts were downgraded' >&2
	exit 1
fi
[[ "$(cat "$HOME/.local/share/fonts/ubuntu-sans-mono/.version")" == 9.9.9 ]]
[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
printf '1.2.3\n' >"$HOME/.local/share/fonts/ubuntu-sans-mono/.version"
cp -- "$TEST_HARNESS_ROOT/fonts.zip" "$TEST_HARNESS_ROOT/fonts.original.zip"
printf 'broken bytes\n' >>"$TEST_HARNESS_ROOT/fonts.zip"
if DOTFILES_FORCE_REINSTALL=1 install_ubuntu_sans_mono_fonts; then
	echo 'FAIL: unapproved font bytes accepted' >&2
	exit 1
fi
[[ "$(cat "$HOME/.local/share/fonts/ubuntu-sans-mono/Mono.ttf")" == 'fixture font' ]]
cp -- "$TEST_HARNESS_ROOT/fonts.original.zip" "$TEST_HARNESS_ROOT/fonts.zip"
# A receipt-shaped file alone cannot authorize replacement or a Windows retry.
printf 'invalid ownership\n' >"$HOME/.local/share/fonts/ubuntu-sans-mono/.catalog-receipt"
printf '1.0.0\n' >"$HOME/.local/share/fonts/ubuntu-sans-mono/.version"
before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
install_ubuntu_sans_mono_windows() { : >"$TEST_HARNESS_ROOT/windows-called"; }
if DOTFILES_FORCE_REINSTALL=1 install_ubuntu_sans_mono_fonts; then
	echo 'FAIL: malformed font receipt authorized installation' >&2
	exit 1
fi
[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
[[ ! -e "$TEST_HARNESS_ROOT/windows-called" ]]
[[ "$(cat "$HOME/.local/share/fonts/ubuntu-sans-mono/.catalog-receipt")" == 'invalid ownership' ]]
printf 'PASS: fonts use pinned archive bytes and preserve working files\n'
