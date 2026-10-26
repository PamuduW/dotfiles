#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
export PATH ASDF_DATA_DIR="$HOME/.asdf"
source "$REPO_DIR/scripts/lib/software_catalog.sh"
source "$REPO_DIR/scripts/lib/catalog_runtimes.sh"
source "$REPO_DIR/scripts/lib/installers/cli_tools.sh"
if ! declare -F dotfiles_catalog_go_install >/dev/null; then
	echo 'FAIL: native exact Go/asdf adapter is missing' >&2
	exit 1
fi
export TEST_NATIVE_PLUGIN="$TEST_HARNESS_ROOT/plugin"
mkdir -p "$TEST_NATIVE_PLUGIN/bin" "$TEST_HARNESS_ROOT/sdk/go/bin"
cat >"$TEST_NATIVE_PLUGIN/bin/install" <<'PLUGIN'
#!/usr/bin/env bash
set -euo pipefail
[[ "$ASDF_GOLANG_DEFAULT_PACKAGES_FILE" == /dev/null && "$GOTOOLCHAIN" == local ]] || exit 81
[[ "${TEST_GO_IMPORT_FAIL:-0}" != 1 ]] || exit 28
mkdir -p "$ASDF_INSTALL_PATH"
tar -xzf "$ASDF_DOWNLOAD_PATH/archive.tar.gz" -C "$ASDF_INSTALL_PATH"
PLUGIN
chmod +x "$TEST_NATIVE_PLUGIN/bin/install"
/usr/bin/git -C "$TEST_NATIVE_PLUGIN" init -q
/usr/bin/git -C "$TEST_NATIVE_PLUGIN" add bin/install
/usr/bin/git -C "$TEST_NATIVE_PLUGIN" -c user.name=Fixture -c user.email=fixture@example.invalid -c core.hooksPath=/dev/null commit -qm plugin
/usr/bin/git -C "$TEST_NATIVE_PLUGIN" remote add origin https://github.com/asdf-community/asdf-golang.git
plugin_revision="$(/usr/bin/git -C "$TEST_NATIVE_PLUGIN" rev-parse HEAD)"
printf '\n/.catalog-receipt\n/.catalog-source-revision\n' >>"$TEST_NATIVE_PLUGIN/.git/info/exclude"
printf '%s\n' "$plugin_revision" >"$TEST_NATIVE_PLUGIN/.catalog-source-revision"
cat >"$TEST_HARNESS_ROOT/sdk/go/bin/go" <<'GO'
#!/usr/bin/env bash
set -euo pipefail
root="$(dirname "$(dirname "$(readlink -f "$0")")")"
if [[ -n "${GOTOOLCHAIN:-}" ]]; then [[ "$GOTOOLCHAIN" == local ]] || exit 82
else grep -Fxq GOTOOLCHAIN=local "$root/go.env" || exit 82; fi
case "$*" in version) echo 'go version go1.2.3 linux/amd64' ;; 'env GOROOT') echo "$root" ;; *) exit 96 ;; esac
GO
chmod +x "$TEST_HARNESS_ROOT/sdk/go/bin/go"
printf 'GOTOOLCHAIN=auto\nGOPROXY=https://proxy.golang.org,direct\n' >"$TEST_HARNESS_ROOT/sdk/go/go.env"
tar -czf "$TEST_HARNESS_ROOT/go.tgz" -C "$TEST_HARNESS_ROOT/sdk" go
cat >"$TEST_HARNESS_ROOT/asdf" <<'ASDF'
#!/usr/bin/env bash
set -euo pipefail
printf 'asdf:%s\n' "$*" >>"$TEST_COMMAND_LOG"
case "$1" in
--version) echo 'v0.20.0' ;;
set)
	[[ "$*" == 'set -u golang 1.2.3' ]] || exit 83
	[[ "${TEST_ASDF_SELECT_FAIL:-0}" != 1 ]] || exit 29
	python3 - "$HOME/.tool-versions" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); lines=p.read_text().splitlines() if p.exists() else []
lines=[x for x in lines if not x.startswith('golang ')]
p.write_text('\n'.join(lines+['golang 1.2.3'])+'\n')
PY
	;;
reshim)
	[[ "$*" == 'reshim golang 1.2.3' ]] || exit 84
	mkdir -p "$ASDF_DATA_DIR/shims"
	printf '%s\n' '#!/usr/bin/env bash' '# asdf-plugin: golang 1.2.3' 'exec "$HOME/.local/bin/asdf" exec go "$@"' >"$ASDF_DATA_DIR/shims/go"
	chmod +x "$ASDF_DATA_DIR/shims/go"
	[[ "${TEST_ASDF_RESHIM_FAIL:-0}" != 1 ]] || exit 30
	;;
which) printf '%s\n' "$ASDF_DATA_DIR/installs/golang/1.2.3/go/bin/go" ;;
exec) shift 2; exec "$ASDF_DATA_DIR/installs/golang/1.2.3/go/bin/go" "$@" ;;
*) exit 97 ;;
esac
ASDF
chmod +x "$TEST_HARNESS_ROOT/asdf"
go_digest="$(sha256sum "$TEST_HARNESS_ROOT/go.tgz")"
asdf_digest="$(sha256sum "$TEST_HARNESS_ROOT/asdf")"
printf '%s\n' $'go\towner\tany\tdotfiles' $'go\tkind\tany\tsoftware' $'go\tversion\tany\t1.2.3' \
	$'go\tarchive\tany\ttar.gz' $'go\tbinary\tany\tgo/bin/go' $'go\turl\tany\thttps://fixture.invalid/go.tgz' $'go\tdigest\tany\tsha256:'"${go_digest%% *}" \
	$'asdf\towner\tany\tdotfiles' $'asdf\tkind\tany\tsoftware' $'asdf\tversion\tany\t0.20.0' \
	$'asdf\tarchive\tany\traw' $'asdf\tbinary\tany\tasdf' $'asdf\turl\tany\thttps://fixture.invalid/asdf' $'asdf\tdigest\tany\tsha256:'"${asdf_digest%% *}" \
	$'asdf-golang\towner\tany\tdotfiles' $'asdf-golang\tkind\tany\tgit-source' $'asdf-golang\tsource\tany\tasdf-community/asdf-golang' \
	$'asdf-golang\trevision\tany\t'"$plugin_revision" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog"
catalog_fixture_use "$TEST_HARNESS_ROOT/catalog"
printf '1.0.0\n%s\n%s\n' "$SOFTWARE_CATALOG_DIGEST" "$SOFTWARE_CATALOG_REVISION" >"$TEST_NATIVE_PLUGIN/.catalog-receipt"
dotfiles_catalog_source_install() { [[ "$1" == asdf-golang ]] && printf '%s\n' "$TEST_NATIVE_PLUGIN"; }
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
	https://fixture.invalid/go.tgz) cp "$TEST_HARNESS_ROOT/go.tgz" "$output" ;;
	https://fixture.invalid/asdf) cp "$TEST_HARNESS_ROOT/asdf" "$output" ;;
	*) return 97 ;;
	esac
}
rm -f -- "$TEST_FAKE_BIN/git"
cat >"$TEST_FAKE_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
repo='' operation=''
for ((i=0; i<${#args[@]}; i++)); do
	case "${args[i]}" in
	-c) i=$((i+1)) ;;
	-C) repo="${args[i+1]}"; i=$((i+1)) ;;
	rev-parse | config | status) operation="${args[i]}"; break ;;
	*) exit 97 ;;
	esac
done
[[ "$repo" == "$TEST_HARNESS_ROOT/"* && -n "$operation" ]] || exit 97
exec /usr/bin/git "$@"
GIT
chmod +x "$TEST_FAKE_BIN/git"
printf 'ruby 3.3.0\n' >"$HOME/.tool-versions"
printf 'example.invalid/unapproved@latest\n' >"$HOME/.default-golang-pkgs"
install_go_via_asdf
prefix="$ASDF_DATA_DIR/installs/golang/1.2.3"
[[ "$("$HOME/.local/bin/go" version)" == 'go version go1.2.3 linux/amd64' ]]
[[ "$("$HOME/.local/bin/go" env GOROOT)" == "$prefix/go" ]]
grep -Fxq 'ruby 3.3.0' "$HOME/.tool-versions"
grep -Fxq 'golang 1.2.3' "$HOME/.tool-versions"
dotfiles_catalog_owned go
[[ "$(GOTOOLCHAIN=auto "$HOME/.local/bin/go" version)" == 'go version go1.2.3 linux/amd64' ]]
grep -Fxq GOTOOLCHAIN=local "$prefix/go/go.env"
grep -Fxq GOPROXY=https://proxy.golang.org,direct "$prefix/go/go.env"
[[ "$(GOTOOLCHAIN=auto "$ASDF_DATA_DIR/shims/go" version)" == 'go version go1.2.3 linux/amd64' ]] || {
	echo 'FAIL: asdf shim did not force the approved local Go toolchain' >&2
	exit 1
}
source "$REPO_DIR/scripts/lib/updates/runtimes.sh"
row="$(PATH="$ASDF_DATA_DIR/shims:$PATH" check_go || true)"
[[ "$row" == 'Go (asdf)|1.2.3|1.2.3|current' ]] || {
	echo "FAIL: owned Go shim misclassified: $row" >&2
	exit 1
}
before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
install_go_via_asdf
[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
mkdir -p "$prefix/packages"
printf keep >"$prefix/packages/user-marker"
DOTFILES_FORCE_REINSTALL=1 install_go_via_asdf
[[ "$(cat "$prefix/packages/user-marker")" == keep ]]
for failure in import select reshim; do
	unset TEST_GO_IMPORT_FAIL TEST_ASDF_SELECT_FAIL TEST_ASDF_RESHIM_FAIL
	case "$failure" in import)
		export TEST_GO_IMPORT_FAIL=1
		expected=28
		;;
	select)
		export TEST_ASDF_SELECT_FAIL=1
		expected=29
		;;
	reshim)
		export TEST_ASDF_RESHIM_FAIL=1
		expected=30
		;;
	esac
	rc=0
	DOTFILES_FORCE_REINSTALL=1 install_go_via_asdf || rc=$?
	[[ "$rc" == "$expected" && "$(cat "$prefix/packages/user-marker")" == keep ]]
	[[ "$("$HOME/.local/bin/go" version)" == 'go version go1.2.3 linux/amd64' ]]
	grep -Fxq 'ruby 3.3.0' "$HOME/.tool-versions"
	grep -Fxq 'golang 1.2.3' "$HOME/.tool-versions"
done
unset TEST_GO_IMPORT_FAIL TEST_ASDF_SELECT_FAIL TEST_ASDF_RESHIM_FAIL
: >"$TEST_HARNESS_ROOT/fail-plugin-publication"
mv() {
	if [[ "${*: -1}" == "$ASDF_DATA_DIR/plugins/golang" && -e "$TEST_HARNESS_ROOT/fail-plugin-publication" ]]; then
		rm "$TEST_HARNESS_ROOT/fail-plugin-publication"
		return 44
	fi
	command mv "$@"
}
rc=0
DOTFILES_FORCE_REINSTALL=1 install_go_via_asdf || rc=$?
[[ "$rc" == 44 && -x "$ASDF_DATA_DIR/plugins/golang/bin/install" ]] || {
	echo 'FAIL: failed publication lost the prior Go plugin' >&2
	exit 1
}
[[ "$("$HOME/.local/bin/go" version)" == 'go version go1.2.3 linux/amd64' ]]
printf 'PASS: native asdf Go uses pinned SDK/plugin, preserves config and rolls back failed import/selection/reshim\n'
