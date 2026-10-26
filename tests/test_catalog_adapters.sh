#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/installers/logging.sh"
source "$ROOT/scripts/lib/installers/load.sh"
source "$ROOT/scripts/lib/update_components.sh"

# A real approved-format fixture, not an environment switch around approval.
fixture="$TEST_HARNESS_ROOT/catalog"
mkdir -p "$fixture" "$TEST_HARNESS_ROOT/artifact"
printf '%s\n' '#!/usr/bin/env bash' 'echo "kubeconform v1.2.3"' >"$TEST_HARNESS_ROOT/artifact/kubeconform"
tar -czf "$TEST_HARNESS_ROOT/pin.tar.gz" -C "$TEST_HARNESS_ROOT/artifact" kubeconform
pin_digest="$(sha256sum "$TEST_HARNESS_ROOT/pin.tar.gz")"
pin_digest="sha256:${pin_digest%% *}"
python3 - "$fixture" "$pin_digest" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); digest=sys.argv[2]
rows=[('kubeconform','owner','any','dotfiles'),('kubeconform','kind','any','software'),('kubeconform','version','linux-amd64','1.2.3'),('kubeconform','url','linux-amd64','https://fixture.invalid/approved.tar.gz'),('kubeconform','digest','linux-amd64',digest),('kubeconform','archive','linux-amd64','tar'),('kubeconform','binary','linux-amd64','kubeconform')]
raw=json.dumps({'test':'qualified fixture'}).encode(); p.joinpath('software.json').write_bytes(raw)
h=hashlib.sha256(raw).hexdigest(); table='#software-catalog-v1\t'+h+'\n'+''.join('\t'.join(row)+'\n' for row in rows)
p.joinpath('software.tsv').write_text(table);p.joinpath('approval.json').write_text('{}')
p.joinpath('approval').write_text('software-approved-v1\n'+h+'\n'+hashlib.sha256(table.encode()).hexdigest()+'\n'+hashlib.sha256(b'{}').hexdigest()+'\n')
PY
# Upstream lies about newer releases. Normal routes must never query it.
release_cli_latest_release_metadata() {
	echo 'v99.0.0'
	echo 'unapproved'
}
curl() {
	printf 'download\n' >>"$TEST_HARNESS_ROOT/downloads"
	local output='' arg
	while (($#)); do
		arg="$1"
		shift
		case "$arg" in
		-o)
			output="$1"
			shift
			;;
		https://fixture.invalid/approved.tar.gz)
			cp "$TEST_HARNESS_ROOT/pin.tar.gz" "$output"
			return
			;;
		esac
	done
	return 70
}
uname() { case "${1:-}" in -m) echo x86_64 ;; -s) echo Linux ;; -r) echo fixture ;; *) command uname "$@" ;; esac }

# Removing the adapter or routing back through latest fails this exact install.
if ! declare -F dotfiles_catalog_begin >/dev/null; then
	echo 'FAIL: public installers do not load approved catalog adapters' >&2
	exit 1
fi
catalog_fixture_use "$fixture"
install_release_cli kubeconform
[[ "$("$HOME/.local/bin/kubeconform" --version)" == 'kubeconform v1.2.3' ]]
DOTFILES_FORCE_REINSTALL=1 install_release_cli kubeconform
check="$(check_kubeconform || true)"
[[ "$check" == *'|1.2.3|current' ]]
[[ "$check" == 'Kubeconform|1.2.3|1.2.3|current' ]] || {
	echo 'FAIL: public update probe lost its report component identity' >&2
	exit 1
}
upgrade_kubeconform
[[ "$("$HOME/.local/bin/kubeconform" --version)" == 'kubeconform v1.2.3' ]]
# A newer managed installation is drift, including during forced reinstall.
installed_binary="$(dotfiles_catalog_root kubeconform)/current/payload/kubeconform"
printf '%s\n' '#!/usr/bin/env bash' 'echo "kubeconform v9.9.9"' >"$installed_binary"
check="$(check_kubeconform || true)"
[[ "$check" == 'Kubeconform|9.9.9|1.2.3|blocked' ]] || {
	echo "FAIL: version drift was reported as an upgrade: $check" >&2
	exit 1
}
before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
if install_release_cli kubeconform || DOTFILES_FORCE_REINSTALL=1 install_release_cli kubeconform; then
	echo 'FAIL: a newer managed command was silently downgraded' >&2
	exit 1
fi
[[ "$("$HOME/.local/bin/kubeconform" --version)" == 'kubeconform v9.9.9' ]]
[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
cp "$TEST_HARNESS_ROOT/artifact/kubeconform" "$installed_binary"
# Changed bytes and wrong versions preserve the working command and config.
printf 'user configuration\n' >"$HOME/.kubeconform"
printf 'changed bytes\n' >>"$TEST_HARNESS_ROOT/pin.tar.gz"
if DOTFILES_FORCE_REINSTALL=1 install_release_cli kubeconform; then
	echo 'FAIL: changed artifact bytes were accepted' >&2
	exit 1
fi
[[ "$("$HOME/.local/bin/kubeconform" --version)" == 'kubeconform v1.2.3' ]]
[[ "$(cat "$HOME/.kubeconform")" == 'user configuration' ]]
# A foreign command is preserved even when forced.
rm "$HOME/.local/bin/kubeconform"
printf '%s\n' '#!/usr/bin/env bash' 'echo external' >"$HOME/.local/bin/kubeconform"
chmod +x "$HOME/.local/bin/kubeconform"
DOTFILES_FORCE_REINSTALL=1 install_release_cli kubeconform
[[ "$("$HOME/.local/bin/kubeconform")" == external ]]
printf 'PASS: approved adapters choose the pin and preserve working/external installs\n'

# All normal public tool routes must use the same loaded snapshot. These
# tools share raw archive semantics but have distinct public entrypoints.
rm -f "$TEST_HARNESS_ROOT/downloads"
for spec in 'install_boost_cli boost_cli' 'install_claude_cli claude_cli' 'install_antigravity_cli antigravity_cli' 'install_node_via_nvm nodejs' 'install_go_via_asdf go' 'install_direnv direnv'; do
	read -r public key <<<"$spec"
	# A missing approved row must fail without invoking a legacy installer.
	if "$public"; then
		echo "FAIL: $public bypassed missing catalog row $key" >&2
		exit 1
	fi
done
[[ ! -e "$TEST_HARNESS_ROOT/downloads" ]] || {
	echo 'FAIL: unavailable approved pins contacted upstream' >&2
	exit 1
}
printf 'PASS: public routes reject unavailable approved pins\n'

source "$ROOT/scripts/lib/components/install_dispatch.sh"
apt_check_sudo_compatibility() {
	echo touched >"$TEST_HARNESS_ROOT/mutation"
	return 17
}
TEST_APPROVED_CATALOG="$TEST_HARNESS_ROOT/unapproved"
rc=0
(run_install) || rc=$?
[[ "$rc" == 2 && ! -e "$TEST_HARNESS_ROOT/mutation" ]] || {
	echo 'FAIL: installation mutated before catalog approval' >&2
	exit 1
}
printf 'PASS: no approved snapshot blocks before component mutation\n'
