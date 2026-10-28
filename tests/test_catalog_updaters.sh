#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
export PATH ASDF_DATA_DIR="$HOME/.asdf"
# This fresh-install fixture must not discover the runner's preinstalled Go.
# Keep lookup real once this fixture has published its managed command/shim.
command() {
	if [[ "$*" == '-v go' && ! -x "$HOME/.local/bin/go" ]]; then return 1; fi
	builtin command "$@"
}
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
	for program in "$ASDF_DATA_DIR/installs/golang/1.2.3/go/bin/"* "$ASDF_DATA_DIR/installs/golang/1.2.3/bin/"*; do
		[[ -f "$program" && -x "$program" ]] || continue
		name="${program##*/}"
		printf '%s\n' '#!/usr/bin/env bash' '# asdf-plugin: golang 1.2.3' "exec \"\$HOME/.local/bin/asdf\" exec $name \"\$@\"" >"$ASDF_DATA_DIR/shims/$name"
		chmod +x "$ASDF_DATA_DIR/shims/$name"
	done
	[[ "${TEST_ASDF_RESHIM_FAIL:-0}" != 1 ]] || exit 30
	;;
which) printf '%s\n' "$ASDF_DATA_DIR/installs/golang/1.2.3/go/bin/go" ;;
exec)
	name="$2"; shift 2
	for directory in go/bin bin; do
		program="$ASDF_DATA_DIR/installs/golang/1.2.3/$directory/$name"
		if [[ -x "$program" ]]; then exec "$program" "$@"; fi
	done
	exit 98
	;;
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
	https://fixture.invalid/go.tgz)
		cp "$TEST_HARNESS_ROOT/go.tgz" "$output"
		if [[ "${TEST_GO_CHANGE_AFTER_DOWNLOAD:-0}" == 1 ]]; then printf 'python 3.12.0\n' >>"$HOME/.tool-versions"; fi
		;;
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

legacy_migration_case() (
	local mode="$1" old_install output='' status=0 downloads_before
	unset -f command mv
	unset TEST_GO_IMPORT_FAIL TEST_ASDF_SELECT_FAIL TEST_ASDF_RESHIM_FAIL TEST_GO_CHANGE_AFTER_DOWNLOAD DOTFILES_MIGRATE_ASDF_GO
	unset ASDF_DIR ASDF_GOLANG_VERSION ASDF_TOOL_VERSIONS_FILENAME
	export HOME="$TEST_HARNESS_ROOT/legacy-$mode/home" ASDF_DATA_DIR="$TEST_HARNESS_ROOT/legacy-$mode/home/.asdf"
	export DOTFILES_INTERACTIVE_TTY=false TEST_LEGACY_GO_VERSION=1.2.2 TEST_LEGACY_ASDF_VERSION=0.19.0
	if [[ "$mode" == same-version || "$mode" == same-version-reshim-failure ]]; then TEST_LEGACY_GO_VERSION=1.2.3; fi
	[[ "$mode" != newer-go ]] || TEST_LEGACY_GO_VERSION=999.0.0
	[[ "$mode" != newer-asdf ]] || TEST_LEGACY_ASDF_VERSION=999.0.0
	[[ "$mode" != unverifiable-asdf ]] || TEST_LEGACY_ASDF_VERSION=unknown
	old_install="$ASDF_DATA_DIR/installs/golang/$TEST_LEGACY_GO_VERSION"
	mkdir -p "$old_install/go/bin" "$old_install/bin" "$old_install/packages" "$ASDF_DATA_DIR/bin" \
		"$ASDF_DATA_DIR/plugins/ruby" "$ASDF_DATA_DIR/shims" "$ASDF_DATA_DIR/installs/golang/0.0.1"
	cp -a "$TEST_NATIVE_PLUGIN" "$ASDF_DATA_DIR/plugins/golang"
	rm "$ASDF_DATA_DIR/plugins/golang/.catalog-receipt" "$ASDF_DATA_DIR/plugins/golang/.catalog-source-revision"
	cat >"$old_install/go/bin/go" <<'LEGACY_GO'
#!/usr/bin/env bash
touch "$HOME/legacy-code-executed"
[[ "$GOTOOLCHAIN" == local ]] || exit 82
echo "go version go$TEST_LEGACY_GO_VERSION linux/amd64"
LEGACY_GO
	cat >"$ASDF_DATA_DIR/bin/asdf" <<'LEGACY_ASDF'
#!/usr/bin/env bash
touch "$HOME/legacy-code-executed"
case "$1" in
--version) echo "v$TEST_LEGACY_ASDF_VERSION" ;;
exec) shift 2; exec "$ASDF_DATA_DIR/installs/golang/$TEST_LEGACY_GO_VERSION/go/bin/go" "$@" ;;
*) exit 97 ;;
esac
LEGACY_ASDF
	printf '%s\n' '#!/usr/bin/env bash' 'exec "$ASDF_DATA_DIR/bin/asdf" exec go "$@"' >"$ASDF_DATA_DIR/shims/go"
	chmod +x "$old_install/go/bin/go" "$ASDF_DATA_DIR/bin/asdf" "$ASDF_DATA_DIR/shims/go"
	cp "$ASDF_DATA_DIR/bin/asdf" "$HOME/manager.before"
	printf '%s\n' '#!/usr/bin/env bash' 'echo retained-user-tool' >"$old_install/bin/user-tool"
	chmod +x "$old_install/bin/user-tool"
	printf keep >"$old_install/packages/marker"
	printf 'ruby 3.3.0\ngolang %s\n' "$TEST_LEGACY_GO_VERSION" >"$HOME/.tool-versions"
	printf 'keep-plugin\n' >"$ASDF_DATA_DIR/plugins/ruby/marker"
	printf 'keep-shim\n' >"$ASDF_DATA_DIR/shims/ruby"
	printf 'keep-sdk\n' >"$ASDF_DATA_DIR/installs/golang/0.0.1/marker"
	PATH="$HOME/.local/bin:$ASDF_DATA_DIR/bin:$ASDF_DATA_DIR/shims:$TEST_FAKE_BIN:/usr/bin:/bin"
	export PATH
	cd "$HOME"
	case "$mode" in
	declined) ;;
	force) export DOTFILES_FORCE_REINSTALL=1 ;;
	interactive-yes | interactive-no | changed-after-consent)
		DOTFILES_INTERACTIVE_TTY=true
		ui_confirm_yes_no() {
			[[ "$1" == *'Migrate the listed Go/asdf'* && "$mode" != interactive-no ]] || return 1
			[[ "$mode" != changed-after-consent ]] || printf 'python 3.12.0\n' >>"$HOME/.tool-versions"
		}
		;;
	*) export DOTFILES_MIGRATE_ASDF_GO=1 ;;
	esac
	case "$mode" in
	import-failure | retry) export TEST_GO_IMPORT_FAIL=1 ;;
	selection-failure) export TEST_ASDF_SELECT_FAIL=1 ;;
	reshim-failure | same-version-reshim-failure) export TEST_ASDF_RESHIM_FAIL=1 ;;
	unverifiable-go) printf '%s\n' '#!/usr/bin/env bash' 'echo unknown' >"$old_install/go/bin/go" ;;
	dirty-plugin) printf '\n# local edit\n' >>"$ASDF_DATA_DIR/plugins/golang/bin/install" ;;
	changed-before-publication) export TEST_GO_CHANGE_AFTER_DOWNLOAD=1 ;;
	plugin-publication-failure)
		mv() {
			if [[ "${*: -1}" == "$ASDF_DATA_DIR/plugins/golang" && "${*: -2:1}" == */plugin ]]; then return 46; fi
			command mv "$@"
		}
		;;
	manager-publication-failure)
		mv() {
			if [[ "${*: -1}" == "$ASDF_DATA_DIR/bin/asdf" && "${*: -2:1}" == */asdf ]]; then return 45; fi
			command mv "$@"
		}
		;;
	esac
	downloads_before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
	output="$(install_go_via_asdf 2>&1)" || status=$?
	if [[ "$mode" == success || "$mode" == same-version || "$mode" == interactive-yes ]]; then
		[[ "$status" == 0 ]] || {
			printf '%s\n' "$output" >&2
			return 1
		}
		dotfiles_catalog_native_owned go
		[[ "$("$HOME/.local/bin/go" version)" == 'go version go1.2.3 linux/amd64' ]]
		[[ "$("$ASDF_DATA_DIR/shims/user-tool")" == retained-user-tool ]]
		[[ "$(cat "$ASDF_DATA_DIR/installs/golang/1.2.3/packages/marker")" == keep ]]
		[[ -n "$(find "$ASDF_DATA_DIR/installs/golang" -name backup-4 -type f -print -quit)" ]]
	else
		[[ "$status" != 0 && ! -L "$ASDF_DATA_DIR/bin/asdf" && ! -e "$HOME/.local/bin/go" && ! -e "$HOME/.local/share/dotfiles-catalog/go.native" ]]
		cmp "$ASDF_DATA_DIR/bin/asdf" "$HOME/manager.before"
		if [[ "$mode" == declined || "$mode" == force || "$mode" == interactive-no || "$mode" == changed-after-consent || "$mode" == newer-go || "$mode" == newer-asdf || "$mode" == unverifiable-go || "$mode" == unverifiable-asdf || "$mode" == dirty-plugin ]]; then
			[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$downloads_before" ]]
		fi
		if [[ "$mode" == declined || "$mode" == force || "$mode" == interactive-no || "$mode" == changed-after-consent ]]; then [[ ! -e "$HOME/legacy-code-executed" ]]; fi
		if [[ "$mode" == unverifiable-go ]]; then
			[[ "$(GOTOOLCHAIN=local "$ASDF_DATA_DIR/shims/go" version)" == unknown ]]
		else
			[[ "$(GOTOOLCHAIN=local "$ASDF_DATA_DIR/shims/go" version)" == "go version go$TEST_LEGACY_GO_VERSION linux/amd64" ]]
		fi
		grep -Fxq "golang $TEST_LEGACY_GO_VERSION" "$HOME/.tool-versions"
		if [[ "$mode" == retry ]]; then
			unset TEST_GO_IMPORT_FAIL
			install_go_via_asdf >/dev/null
			dotfiles_catalog_native_owned go
			[[ "$("$ASDF_DATA_DIR/shims/user-tool")" == retained-user-tool ]]
		fi
	fi
	grep -Fxq 'ruby 3.3.0' "$HOME/.tool-versions"
	[[ "$(cat "$ASDF_DATA_DIR/plugins/ruby/marker")" == keep-plugin && "$(cat "$ASDF_DATA_DIR/shims/ruby")" == keep-shim ]]
	[[ "$(cat "$ASDF_DATA_DIR/installs/golang/0.0.1/marker")" == keep-sdk ]]
)
for mode in success same-version declined force interactive-yes interactive-no changed-after-consent changed-before-publication newer-go newer-asdf unverifiable-go unverifiable-asdf dirty-plugin import-failure selection-failure reshim-failure same-version-reshim-failure plugin-publication-failure manager-publication-failure retry; do
	legacy_migration_case "$mode"
	printf 'ok - native Go/asdf migration: %s\n' "$mode"
	rm -rf -- "$TEST_HARNESS_ROOT/legacy-$mode"
done
