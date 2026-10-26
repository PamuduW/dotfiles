#!/usr/bin/env bash
set -euo pipefail
umask 077
(($# == 2)) || exit 64
context="$(realpath -- "$1")" || exit 2
output="$(realpath -m -- "$2")" || exit 2
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ ! -e "$output" && ! -L "$output" && -f /.dockerenv && "$EUID" != 0 ]] || exit 2
# Keep this coordinator's static source graph bounded.
# shellcheck source=/dev/null
source "$root/scripts/lib/installers/load.sh"
software_catalog_qualification_begin "$context" || exit 2
[[ "$(software_catalog_qualification_source dotfiles)" == "$root" ]] || exit 2
dotfiles_catalog_begin || exit 2
font_dir="$HOME/.local/share/fonts/ubuntu-sans-mono"
[[ ! -e "$font_dir" && ! -L "$font_dir" ]] || exit 2
expected="$(dotfiles_catalog_get ubuntu_sans_mono_fonts version)" || exit 2
for phase in fresh repeat; do
	printf 'Linux font smoke: %s\n' "$phase"
	install_ubuntu_sans_mono_fonts
	dotfiles_catalog_fonts_owned || exit 2
	[[ "$(cat "$font_dir/.version")" == "$expected" ]] || exit 2
	registered="$(fc-list --format='%{file}\n')"
	[[ "$registered" == *"$font_dir/"* ]] || exit 2
	matched="$(fc-match --format='%{file}' 'Ubuntu Sans Mono')"
	[[ "$matched" == "$font_dir/"* && -f "$matched" ]] || exit 2
done
python3 - "$DOTFILES_SHARED_ROOT/scripts/lib/shared/python" "$context" "$output" "$matched" <<'PY'
import json,pathlib,sys
sys.path.insert(0,sys.argv[1])
from catalog_context import load_qualification_context
from software_catalog import resolve_entry
snapshot,_,_=load_qualification_context(pathlib.Path(sys.argv[2]))
version=resolve_entry(snapshot,'ubuntu_sans_mono_fonts','linux-amd64',require_approved=False)['version']
result={
    'schema_version':1,'scope':'linux-font-smoke-only','approved':False,
    'catalog_digest':snapshot.digest,'sources':dict(snapshot.data['sources']),
    'version':version,'fresh':'success','repeat':'success','fontconfig_match':sys.argv[4],
}
with pathlib.Path(sys.argv[3]).open('x') as stream:
    json.dump(result,stream,indent=2)
    stream.write('\n')
PY
