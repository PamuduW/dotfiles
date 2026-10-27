#!/usr/bin/env bash
set -euo pipefail
umask 077
(($# == 2)) || exit 64
context="$(realpath -- "$1")" || exit 2
output="$(realpath -m -- "$2")" || exit 2
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ ! -e "$output" && ! -L "$output" && -f /.dockerenv && "$EUID" != 0 ]] || exit 2
# shellcheck source=/dev/null
source "$root/scripts/lib/installers/load.sh"
software_catalog_qualification_begin "$context" || exit 2
[[ "$(software_catalog_qualification_source dotfiles)" == "$root" ]] || exit 2
dotfiles_catalog_begin || exit 2
for key in nodejs go chrome_headless mermaid_cli; do
	dotfiles_catalog_owned "$key" || exit 2
	[[ "$(dotfiles_catalog_installed "$key")" == "$(dotfiles_catalog_get "$key" version)" ]] || exit 2
	[[ "$(dotfiles_catalog_installed_identity "$key")" == "$(dotfiles_catalog_component_identity "$key")" ]] || exit 2
done
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
[[ "$("$HOME/.local/bin/node" -e 'process.stdout.write("catalog-ok")')" == catalog-ok ]] || exit 2
[[ "$(GOTOOLCHAIN=auto "$HOME/.local/bin/go" env GOTOOLCHAIN)" == local ]] || exit 2
printf '%s\n' 'package main' 'import "fmt"' 'func main() { fmt.Print("catalog-ok") }' >"$fixture/main.go"
[[ "$(GOTOOLCHAIN=auto GOPROXY=off GOSUMDB=off timeout 120 "$HOME/.local/bin/go" run "$fixture/main.go")" == catalog-ok ]] || exit 2
printf '%s\n' '<!doctype html><html><body><h1 id="catalog-smoke">Catalog</h1></body></html>' >"$fixture/page.html"
dom="$(timeout 30 "$HOME/.local/bin/chrome-headless-shell" --no-sandbox --disable-gpu --disable-dev-shm-usage --dump-dom "file://$fixture/page.html")"
[[ "$dom" == *'id="catalog-smoke"'* ]] || exit 2
printf '%s\n' 'graph TD' '  A --> B' >"$fixture/diagram.mmd"
python3 - "$fixture/puppeteer.json" "$HOME/.local/bin/chrome-headless-shell" <<'PY'
import json,pathlib,sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    'executablePath':sys.argv[2],'args':['--no-sandbox','--disable-dev-shm-usage'],
}))
PY
timeout 120 "$HOME/.local/bin/mmdc" -i "$fixture/diagram.mmd" -o "$fixture/diagram.svg" -p "$fixture/puppeteer.json"
python3 - "$DOTFILES_SHARED_ROOT/scripts/lib/shared/python" "$context" "$output" "$fixture/diagram.svg" <<'PY'
import json,pathlib,sys,xml.etree.ElementTree as ET
sys.path.insert(0,sys.argv[1])
from catalog_context import load_qualification_context
svg=ET.parse(sys.argv[4]).getroot()
labels=''.join(svg.itertext())
if svg.tag.rsplit('}',1)[-1]!='svg' or 'A' not in labels or 'B' not in labels:
    raise SystemExit('Mermaid did not render both SVG node labels')
snapshot,_,_=load_qualification_context(pathlib.Path(sys.argv[2]))
result={
    'schema_version':1,'scope':'behavior-smoke-only','approved':False,
    'catalog_digest':snapshot.digest,'sources':dict(snapshot.data['sources']),
    'checks':dict.fromkeys(['node-execution','go-compilation','chrome-dom','mermaid-svg'],'success'),
}
with pathlib.Path(sys.argv[3]).open('x') as stream:
    json.dump(result,stream,indent=2)
    stream.write('\n')
PY
