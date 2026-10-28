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
	case "$url" in
	https://github.com/*) github_curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-all-errors -o "$fixture/$key.archive" "$url" ;;
	*) curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-all-errors -o "$fixture/$key.archive" "$url" ;;
	esac
	dotfiles_catalog_verify "$fixture/$key.archive" "$digest"
	mkdir "$fixture/$key"
	if [[ "$archive" == raw ]]; then
		cp "$fixture/$key.archive" "$fixture/$key/$binary"
	else
		dotfiles_catalog_extract "$archive" "$fixture/$key.archive" "$fixture/$key"
	fi
	chmod u+x "$fixture/$key/$binary"
}

/usr/bin/python3 -I -B "$root/scripts/catalog/legacy_native.py" "$DOTFILES_SHARED_ROOT" "$context" \
	"$root/tests/fixtures/catalog-legacy-native.json" >"$fixture/tools.tsv"
declare -a keys=()
while IFS=$'\t' read -r key url digest archive binary; do
	fetch_fixture "$key" "$url" "$digest" "$archive" "$binary"
	keys+=("$key")
done <"$fixture/tools.tsv"

migrate_fixture() (
	local key="$1" layout="$2" old_path before status=0 marker="$fixture/$1-$2.download" command_name binary version_arg baseline_version auto_env='' auto_value=''
	command_name="$(dotfiles_catalog_command_name "$key")"
	binary="$(/usr/bin/python3 -I -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["tools"][sys.argv[2]]["binary"])' "$root/tests/fixtures/catalog-legacy-native.json" "$key")"
	version_arg="$(dotfiles_catalog_version_arg "$key")"
	baseline_version="$(/usr/bin/python3 -I -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["tools"][sys.argv[2]]["version"])' "$root/tests/fixtures/catalog-legacy-native.json" "$key")"
	export HOME="$base_home/$key-$layout"
	mkdir -p "$HOME/.local/bin" "$HOME/bin"
	export PATH="$HOME/bin:$HOME/.local/bin:/usr/bin:/bin"
	unset DOTFILES_MIGRATE_LOCAL_TOOLS DOTFILES_FORCE_REINSTALL DOTFILES_INTERACTIVE_TTY
	old_path="$HOME/.local/bin/$command_name"
	[[ "$layout" != home-bin ]] || old_path="$HOME/bin/$command_name"
	cp -a -- "$fixture/$key" "$HOME/legacy-payload"
	ln -s "$HOME/legacy-payload/$binary" "$old_path"
	printf 'preserve\n' >"$HOME/user-configuration"
	before="$(sha256sum "$old_path" "$HOME/user-configuration")"
	for force in 0 1; do
		DOTFILES_FORCE_REINSTALL="$force" dotfiles_catalog_install "$key"
		[[ "$(sha256sum "$old_path" "$HOME/user-configuration")" == "$before" ]]
		if dotfiles_catalog_owned "$key"; then exit 1; fi
	done
	export DOTFILES_MIGRATE_LOCAL_TOOLS=1
	# Probe old vendor code only after consent, with the normal bounded process.
	# shellcheck source=/dev/null
	source "$root/scripts/lib/catalog_legacy.sh"
	case "$key" in
	claude_cli) auto_env=DISABLE_UPDATES auto_value=1 ;;
	antigravity_cli) auto_env=AGY_CLI_DISABLE_AUTO_UPDATE auto_value=true ;;
	esac
	[[ "$key" != codex_cli ]] || dotfiles_catalog_codex_defaults
	dotfiles_catalog_local_version_allowed "$old_path" "$baseline_version" "$version_arg" "$auto_env" "$auto_value" exact
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
		[[ "$(command -v "$command_name")" == "$old_path" ]]
		dotfiles_catalog_version_matches "$old_path" "$(dotfiles_catalog_get "$key" version)" "$version_arg"
	done
	local recovery
	recovery="$(dotfiles_catalog_root "$key")/current"
	[[ -f "$recovery/.catalog-legacy-recovery" ]]
	if [[ "$layout" == home-bin ]]; then recovery+='/previous-alias-0'; else recovery+='/previous-command'; fi
	[[ "$(sha256sum "$recovery" | cut -d ' ' -f1)" == "$(sha256sum "$fixture/$key/$binary" | cut -d ' ' -f1)" ]]
)
for key in "${keys[@]}"; do
	migrate_fixture "$key" local-bin
	case "$key" in uv | lazygit | direnv) migrate_fixture "$key" home-bin ;; esac
done
/usr/bin/python3 -I -B - "$DOTFILES_SHARED_ROOT" "$context" "$output" "$root/tests/fixtures/catalog-legacy-native.json" <<'PY'
import json,pathlib,sys
sys.path.insert(0,str(pathlib.Path(sys.argv[1])/'scripts/lib/shared/python'))
from catalog_context import load_qualification_context
snapshot,_,_=load_qualification_context(pathlib.Path(sys.argv[2]))
legacy=json.loads(pathlib.Path(sys.argv[4]).read_text())['tools']
result={
    'schema_version':1,'scope':'legacy-local-migration-smoke-only','approved':False,
    'catalog_digest':snapshot.digest,'sources':dict(snapshot.data['sources']),
    'legacy':{key:item['version'] for key,item in legacy.items()},
    'layouts':{key:['local-bin','home-bin'] if key in {'uv','lazygit','direnv'} else ['local-bin'] for key in legacy},
    'checks':dict.fromkeys(('default-preserved','force-preserved','failed-download','migration','repeat','recovery-copy','preservation'),'success'),
    'limits':['Native binaries only; not a complete legacy setup or qualification receipt'],
}
with pathlib.Path(sys.argv[3]).open('x') as stream:
    json.dump(result,stream,indent=2)
    stream.write('\n')
PY
