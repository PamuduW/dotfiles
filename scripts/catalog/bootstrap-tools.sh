#!/usr/bin/env bash
# Install initial discovery tools only in a new private qualification home.
set -euo pipefail
umask 077
if (($# != 3)); then
	printf 'Usage: bootstrap-tools.sh QUALIFICATION_CONTEXT NEW_HOME TOOL_DESCRIPTOR\n' >&2
	exit 64
fi
catalog_context="$(realpath -- "$1")" || exit 2
catalog_new_home="$(realpath -m -- "$2")" || exit 2
catalog_descriptor="$(realpath -m -- "$3")" || exit 2
catalog_product_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -e "$catalog_new_home" || -L "$catalog_new_home" || -e "$catalog_descriptor" || -L "$catalog_descriptor" ]]; then
	printf 'Initial tooling needs a new home and descriptor; preserving existing paths.\n' >&2
	exit 2
fi
env -i PATH=/usr/bin:/bin LANG=C.UTF-8 HOME="$catalog_new_home" USER="$(id -un)" \
	DOTFILES_DIR="$catalog_product_root" bash -s -- "$catalog_context" "$catalog_descriptor" <<'QUALIFY'
set -euo pipefail
umask 077
catalog_context="$1"
catalog_descriptor="$2"
# Modules are independently linted; keep this coordinator's source graph bounded.
# shellcheck source=/dev/null
source "$DOTFILES_DIR/scripts/lib/installers/load.sh"
software_catalog_qualification_begin "$catalog_context" || exit 2
[[ "$(realpath -- "$DOTFILES_DIR")" == "$(software_catalog_qualification_source dotfiles)" ]] || exit 2
mkdir -m 700 -- "$HOME"
install_node_via_nvm
ensure_graphify_uv
runtime_output="$(dotfiles_catalog_npm_runtime)"
mapfile -t runtime <<<"$runtime_output"
[[ "${#runtime[@]}" == 2 ]] || exit 2
dotfiles_catalog_owned uv || exit 2
catalog_uv="$(realpath -- "$HOME/.local/bin/uv")"
software_catalog_begin "$DOTFILES_SHARED_ROOT" || exit 2
python3 - "$catalog_descriptor" "${runtime[0]}" "${runtime[1]}" "$catalog_uv" "$SOFTWARE_CATALOG_DIGEST" <<'DESCRIPTOR'
import json,os,sys
path,node,npm,uv,digest=sys.argv[1:]
fd=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
with os.fdopen(fd,'w') as stream:
    json.dump({'schema_version':1,'target':'linux-amd64','catalog_digest':digest,'node':node,'npm':npm,'uv':uv},stream,indent=2)
    stream.write('\n')
DESCRIPTOR
QUALIFY
