#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/installers/release_cli.sh"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/dotfiles"
printf '%s\n' '#!/usr/bin/env bash' 'if [[ "$1" == --origin ]]; then echo legacy; else echo v1.2.3; fi' >"$HOME/.local/bin/kubeconform"
chmod +x "$HOME/.local/bin/kubeconform"
printf 'v1.2.3\n' >"$HOME/.local/share/dotfiles/kubeconform.version"
printf '%s\n' '#!/usr/bin/env bash' 'if [[ "$1" == --origin ]]; then echo approved; else echo v1.2.3; fi' >"$TEST_HARNESS_ROOT/binary"
digest="$(sha256sum "$TEST_HARNESS_ROOT/binary")"
printf '%s\n' $'kubeconform\towner\tany\tdotfiles' $'kubeconform\tkind\tany\tsoftware' \
	$'kubeconform\tversion\tany\t1.2.3' $'kubeconform\tarchive\tany\traw' \
	$'kubeconform\tbinary\tany\tkubeconform' $'kubeconform\turl\tany\thttps://fixture.invalid/binary' \
	$'kubeconform\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog"
catalog_fixture_use "$TEST_HARNESS_ROOT/catalog"
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
install_release_cli kubeconform
[[ "$("$HOME/.local/bin/kubeconform" --origin)" == approved ]] || {
	echo 'FAIL: matching legacy version bypassed approved bytes and catalog ownership' >&2
	exit 1
}
[[ -L "$HOME/.local/bin/kubeconform" && -f "$HOME/.local/share/dotfiles-catalog/kubeconform/current/.catalog-receipt" ]]
curl() {
	echo 'FAIL: repeated reconciled install downloaded again' >&2
	return 97
}
install_release_cli kubeconform
printf 'PASS: matching legacy versions reconcile once to approved bytes and provenance\n'
