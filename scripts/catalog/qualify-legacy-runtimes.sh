#!/usr/bin/env bash
set -euo pipefail
umask 077
(($# == 2)) || exit 64
context="$(realpath -- "$1")" || exit 2
output="$(realpath -m -- "$2")" || exit 2
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f /.dockerenv && "$EUID" != 0 && ! -e "$output" && ! -L "$output" ]] || exit 2
# shellcheck source=/dev/null
source "$root/scripts/lib/installers/load.sh"
software_catalog_qualification_begin "$context" || exit 2
[[ "$(software_catalog_qualification_source dotfiles)" == "$root" ]] || exit 2
dotfiles_catalog_begin || exit 2
# Require a dedicated empty home: this driver creates a legacy installation.
[[ -d "$HOME" && ! -L "$HOME" && -O "$HOME" && "$(realpath -- "$HOME")" == "$HOME" ]] || exit 2
[[ -z "$(find "$HOME" -mindepth 1 -maxdepth 1 -print -quit)" ]] || exit 2
[[ "$(uname -m)" == x86_64 ]] || exit 2
# shellcheck source=/dev/null
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || exit 2

# Frozen vendor inputs for the pre-catalog manager layouts. These are test
# fixtures, not an approved catalog or a version override for the candidate.
node_version=24.22.1
go_version=1.27.3
nvm_revision=977563e97ddc66facf3a8e31c6cff01d236f09bd
plugin_revision=a75b761963d8e6eda1a185c73476da8a75b8d300
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

fetch_archive() {
	local name="$1" url="$2" digest="$3" kind="$4"
	curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 \
		--retry 2 --retry-all-errors -o "$fixture/$name.archive" "$url"
	dotfiles_catalog_verify "$fixture/$name.archive" "$digest"
	mkdir "$fixture/$name"
	dotfiles_catalog_extract "$kind" "$fixture/$name.archive" "$fixture/$name"
}

fetch_asdf_archive() {
	github_curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 \
		--retry 2 --retry-all-errors -o "$fixture/asdf.archive" \
		'https://github.com/asdf-vm/asdf/releases/download/v0.20.2/asdf-v0.20.2-linux-amd64.tar.gz'
	dotfiles_catalog_verify "$fixture/asdf.archive" sha256:6d45e6fab12f50a259b5643adf06a2e77af30a87300b4402440eda09af467a6d
	mkdir "$fixture/asdf"
	dotfiles_catalog_extract tar.gz "$fixture/asdf.archive" "$fixture/asdf"
}

checkout_source() {
	local repository="$1" revision="$2" destination="$3"
	_dotfiles_catalog_source_git init -q "$destination"
	_dotfiles_catalog_source_git -C "$destination" remote add origin "https://github.com/$repository.git"
	_dotfiles_catalog_source_git -C "$destination" fetch -q --depth=1 origin "$revision"
	_dotfiles_catalog_source_git -C "$destination" checkout -q --detach "$revision"
	/usr/bin/python3 -I -B - "$DOTFILES_SHARED_ROOT" "$destination" "$revision" <<'PY'
import pathlib,sys
sys.path.insert(0,str(pathlib.Path(sys.argv[1])/'scripts/lib/shared/python'))
from catalog_git_source import verify_checkout
verify_checkout(pathlib.Path(sys.argv[2]),sys.argv[3])
PY
}

verify_preserved_state() {
	local selected_prefix
	selected_prefix="$NVM_DIR/versions/node/v$(dotfiles_catalog_get nodejs version)" || return 2
	[[ -x "$selected_prefix/bin/legacy-runtime-probe" &&
		"$("$selected_prefix/bin/legacy-runtime-probe")" == legacy-preserved &&
		"$(cat "$HOME/.npmrc")" == fund=false &&
		"$(grep -xc 'legacy-other 1.0' "$HOME/.tool-versions")" == 1 ]]
}

expect_failed_download() {
	local installer="$1" marker="$2" status=0
	# Exercise the normal transaction with an unavailable archive boundary.
	(
		# shellcheck disable=SC2317,SC2329  # Called by the normal installer transaction.
		dotfiles_catalog_download() {
			printf '%s\n' "$1" >"$marker"
			return 71
		}
		"$installer"
	) || status=$?
	[[ "$status" == 71 && -s "$marker" ]]
}

# shellcheck source=/dev/null
source "$root/scripts/lib/catalog_sources.sh"
fetch_archive node "https://nodejs.org/dist/v$node_version/node-v$node_version-linux-x64.tar.xz" \
	sha256:6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6 tar.xz
fetch_asdf_archive
fetch_archive go "https://go.dev/dl/go$go_version.linux-amd64.tar.gz" \
	sha256:65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40 tar.gz
export NVM_DIR="$HOME/.nvm" ASDF_DATA_DIR="$HOME/.asdf"
checkout_source nvm-sh/nvm "$nvm_revision" "$NVM_DIR"
mkdir -p "$NVM_DIR/versions/node" "$ASDF_DATA_DIR/bin" "$ASDF_DATA_DIR/plugins" "$ASDF_DATA_DIR/installs/golang/$go_version"
mv "$fixture/node/node-v$node_version-linux-x64" "$NVM_DIR/versions/node/v$node_version"
install -m 755 "$fixture/asdf/asdf" "$ASDF_DATA_DIR/bin/asdf"
checkout_source asdf-community/asdf-golang "$plugin_revision" "$ASDF_DATA_DIR/plugins/golang"
mv "$fixture/go/go" "$ASDF_DATA_DIR/installs/golang/$go_version/go"
export PATH="$HOME/.local/bin:$ASDF_DATA_DIR/bin:$ASDF_DATA_DIR/shims:$NVM_DIR/versions/node/v$node_version/bin:/usr/bin:/bin"
cd "$HOME"
# Use the real managers to select their legacy installations and generate shims.
# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh" --no-use
nvm alias default "v$node_version"
asdf set -u golang "$go_version"
asdf reshim golang
[[ "$(node --version)" == "v$node_version" && "$(GOTOOLCHAIN=local go version)" == "go version go$go_version linux/amd64" ]]
[[ "$(nvm --version)" == 0.40.3 ]]
[[ ! -e "$HOME/.local/share/dotfiles-catalog" ]]
printf 'legacy-other 1.0\n' >>"$HOME/.tool-versions"
printf 'fund=false\n' >"$HOME/.npmrc"
prefix="$NVM_DIR/versions/node/v$node_version"
mkdir -p "$prefix/lib/node_modules/legacy-runtime-probe"
printf '{"name":"legacy-runtime-probe","version":"1.0.0","bin":{"legacy-runtime-probe":"cli.js"}}\n' >"$prefix/lib/node_modules/legacy-runtime-probe/package.json"
printf '%s\n' '#!/usr/bin/env node' 'process.stdout.write("legacy-preserved")' >"$prefix/lib/node_modules/legacy-runtime-probe/cli.js"
chmod +x "$prefix/lib/node_modules/legacy-runtime-probe/cli.js"
ln -s ../lib/node_modules/legacy-runtime-probe/cli.js "$prefix/bin/legacy-runtime-probe"
[[ "$(legacy-runtime-probe)" == legacy-preserved ]]
baseline_state="$(sha256sum "$NVM_DIR/nvm.sh" "$prefix/bin/node" "$ASDF_DATA_DIR/bin/asdf" "$ASDF_DATA_DIR/shims/go" "$HOME/.tool-versions")"
for installer in install_node_via_nvm install_go_via_asdf; do
	if (DOTFILES_FORCE_REINSTALL=1 "$installer"); then
		printf 'Migration unexpectedly accepted force as consent: %s\n' "$installer" >&2
		exit 2
	fi
done
[[ "$(sha256sum "$NVM_DIR/nvm.sh" "$prefix/bin/node" "$ASDF_DATA_DIR/bin/asdf" "$ASDF_DATA_DIR/shims/go" "$HOME/.tool-versions")" == "$baseline_state" ]]
export DOTFILES_MIGRATE_NVM=1 DOTFILES_MIGRATE_ASDF_GO=1
for installer in install_node_via_nvm install_go_via_asdf; do
	expect_failed_download "$installer" "$fixture/$installer.download-reached"
done
[[ "$(sha256sum "$NVM_DIR/nvm.sh" "$prefix/bin/node" "$ASDF_DATA_DIR/bin/asdf" "$ASDF_DATA_DIR/shims/go" "$HOME/.tool-versions")" == "$baseline_state" ]]
[[ "$(legacy-runtime-probe)" == legacy-preserved && "$(GOTOOLCHAIN=local go version)" == "go version go$go_version linux/amd64" ]]
for phase in migrate repeat; do
	printf 'Real legacy runtimes: %s\n' "$phase" >&2
	install_node_via_nvm
	install_go_via_asdf
	for key in nodejs npm go asdf; do
		dotfiles_catalog_owned "$key"
		[[ "$(dotfiles_catalog_installed "$key")" == "$(dotfiles_catalog_get "$key" version)" ]]
	done
	dotfiles_catalog_source_owned nvm
	dotfiles_catalog_source_owned asdf-golang
	verify_preserved_state
	[[ "$("$HOME/.local/bin/node" -p '6*7')" == 42 ]]
	printf '%s\n' 'package main' 'import "fmt"' 'func main() { fmt.Print("legacy-migrated") }' >"$fixture/main.go"
	[[ "$(GOPROXY=off GOSUMDB=off timeout 120 "$HOME/.local/bin/go" run "$fixture/main.go")" == legacy-migrated ]]
done
/usr/bin/python3 -I -B - "$DOTFILES_SHARED_ROOT" "$context" "$output" "$nvm_revision" "$plugin_revision" "$node_version" "$go_version" <<'PY'
import json,pathlib,sys
sys.path.insert(0,str(pathlib.Path(sys.argv[1])/'scripts/lib/shared/python'))
from catalog_context import load_qualification_context
snapshot,_,_=load_qualification_context(pathlib.Path(sys.argv[2]))
result={
    'schema_version':1,'scope':'legacy-runtime-migration-smoke-only','approved':False,
    'catalog_digest':snapshot.digest,'sources':dict(snapshot.data['sources']),
    'legacy':dict(zip(('nvm_revision','plugin_revision','node_version','go_version'),sys.argv[4:])),
    'checks':dict.fromkeys(('declined','failed-download','migration','repeat','node-execution','go-compilation','preservation'),'success'),
    'limits':['Runtime layouts only; not a complete legacy setup or qualification receipt'],
}
with pathlib.Path(sys.argv[3]).open('x') as stream:
    json.dump(result,stream,indent=2)
    stream.write('\n')
PY
