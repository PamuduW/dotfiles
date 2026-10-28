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
[[ -d "$HOME" && ! -L "$HOME" && -O "$HOME" && "$(realpath -- "$HOME")" == "$HOME" ]] || exit 2
[[ -z "$(find "$HOME" -mindepth 1 -maxdepth 1 -print -quit)" ]] || exit 2
[[ "$(uname -m)" == x86_64 ]] || exit 2
# shellcheck source=/dev/null
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || exit 2
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
base_home="$HOME"

# Frozen vendor inputs construct pre-catalog local layouts without ownership
# receipts. These fixtures are independent of candidate version selection.
fetch_fixture() {
	local key="$1" url="$2" digest="$3" archive="$4" binary="$5"
	github_curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 \
		--retry 2 --retry-all-errors -o "$fixture/$key.archive" "$url"
	dotfiles_catalog_verify "$fixture/$key.archive" "$digest"
	mkdir "$fixture/$key"
	if [[ "$archive" == raw ]]; then
		cp "$fixture/$key.archive" "$fixture/$key/$binary"
	else
		dotfiles_catalog_extract "$archive" "$fixture/$key.archive" "$fixture/$key"
	fi
	install -m 755 "$fixture/$key/$binary" "$fixture/$key.command"
}

fetch_fixture uv 'https://github.com/astral-sh/uv/releases/download/0.13.6/uv-x86_64-unknown-linux-gnu.tar.gz' \
	sha256:f29c3e94ffabd7e6f3ba521dba169a9b7ec12100bf3257087f0f24f6123f3645 tar.gz uv-x86_64-unknown-linux-gnu/uv
fetch_fixture lazygit 'https://github.com/jesseduffield/lazygit/releases/download/v0.66.2/lazygit_0.66.2_linux_x86_64.tar.gz' \
	sha256:158efc9ddfa1241fab5fb3526bb442c8dc6c4b1904d73213b9e4e93e03c52034 tar lazygit
fetch_fixture direnv 'https://github.com/direnv/direnv/releases/download/v2.38.2/direnv.linux-amd64' \
	sha256:148820a187930d36ca6a204504e5cdb30d8396cd1a97e64c3b3f10d793c11247 raw direnv

migrate_fixture() (
	local key="$1" layout="$2" old_path before status=0 marker="$fixture/$1-$2.download"
	export HOME="$base_home/$key-$layout"
	mkdir -p "$HOME/.local/bin" "$HOME/bin"
	export PATH="$HOME/bin:$HOME/.local/bin:/usr/bin:/bin"
	unset DOTFILES_MIGRATE_LOCAL_TOOLS DOTFILES_FORCE_REINSTALL DOTFILES_INTERACTIVE_TTY
	old_path="$HOME/.local/bin/$key"
	[[ "$layout" != home-bin ]] || old_path="$HOME/bin/$key"
	install -m 755 "$fixture/$key.command" "$old_path"
	printf 'preserve\n' >"$HOME/user-configuration"
	before="$(sha256sum "$old_path" "$HOME/user-configuration")"
	for force in 0 1; do
		DOTFILES_FORCE_REINSTALL="$force" dotfiles_catalog_install "$key"
		[[ "$(sha256sum "$old_path" "$HOME/user-configuration")" == "$before" ]]
		if dotfiles_catalog_owned "$key"; then exit 1; fi
	done
	export DOTFILES_MIGRATE_LOCAL_TOOLS=1
	(
		# shellcheck disable=SC2317,SC2329  # The installer invokes this callback.
		dotfiles_catalog_download() {
			printf '%s\n' "$1" >"$marker"
			return 71
		}
		dotfiles_catalog_install "$key"
	) || status=$?
	[[ "$status" == 71 && -s "$marker" ]]
	[[ "$(sha256sum "$old_path" "$HOME/user-configuration")" == "$before" ]]
	for phase in migrate repeat; do
		printf 'Real local migration %s: %s/%s\n' "$phase" "$key" "$layout" >&2
		dotfiles_catalog_install "$key"
		dotfiles_catalog_owned "$key"
		[[ "$(dotfiles_catalog_installed "$key")" == "$(dotfiles_catalog_get "$key" version)" ]]
		[[ "$(cat "$HOME/user-configuration")" == preserve ]]
		[[ "$(command -v "$key")" == "$old_path" ]]
		dotfiles_catalog_version_matches "$old_path" "$(dotfiles_catalog_get "$key" version)" --version
	done
	local recovery
	recovery="$(dotfiles_catalog_root "$key")/current"
	[[ -f "$recovery/.catalog-legacy-recovery" ]]
	if [[ "$layout" == home-bin ]]; then recovery+='/previous-alias-0'; else recovery+='/previous-command'; fi
	[[ "$(sha256sum "$recovery" | cut -d ' ' -f1)" == "$(sha256sum "$fixture/$key.command" | cut -d ' ' -f1)" ]]
)
for key in uv lazygit direnv; do
	for layout in local-bin home-bin; do migrate_fixture "$key" "$layout"; done
done
/usr/bin/python3 -I -B - "$DOTFILES_SHARED_ROOT" "$context" "$output" <<'PY'
import json,pathlib,sys
sys.path.insert(0,str(pathlib.Path(sys.argv[1])/'scripts/lib/shared/python'))
from catalog_context import load_qualification_context
snapshot,_,_=load_qualification_context(pathlib.Path(sys.argv[2]))
result={
    'schema_version':1,'scope':'legacy-local-migration-smoke-only','approved':False,
    'catalog_digest':snapshot.digest,'sources':dict(snapshot.data['sources']),
    'legacy':{'uv':'0.13.6','lazygit':'0.66.2','direnv':'2.38.2'},
    'layouts':['local-bin','home-bin'],
    'checks':dict.fromkeys(('default-preserved','force-preserved','failed-download','migration','repeat','recovery-copy','preservation'),'success'),
    'limits':['Three native binaries only; not a complete legacy setup or qualification receipt'],
}
with pathlib.Path(sys.argv[3]).open('x') as stream:
    json.dump(result,stream,indent=2)
    stream.write('\n')
PY
