#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$REPO_DIR/scripts/lib/catalog_legacy.sh"
declare -F dotfiles_catalog_asdf_go_inventory >/dev/null || {
	echo 'FAIL: bounded legacy Go/asdf inventory is missing' >&2
	exit 1
}

inventory_case() (
	local mode="$1" result='' status=0 path install_root
	export HOME="$TEST_HARNESS_ROOT/$mode/home" ASDF_DATA_DIR="$TEST_HARNESS_ROOT/$mode/home/.asdf"
	unset ASDF_GOLANG_VERSION ASDF_TOOL_VERSIONS_FILENAME ASDF_DIR
	install_root="$ASDF_DATA_DIR/installs/golang/1.2.2"
	mkdir -p "$install_root/go/bin" "$ASDF_DATA_DIR/bin" "$ASDF_DATA_DIR/shims" "$ASDF_DATA_DIR/plugins/golang/bin"
	for path in "$install_root/go/bin/go" "$ASDF_DATA_DIR/bin/asdf" "$ASDF_DATA_DIR/shims/go" "$ASDF_DATA_DIR/plugins/golang/bin/install"; do
		printf '%s\n' '#!/bin/sh' '# asdf-plugin: golang 1.2.2' 'touch "$HOME/legacy-code-executed"' >"$path"
		chmod +x "$path"
	done
	printf 'ruby 3.3.0\ngolang 1.2.2\n' >"$HOME/.tool-versions"
	/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" init -q
	/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" add bin/install
	/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm legacy
	/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" remote add origin https://github.com/asdf-community/asdf-golang.git
	PATH="$HOME/.local/bin:$ASDF_DATA_DIR/bin:$ASDF_DATA_DIR/shims:/usr/bin:/bin"
	export PATH
	cd "$HOME"
	case "$mode" in
	valid) ;;
	dirty-plugin) printf changed >>"$ASDF_DATA_DIR/plugins/golang/bin/install" ;;
	foreign-go)
		mkdir "$HOME/foreign"
		cp "$install_root/go/bin/go" "$HOME/foreign/go"
		PATH="$HOME/foreign:$PATH"
		;;
	escaped-manager)
		mv "$ASDF_DATA_DIR/bin/asdf" "$HOME/foreign-asdf"
		ln -s "$HOME/foreign-asdf" "$ASDF_DATA_DIR/bin/asdf"
		;;
	project-override)
		mkdir "$HOME/project"
		printf 'golang 1.2.1\n' >"$HOME/project/.tool-versions"
		cd "$HOME/project"
		;;
	environment-override) export ASDF_GOLANG_VERSION=1.2.1 ;;
	conflicting-receipt)
		mkdir -p "$HOME/.local/share/dotfiles-catalog"
		printf corrupt >"$HOME/.local/share/dotfiles-catalog/go.native"
		;;
	inactive-target) mkdir "$ASDF_DATA_DIR/installs/golang/1.2.3" ;;
	fsmonitor)
		cp "$ASDF_DATA_DIR/bin/asdf" "$HOME/fsmonitor-hook"
		/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" config core.fsmonitor "$HOME/fsmonitor-hook"
		;;
	python-shim)
		printf '%s\n' '#!/bin/sh' 'touch "$HOME/legacy-code-executed"' 'exec /usr/bin/python3 "$@"' >"$ASDF_DATA_DIR/shims/python3"
		chmod +x "$ASDF_DATA_DIR/shims/python3"
		;;
	clean-filter)
		printf 'bin/install filter=legacy\n' >"$ASDF_DATA_DIR/plugins/golang/.gitattributes"
		/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" add .gitattributes
		/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm attributes
		/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" config filter.legacy.clean 'touch "$HOME/legacy-code-executed"; cat'
		/usr/bin/python3 - "$ASDF_DATA_DIR/plugins/golang/bin/install" <<'PY'
import os,pathlib,sys
p=pathlib.Path(sys.argv[1]); metadata=p.stat()
p.write_bytes(p.read_bytes().replace(b'touch',b'xxxxx'))
os.utime(p,ns=(metadata.st_atime_ns,metadata.st_mtime_ns+2000000000))
PY
		;;
	assume-unchanged)
		/usr/bin/git -C "$ASDF_DATA_DIR/plugins/golang" update-index --assume-unchanged bin/install
		printf '\n# local edit\n' >>"$ASDF_DATA_DIR/plugins/golang/bin/install"
		;;
	esac
	result="$(dotfiles_catalog_asdf_go_inventory 1.2.3 2>/dev/null)" || status=$?
	if [[ "$mode" == valid || "$mode" == fsmonitor || "$mode" == python-shim ]]; then
		[[ "$status" == 0 && "$result" == "$install_root"$'\t'* && "${result##*$'\t'}" =~ ^[0-9a-f]{64}$ ]]
	else
		[[ "$status" != 0 ]]
	fi
	[[ ! -e "$HOME/legacy-code-executed" ]]
)
cases=(valid dirty-plugin foreign-go escaped-manager project-override environment-override conflicting-receipt inactive-target fsmonitor python-shim clean-filter assume-unchanged)
if (($#)); then cases=("$@"); fi
for mode in "${cases[@]}"; do
	inventory_case "$mode"
	printf 'ok - legacy Go/asdf inventory: %s\n' "$mode"
done
