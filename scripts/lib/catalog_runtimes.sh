# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/catalog_load.sh"
# shellcheck source=scripts/lib/catalog_sources.sh
source "${BASH_SOURCE[0]%/*}/catalog_sources.sh"

_dotfiles_catalog_runtime_receipt() {
	local destination="$1" manager="$2" version="$3" prefix="$4" identity="$5"
	printf 'native-runtime-v1\n%s\n%s\n%s\n%s\n%s\n%s\n' \
		"$manager" "$version" "$SOFTWARE_CATALOG_DIGEST" "$SOFTWARE_CATALOG_REVISION" "$prefix" "$identity" >"$destination"
}

dotfiles_catalog_node_install() (
	# shellcheck disable=SC2034  # Holds the transaction descriptor until this subshell exits.
	local lock_fd
	dotfiles_catalog_transaction_lock nodejs lock_fd || return $?
	dotfiles_catalog_begin || return $?
	local runtime_key node_version npm_version nvm_version binary archive npm_archive identity source_checkout root prefix stage candidate native_archive compression
	local committed=0 prefix_published=0 prefix_backed_up=0 keep_stage=0 index rc=0 previous_prefix=''
	local -a paths=() prepared=() changed=() old_proof=()
	[[ "${SOFTWARE_CATALOG_REVISION:-}" =~ ^[0-9a-f]{40}$ ]] || return 2
	for runtime_key in nodejs npm; do [[ "$(dotfiles_catalog_get "$runtime_key" owner)" == dotfiles ]] || return 2; done
	[[ "$(dotfiles_catalog_get nvm kind)" == git-source ]] || return 2
	node_version="$(dotfiles_catalog_get nodejs version)" || return 2
	npm_version="$(dotfiles_catalog_get npm version)" || return 2
	nvm_version="$(dotfiles_catalog_get nvm version)" || return 2
	[[ "$node_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$npm_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 2
	archive="$(dotfiles_catalog_get nodejs archive)" || return 2
	npm_archive="$(dotfiles_catalog_get npm archive)" || return 2
	case "$archive" in tar.gz | tar.xz | tgz | tar) ;; *) return 2 ;; esac
	case "$npm_archive" in tar.gz | tgz | tar) ;; *) return 2 ;; esac
	binary="$(dotfiles_catalog_get nodejs binary)" || return 2
	[[ "$binary" =~ ^[A-Za-z0-9._+-]+/bin/node$ && "$(dotfiles_catalog_get npm binary)" == package/bin/npm-cli.js ]] || return 2
	if dotfiles_catalog_external nodejs || dotfiles_catalog_external npm; then
		printf 'Preserving externally owned Node/npm; native catalog activation is blocked.\n' >&2
		return 2
	fi
	if dotfiles_catalog_native_owned npm; then
		local active_npx native_npx_root
		mapfile -t old_proof <"$HOME/.local/share/dotfiles-catalog/npm.native"
		native_npx_root="${old_proof[5]}"
		if [[ -e "$HOME/.local/bin/npx" || -L "$HOME/.local/bin/npx" ]]; then
			[[ -L "$HOME/.local/bin/npx" && "$(readlink -- "$HOME/.local/bin/npx")" == "$native_npx_root/bin/npx" ]] || {
				printf 'Preserving external npx; native runtime activation is blocked.\n' >&2
				return 2
			}
		fi
		active_npx="$(command -v npx 2>/dev/null || true)"
		if [[ -n "$active_npx" ]]; then
			[[ "$(realpath -- "$active_npx")" == "$native_npx_root/lib/node_modules/npm/bin/npx-cli.js" ]] || return 2
		fi
	else
		dotfiles_catalog_npm_preflight || return 2
	fi
	for runtime_key in nodejs npm; do
		if dotfiles_catalog_managed "$runtime_key" &&
			! dotfiles_catalog_version_matches "$HOME/.local/bin/$(dotfiles_catalog_command_name "$runtime_key")" "$(dotfiles_catalog_get "$runtime_key" version)" --version &&
			! dotfiles_catalog_upgrade_allowed "$HOME/.local/bin/$(dotfiles_catalog_command_name "$runtime_key")" "$(dotfiles_catalog_get "$runtime_key" version)" --version; then
			printf 'Preserving newer or unverifiable %s; review version drift.\n' "$runtime_key" >&2
			return 2
		fi
	done
	root="${NVM_DIR:-$HOME/.nvm}"
	prefix="$root/versions/node/v$node_version"
	[[ "$root" == /* && ! -L "$root" && ! -L "$root/versions" && ! -L "$root/versions/node" ]] || return 2
	if [[ -e "$root/nvm.sh" || -L "$root/nvm.sh" ]]; then
		[[ -L "$root/nvm.sh" && "$(readlink -- "$root/nvm.sh")" == "$(dotfiles_catalog_root nvm)/current/nvm.sh" ]] || return 2
		dotfiles_catalog_source_owned nvm || return 2
	fi
	if dotfiles_catalog_native_owned nodejs; then
		mapfile -t old_proof <"$HOME/.local/share/dotfiles-catalog/nodejs.native"
		previous_prefix="${old_proof[5]}"
	fi
	if [[ -e "$prefix" || -L "$prefix" ]]; then
		dotfiles_catalog_native_owned nodejs || return 2
		mapfile -t old_proof <"$HOME/.local/share/dotfiles-catalog/nodejs.native"
		[[ "${old_proof[5]}" == "$prefix" ]] || return 2
	fi
	identity="$(dotfiles_catalog_identity nodejs npm nvm)" || return 2
	source_checkout="$(dotfiles_catalog_source_install nvm)" || return $?
	if [[ "${DOTFILES_FORCE_REINSTALL:-0}" != 1 ]] && dotfiles_catalog_native_owned nodejs && dotfiles_catalog_native_owned npm; then
		mapfile -t old_proof <"$HOME/.local/share/dotfiles-catalog/nodejs.native"
		if [[ "${old_proof[6]}" == "$identity" ]] &&
			dotfiles_catalog_version_matches "$prefix/bin/node" "$node_version" --version &&
			dotfiles_catalog_version_matches "$prefix/bin/npm" "$npm_version" --version &&
			dotfiles_catalog_version_matches "$prefix/bin/npx" "$npm_version" --version; then
			if [[ ! -e "$HOME/.local/bin/npx" && ! -L "$HOME/.local/bin/npx" ]]; then
				ln -s -- "$prefix/bin/npx" "$HOME/.local/bin/npx" || return 1
			fi
			return 0
		fi
	fi
	[[ -f "$source_checkout/nvm.sh" && ! -L "$source_checkout/nvm.sh" ]] || return 2
	mkdir -p -- "$root/versions/node" "$root/alias" "$HOME/.local/bin" "$HOME/.local/share/dotfiles-catalog" || return 1
	[[ ! -L "$root/alias" && ! -L "$root/alias/default" ]] || return 2
	stage="$(mktemp -d "$root/versions/node/.catalog-node-XXXXXX")" || return 1
	paths=("$HOME/.local/bin/node" "$HOME/.local/bin/npm" "$HOME/.local/bin/npx"
		"$HOME/.local/share/dotfiles-catalog/nodejs.native" "$HOME/.local/share/dotfiles-catalog/npm.native"
		"$root/alias/default" "$root/nvm.sh")
	# shellcheck disable=SC2317,SC2329  # Invoked by this transaction's EXIT trap.
	_dotfiles_catalog_node_cleanup() {
		local status=$? rollback_failed=0
		if [[ "$committed" == 0 ]]; then
			if [[ "$prefix_published" == 1 ]]; then rm -rf -- "$prefix" || rollback_failed=1; fi
			if [[ "$prefix_backed_up" == 1 ]]; then mv -- "$stage/previous-prefix" "$prefix" || rollback_failed=1; fi
			for index in "${!paths[@]}"; do
				[[ "${changed[index]:-0}" == 1 ]] || continue
				if [[ -e "$stage/backup-$index" || -L "$stage/backup-$index" ]]; then
					mv -Tf -- "$stage/backup-$index" "${paths[index]}" || rollback_failed=1
				else rm -f -- "${paths[index]}" || rollback_failed=1; fi
			done
		fi
		if [[ "$rollback_failed" == 1 ]]; then
			keep_stage=1
			printf 'Native Node rollback needs recovery; originals retained at %s.\n' "$stage" >&2
		fi
		[[ "$keep_stage" == 1 ]] || rm -rf -- "$stage"
		return "$status"
	}
	trap '_dotfiles_catalog_node_cleanup' EXIT
	dotfiles_catalog_download nodejs "$stage/node-archive" || return $?
	dotfiles_catalog_download npm "$stage/npm-archive" || return $?
	mkdir "$stage/node-validated" "$stage/npm-validated" "$stage/nvm" || return 1
	dotfiles_catalog_extract "$archive" "$stage/node-archive" "$stage/node-validated" || return $?
	dotfiles_catalog_extract "$npm_archive" "$stage/npm-archive" "$stage/npm-validated" || return $?
	[[ -f "$stage/node-validated/$binary" ]] || return 2
	dotfiles_catalog_npm_payload "$stage/npm-validated" "$npm_version" || return 2
	# The pinned NVM extractor operates only on this isolated staging root.
	local NVM_DIR="$stage/nvm"
	export NVM_DIR
	# shellcheck source=/dev/null
	source "$source_checkout/nvm.sh" --no-use || return $?
	[[ "$(nvm --version)" == "$nvm_version" ]] || return 2
	compression="$(nvm_get_artifact_compression "$node_version")" || return 2
	native_archive="$stage/native.$compression"
	if [[ "$archive" == "$compression" || ("$archive" == tgz && "$compression" == tar.gz) ]]; then
		ln -- "$stage/node-archive" "$native_archive" || return 1
	else
		case "$compression" in
		tar.gz) tar -czf "$native_archive" -C "$stage/node-validated" "${binary%%/*}" || return $? ;;
		tar.xz) tar -cJf "$native_archive" -C "$stage/node-validated" "${binary%%/*}" || return $? ;;
		*) return 2 ;;
		esac
	fi
	nvm_install_binary_extract linux "v$node_version" "$node_version" "$native_archive" "$stage/nvm-extracted" >"$stage/nvm.log" 2>&1 || return $?
	candidate="$NVM_DIR/versions/node/v$node_version"
	[[ -d "$candidate" && ! -L "$candidate" && -f "$candidate/bin/node" ]] || return 2
	mkdir -p "$candidate/lib/node_modules" || return 1
	rm -rf -- "$candidate/lib/node_modules/npm" || return 1
	cp -a -- "$stage/npm-validated/package" "$candidate/lib/node_modules/npm" || return 1
	chmod u+x "$candidate/lib/node_modules/npm/bin/npm-cli.js" "$candidate/lib/node_modules/npm/bin/npx-cli.js" || return 1
	ln -sfn ../lib/node_modules/npm/bin/npm-cli.js "$candidate/bin/npm" || return 1
	ln -sfn ../lib/node_modules/npm/bin/npx-cli.js "$candidate/bin/npx" || return 1
	dotfiles_catalog_version_matches "$candidate/bin/node" "$node_version" --version || return 2
	PATH="$candidate/bin:$PATH" dotfiles_catalog_version_matches "$candidate/bin/npm" "$npm_version" --version || return 2
	PATH="$candidate/bin:$PATH" dotfiles_catalog_version_matches "$candidate/bin/npx" "$npm_version" --version || return 2
	if [[ -n "$previous_prefix" ]]; then
		local preserved
		for preserved in "$previous_prefix/lib/node_modules/"* "$previous_prefix/lib/node_modules/".[!.]* "$previous_prefix/lib/node_modules/"..?*; do
			[[ -e "$preserved" || -L "$preserved" ]] || continue
			[[ "${preserved##*/}" != npm ]] || continue
			cp -a -- "$preserved" "$candidate/lib/node_modules/" || return 1
		done
		for preserved in "$previous_prefix/bin/"*; do
			[[ -e "$preserved" || -L "$preserved" ]] || continue
			[[ ! -e "$candidate/bin/${preserved##*/}" && ! -L "$candidate/bin/${preserved##*/}" ]] || continue
			cp -a -- "$preserved" "$candidate/bin/" || return 1
		done
		[[ ! -d "$previous_prefix/etc" ]] || cp -a -- "$previous_prefix/etc" "$candidate/" || return 1
	fi
	for binary in node npm npx; do ln -s -- "$prefix/bin/$binary" "$stage/public-$binary" || return 1; done
	_dotfiles_catalog_runtime_receipt "$stage/nodejs.native" nvm "$node_version" "$prefix" "$identity" || return 1
	_dotfiles_catalog_runtime_receipt "$stage/npm.native" nvm "$npm_version" "$prefix" "$identity" || return 1
	printf 'v%s\n' "$node_version" >"$stage/default"
	ln -s -- "$(dotfiles_catalog_root nvm)/current/nvm.sh" "$stage/nvm.sh" || return 1
	prepared=("$stage/public-node" "$stage/public-npm" "$stage/public-npx" "$stage/nodejs.native" "$stage/npm.native" "$stage/default" "$stage/nvm.sh")
	for index in "${!paths[@]}"; do
		if [[ -e "${paths[index]}" || -L "${paths[index]}" ]]; then cp -a -- "${paths[index]}" "$stage/backup-$index" || return 1; fi
	done
	if [[ -e "$prefix" ]]; then
		mv -- "$prefix" "$stage/previous-prefix" || return $?
		prefix_backed_up=1
	fi
	mv -- "$candidate" "$prefix" || return $?
	prefix_published=1
	for index in "${!paths[@]}"; do
		mv -Tf -- "${prepared[index]}" "${paths[index]}" || return $?
		changed[index]=1
	done
	NVM_DIR="$root"
	export NVM_DIR
	nvm alias default "v$node_version" >"$stage/default.log" 2>&1 || rc=$?
	((rc == 0)) || return "$rc"
	PATH="$prefix/bin:$PATH" dotfiles_catalog_version_matches "$prefix/bin/node" "$node_version" --version || return 2
	PATH="$prefix/bin:$PATH" dotfiles_catalog_version_matches "$prefix/bin/npm" "$npm_version" --version || return 2
	dotfiles_catalog_native_owned nodejs && dotfiles_catalog_native_owned npm || return 2
	committed=1
)

dotfiles_catalog_go_install() (
	# shellcheck disable=SC2034  # Holds the transaction descriptor until this subshell exits.
	local lock_fd
	dotfiles_catalog_transaction_lock go lock_fd || return $?
	dotfiles_catalog_begin || return $?
	local version archive identity root install_root prefix source_checkout stage asdf_binary program name index
	local committed=0 prefix_published=0 prefix_backed_up=0 keep_stage=0
	local -a paths=() prepared=() changed=() old_proof=()
	[[ "$(dotfiles_catalog_get go owner)" == dotfiles && "$(dotfiles_catalog_get asdf-golang kind)" == git-source ]] || return 2
	version="$(dotfiles_catalog_get go version)" || return 2
	archive="$(dotfiles_catalog_get go archive)" || return 2
	[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$(dotfiles_catalog_get go binary)" == go/bin/go ]] || return 2
	case "$archive" in tar.gz | tgz) ;; *) return 2 ;; esac
	if dotfiles_catalog_external go; then
		printf 'Preserving external Go; native catalog activation is blocked.\n' >&2
		return 2
	fi
	if dotfiles_catalog_managed go && ! dotfiles_catalog_version_matches "$HOME/.local/bin/go" "$version" version GOTOOLCHAIN local &&
		! dotfiles_catalog_upgrade_allowed "$HOME/.local/bin/go" "$version" version GOTOOLCHAIN local; then return 2; fi
	root="${ASDF_DATA_DIR:-$HOME/.asdf}"
	install_root="$root/installs/golang/$version"
	prefix="$install_root/go"
	[[ "$root" == /* && ! -L "$root" && ! -L "$root/installs" && ! -L "$root/installs/golang" && ! -L "$root/plugins" && ! -L "$root/shims" && ! -L "$HOME/.tool-versions" ]] || return 2
	if [[ -e "$root/bin/asdf" || -L "$root/bin/asdf" ]]; then
		[[ -L "$root/bin/asdf" && "$(readlink -- "$root/bin/asdf")" == "$HOME/.local/bin/asdf" ]] || return 2
		dotfiles_catalog_owned asdf || return 2
	fi
	if [[ -e "$root/plugins/golang" || -L "$root/plugins/golang" ]]; then
		[[ -d "$root/plugins/golang" && ! -L "$root/plugins/golang" ]] || return 2
		dotfiles_catalog_source_checkout_owned asdf-golang "$root/plugins/golang" || return 2
	fi
	if [[ -e "$install_root" || -L "$install_root" ]]; then
		dotfiles_catalog_native_owned go || return 2
		mapfile -t old_proof <"$HOME/.local/share/dotfiles-catalog/go.native"
		[[ "${old_proof[5]}" == "$prefix" ]] || return 2
	fi
	dotfiles_catalog_install asdf || return $?
	dotfiles_catalog_owned asdf || return 2
	asdf_binary="$HOME/.local/bin/asdf"
	source_checkout="$(dotfiles_catalog_source_install asdf-golang)" || return $?
	dotfiles_catalog_source_checkout_owned asdf-golang "$source_checkout" || return 2
	identity="$(dotfiles_catalog_identity go asdf asdf-golang)" || return 2
	if [[ "${DOTFILES_FORCE_REINSTALL:-0}" != 1 ]] && dotfiles_catalog_native_owned go; then
		mapfile -t old_proof <"$HOME/.local/share/dotfiles-catalog/go.native"
		if [[ "${old_proof[6]}" == "$identity" ]] && dotfiles_catalog_native_go_shim_owned "$root/shims/go" &&
			dotfiles_catalog_version_matches "$HOME/.local/bin/go" "$version" version GOTOOLCHAIN local; then return 0; fi
	fi
	[[ -x "$source_checkout/bin/install" && ! -L "$source_checkout/bin/install" ]] || return 2
	mkdir -p -- "$root/installs/golang" "$root/plugins" "$root/bin" "$root/shims" "$HOME/.local/bin" "$HOME/.local/share/dotfiles-catalog" || return 1
	stage="$(mktemp -d "$root/installs/golang/.catalog-go-XXXXXX")" || return 1
	paths=("$HOME/.local/bin/go" "$HOME/.local/share/dotfiles-catalog/go.native" "$HOME/.local/share/dotfiles-catalog/go.command"
		"$root/plugins/golang" "$root/bin/asdf" "$HOME/.tool-versions" "$HOME/.local/share/dotfiles-catalog/go.shims")
	# shellcheck disable=SC2317,SC2329  # Invoked by this transaction's EXIT trap.
	_dotfiles_catalog_go_cleanup() {
		local status=$? rollback_failed=0
		if [[ "$committed" == 0 ]]; then
			if [[ "$prefix_published" == 1 ]]; then rm -rf -- "$install_root" || rollback_failed=1; fi
			if [[ "$prefix_backed_up" == 1 ]]; then mv -- "$stage/previous-prefix" "$install_root" || rollback_failed=1; fi
			for index in "${!paths[@]}"; do
				[[ "${changed[index]:-0}" == 1 ]] || continue
				if [[ "${paths[index]}" == "$root/plugins/golang" ]]; then
					rm -rf -- "${paths[index]}" || rollback_failed=1
				fi
				if [[ -e "$stage/backup-$index" || -L "$stage/backup-$index" ]]; then
					mv -Tf -- "$stage/backup-$index" "${paths[index]}" || rollback_failed=1
				else rm -f -- "${paths[index]}" || rollback_failed=1; fi
			done
		fi
		if [[ "$rollback_failed" == 1 ]]; then
			keep_stage=1
			printf 'Native Go rollback needs recovery; originals retained at %s.\n' "$stage" >&2
		fi
		[[ "$keep_stage" == 1 ]] || rm -rf -- "$stage"
		return "$status"
	}
	trap '_dotfiles_catalog_go_cleanup' EXIT
	mkdir "$stage/download" "$stage/validated" "$stage/install" || return 1
	dotfiles_catalog_download go "$stage/download/archive.tar.gz" || return $?
	dotfiles_catalog_extract "$archive" "$stage/download/archive.tar.gz" "$stage/validated" || return $?
	env GOTOOLCHAIN=local ASDF_GOLANG_DEFAULT_PACKAGES_FILE=/dev/null ASDF_INSTALL_VERSION="$version" \
		ASDF_DOWNLOAD_PATH="$stage/download" ASDF_INSTALL_PATH="$stage/install" \
		"$source_checkout/bin/install" >"$stage/import.log" 2>&1 || return $?
	dotfiles_catalog_go_defaults "$stage/install/go/bin/go" "$stage/install" || return 2
	dotfiles_catalog_version_matches "$stage/install/go/bin/go" "$version" version GOTOOLCHAIN local || return 2
	if [[ -d "$install_root" ]]; then
		for program in "$install_root/"* "$install_root/".[!.]* "$install_root/"..?*; do
			[[ -e "$program" || -L "$program" ]] || continue
			[[ "${program##*/}" != go ]] || continue
			cp -a -- "$program" "$stage/install/" || return 1
		done
	fi
	cp -a -- "$source_checkout" "$stage/plugin" || return 1
	ln -s -- "$HOME/.local/share/dotfiles-catalog/go.command" "$stage/public-go" || return 1
	_dotfiles_catalog_runtime_receipt "$stage/go.native" asdf "$version" "$prefix" "$identity" || return 1
	dotfiles_catalog_native_go_command "$prefix" >"$stage/go.command" || return 1
	chmod 0755 "$stage/go.command" || return 1
	ln -s -- "$asdf_binary" "$stage/asdf" || return 1
	if [[ -e "$HOME/.tool-versions" ]]; then cp -a -- "$HOME/.tool-versions" "$stage/tool-versions" || return 1; else : >"$stage/tool-versions"; fi
	: >"$stage/go.shims"
	prepared=("$stage/public-go" "$stage/go.native" "$stage/go.command" "$stage/plugin" "$stage/asdf" "$stage/tool-versions" "$stage/go.shims")
	for program in "$stage/install/go/bin/"* "$stage/install/bin/"*; do
		[[ -f "$program" && -x "$program" ]] || continue
		name="${program##*/}"
		[[ "$name" =~ ^[A-Za-z0-9_.+-]+$ ]] || return 2
		paths+=("$root/shims/$name")
		prepared+=('')
	done
	for index in "${!paths[@]}"; do
		if [[ -e "${paths[index]}" || -L "${paths[index]}" ]]; then cp -a -- "${paths[index]}" "$stage/backup-$index" || return 1; fi
	done
	if [[ -e "$install_root" ]]; then
		mv -- "$install_root" "$stage/previous-prefix" || return $?
		prefix_backed_up=1
	fi
	mv -- "$stage/install" "$install_root" || return $?
	prefix_published=1
	for index in "${!paths[@]}"; do
		if [[ -n "${prepared[index]}" ]]; then
			if [[ "${paths[index]}" == "$root/plugins/golang" && -e "${paths[index]}" ]]; then
				mv -- "${paths[index]}" "$stage/previous-plugin" || return $?
				changed[index]=1
			fi
			mv -Tf -- "${prepared[index]}" "${paths[index]}" || return $?
		fi
		changed[index]=1
	done
	export ASDF_DATA_DIR="$root"
	GOTOOLCHAIN=local "$asdf_binary" set -u golang "$version" >"$stage/select.log" 2>&1 || return $?
	GOTOOLCHAIN=local "$asdf_binary" reshim golang "$version" >"$stage/reshim.log" 2>&1 || return $?
	: >"$stage/shim-records"
	for program in "$prefix/bin/"* "$install_root/bin/"*; do
		[[ -f "$program" && -x "$program" ]] || continue
		name="${program##*/}"
		[[ "$name" =~ ^[A-Za-z0-9_.+-]+$ ]] || return 2
		_dotfiles_catalog_go_control_shim "$root/shims/$name" || return 2
		local shim_digest
		shim_digest="$(sha256sum -- "$root/shims/$name")" || return 2
		printf '%s\t%s\n' "$name" "${shim_digest%% *}" >>"$stage/shim-records"
	done
	mv -Tf -- "$stage/shim-records" "$HOME/.local/share/dotfiles-catalog/go.shims" || return $?
	dotfiles_catalog_native_owned go || return 2
	dotfiles_catalog_version_matches "$HOME/.local/bin/go" "$version" version GOTOOLCHAIN local || return 2
	committed=1
)

_dotfiles_catalog_go_control_shim() {
	python3 - "$1" <<'PYSHIM'
import os,pathlib,stat,sys,tempfile
path=pathlib.Path(sys.argv[1])
if path.is_symlink() or not path.is_file() or path.stat().st_uid!=os.getuid() or path.stat().st_size>65536:
    raise SystemExit("Cannot verify generated Go shim")
lines=path.read_text().splitlines(keepends=True)
if not lines or not lines[0].startswith('#!'): raise SystemExit("Generated Go shim has no interpreter")
control='export GOTOOLCHAIN=local\n'
text=lines[0]+control+''.join(line for line in lines[1:] if line!=control)
fd,name=tempfile.mkstemp(prefix='.catalog-go-shim-',dir=path.parent)
try:
    with os.fdopen(fd,'w') as stream: stream.write(text)
    os.chmod(name,stat.S_IMODE(path.stat().st_mode))
    os.replace(name,path)
finally:
    pathlib.Path(name).unlink(missing_ok=True)
PYSHIM
}
