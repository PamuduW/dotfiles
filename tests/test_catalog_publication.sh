#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/software_catalog.sh"
fixture="$TEST_HARNESS_ROOT/catalog"
printf '%s\n' '#!/usr/bin/env bash' 'echo v1.2.3' >"$TEST_HARNESS_ROOT/binary"
digest="$(sha256sum "$TEST_HARNESS_ROOT/binary")"
printf '%s\n' $'kubeconform\towner\tany\tdotfiles' \
	$'kubeconform\tkind\tany\tsoftware' $'kubeconform\tversion\tany\t1.2.3' \
	$'kubeconform\tarchive\tany\traw' $'kubeconform\tbinary\tany\tkubeconform' \
	$'kubeconform\turl\tany\thttps://fixture.invalid/binary' \
	$'kubeconform\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$fixture"
catalog_fixture_use "$fixture"
uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; -r) echo fixture ;; esac }
curl() {
	while (($#)); do
		if [[ "$1" == -o ]]; then
			cp "$TEST_HARNESS_ROOT/binary" "$2"
			return
		fi
		shift
	done
	return 1
}
# Inject failure only at the public-command rename; extraction and version
# verification still run against real files. A dangling current must fail this.
mv() {
	if [[ "${FAIL_PUBLICATION:-0}" == 1 && "${*: -1}" == "$HOME/.local/bin/kubeconform" ]]; then return 73; fi
	command mv "$@"
}
FAIL_PUBLICATION=1
if dotfiles_catalog_install kubeconform; then exit 1; fi
[[ ! -e "$HOME/.local/share/dotfiles-catalog/kubeconform/current" && ! -L "$HOME/.local/share/dotfiles-catalog/kubeconform/current" ]] || {
	echo 'FAIL: failed first publication left a dangling current' >&2
	exit 1
}
FAIL_PUBLICATION=0
dotfiles_catalog_install kubeconform
previous="$(readlink "$HOME/.local/share/dotfiles-catalog/kubeconform/current")"
FAIL_PUBLICATION=1
if DOTFILES_FORCE_REINSTALL=1 dotfiles_catalog_install kubeconform; then exit 1; fi
[[ "$("$HOME/.local/bin/kubeconform" -v)" == v1.2.3 ]]
[[ "$(readlink "$HOME/.local/share/dotfiles-catalog/kubeconform/current")" == "$previous" ]]
printf 'PASS: failed command publication preserves the previous working release\n'
