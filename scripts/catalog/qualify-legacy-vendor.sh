#!/usr/bin/env bash
set -euo pipefail
umask 077
(($# == 2)) || exit 64
context="$(realpath -- "$1")" || exit 2
output="$(realpath -m -- "$2")" || exit 2
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f /.dockerenv && "$EUID" != 0 && "${GITHUB_ACTIONS:-}" == true && ! -e "$output" && ! -L "$output" ]] || exit 2
[[ ! -e /var/run/docker.sock && ! -e /run/docker.sock ]] || exit 2
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
status=0
pgrep -x dockerd >/dev/null || status=$?
[[ "$status" == 1 ]] || exit 2
status=0
sudo -n /usr/sbin/policy-rc.d || status=$?
[[ "$status" == 101 ]] || exit 2
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
/usr/bin/python3 -I -B - "$DOTFILES_SHARED_ROOT" "$context" "$root/tests/fixtures/catalog-legacy-vendor.json" >"$fixture/packages.tsv" <<'PY'
import json,pathlib,re,sys,urllib.parse
sys.path.insert(0,str(pathlib.Path(sys.argv[1])/'scripts/lib/shared/python'))
from catalog_context import load_qualification_context
from software_catalog import _object
snapshot,_,_=load_qualification_context(pathlib.Path(sys.argv[2]))
fixture=json.loads(pathlib.Path(sys.argv[3]).read_text(),object_pairs_hook=_object)
assert set(fixture)=={'schema_version','origin_run_id','approved','packages'}
assert fixture['schema_version']==1 and fixture['approved'] is False and fixture['origin_run_id']==40477067865
expected={key for key,entry in snapshot.data['components'].items() if entry['owner']=='dotfiles' and
          (entry['kind']=='vendor-apt' or any(item.get('archive')=='deb' for item in entry['targets'].values()))}
assert expected and set(fixture['packages'])==expected, 'legacy vendor fixture does not cover current inventory'
for key,item in sorted(fixture['packages'].items()):
    assert set(item)=={'package','version','url','digest'}
    assert all(isinstance(v,str) and not any(ord(c)<32 or ord(c)==127 for c in v) for v in item.values())
    assert re.fullmatch(r'[a-z0-9][a-z0-9+.-]+',item['package'])
    assert re.fullmatch(r'[0-9][A-Za-z0-9.+:~_-]+',item['version'])
    assert re.fullmatch(r'sha256:[a-f0-9]{64}',item['digest'])
    url=urllib.parse.urlsplit(item['url'])
    assert url.scheme=='https' and url.hostname in {'github.com','download.docker.com'} and not url.username and not url.password and not url.port and not url.query and not url.fragment
    assert snapshot.data['components'][key]['targets']['linux-amd64']['package']==item['package']
    print('\t'.join([key,item['package'],item['version'],item['url'],item['digest']]))
PY
declare -a keys=() packages=() versions=() files=()
while IFS=$'\t' read -r key package version url digest; do
	if dpkg-query -W "$package" >/dev/null 2>&1; then exit 2; fi
	file="$fixture/$package.deb"
	case "$url" in
	https://github.com/*) github_curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-all-errors -o "$file" "$url" ;;
	https://download.docker.com/*) curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-all-errors -o "$file" "$url" ;;
	*) exit 2 ;;
	esac
	dotfiles_catalog_verify "$file" "$digest"
	[[ "$(dpkg-deb -f "$file" Package)" == "$package" && "$(dpkg-deb -f "$file" Version)" == "$version" && "$(dpkg-deb -f "$file" Architecture)" == amd64 ]]
	keys+=("$key")
	packages+=("$package")
	versions+=("$version")
	files+=("$file")
done <"$fixture/packages.tsv"
((${#keys[@]} > 0))
sudo apt-get update >&2
sudo apt-get -qq -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=600 install -y --no-install-recommends "${files[@]}" >&2
verify_legacy_packages() {
	local index
	for index in "${!packages[@]}"; do
		[[ "$(dpkg-query -W -f='${Version}' "${packages[$index]}")" == "${versions[$index]}" ]]
		[[ ! -e "$HOME/.local/share/dotfiles-catalog/${keys[$index]}.apt" && ! -L "$HOME/.local/share/dotfiles-catalog/${keys[$index]}.apt" ]]
	done
}
verify_legacy_packages
printf 'preserve\n' >"$HOME/operator-settings"
unset DOTFILES_MIGRATE_APT_PACKAGES DOTFILES_INTERACTIVE_TTY
for force in 0 1; do
	DOTFILES_FORCE_REINSTALL="$force" dotfiles_catalog_install_debs "${keys[@]}"
	verify_legacy_packages
done
export DOTFILES_MIGRATE_APT_PACKAGES=1
status=0
(
	# shellcheck disable=SC2317,SC2329  # Invoked by the normal installer transaction.
	dotfiles_catalog_download() {
		printf '%s\n' "$1" >"$fixture/download-reached"
		return 71
	}
	dotfiles_catalog_install_debs "${keys[@]}"
) || status=$?
[[ "$status" == 71 && -s "$fixture/download-reached" ]]
verify_legacy_packages
for phase in migrate repeat; do
	printf 'Real legacy vendor packages: %s\n' "$phase" >&2
	dotfiles_catalog_install_debs "${keys[@]}" >&2
	holds="$(apt-mark showhold)"
	for index in "${!keys[@]}"; do
		key="${keys[$index]}"
		package="${packages[$index]}"
		dotfiles_catalog_apt_owned "$key" "$package"
		[[ "$(dpkg-query -W -f='${Version}' "$package")" == "$(dotfiles_catalog_get "$key" version)" ]]
		grep -Fxq "$package" <<<"$holds"
	done
	[[ "$(cat "$HOME/operator-settings")" == preserve ]]
done
status=0
pgrep -x dockerd >/dev/null || status=$?
[[ "$status" == 1 ]]
/usr/bin/python3 -I -B - "$DOTFILES_SHARED_ROOT" "$context" "$output" "$root/tests/fixtures/catalog-legacy-vendor.json" <<'PY'
import json,pathlib,sys
sys.path.insert(0,str(pathlib.Path(sys.argv[1])/'scripts/lib/shared/python'))
from catalog_context import load_qualification_context
snapshot,_,_=load_qualification_context(pathlib.Path(sys.argv[2]))
legacy=json.loads(pathlib.Path(sys.argv[4]).read_text())
result={
    'schema_version':1,'scope':'legacy-vendor-migration-smoke-only','approved':False,
    'catalog_digest':snapshot.digest,'sources':dict(snapshot.data['sources']),
    'legacy_origin_run_id':legacy['origin_run_id'],
    'legacy_versions':{key:item['version'] for key,item in legacy['packages'].items()},
    'checks':dict.fromkeys(('default-preserved','force-preserved','failed-download','migration','repeat','holds','preservation'),'success'),
    'limits':['Vendor package layouts only; not a complete legacy setup or daemon qualification'],
}
with pathlib.Path(sys.argv[3]).open('x') as stream:
    json.dump(result,stream,indent=2)
    stream.write('\n')
PY
