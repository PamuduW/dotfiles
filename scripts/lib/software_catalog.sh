# shellcheck shell=bash
# Exact software adapters. Discovery helpers remain separate from these routes.

_DOTFILES_CATALOG_LIB="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=scripts/lib/catalog_state.sh
source "$_DOTFILES_CATALOG_LIB/catalog_state.sh"
# shellcheck source=scripts/lib/shared_resolve.sh
source "$_DOTFILES_CATALOG_LIB/shared_resolve.sh"
dotfiles_shared_resolve "$(cd -- "$_DOTFILES_CATALOG_LIB/../.." && pwd)" || return 1
# shellcheck source=/dev/null
source "$DOTFILES_SHARED_LIB/software_catalog.sh"
if ! declare -F github_curl >/dev/null; then
	# shellcheck source=scripts/lib/github_api.sh
	source "$_DOTFILES_CATALOG_LIB/github_api.sh"
fi

_DOTFILES_CATALOG_OPERATION_PID=''
_DOTFILES_CATALOG_OPERATION_SNAPSHOT=''
_DOTFILES_CATALOG_OPERATION_JSON=''
_DOTFILES_CATALOG_OPERATION_TABLE=''
_DOTFILES_CATALOG_OPERATION_APPROVAL=''
_DOTFILES_CATALOG_OPERATION_REVISION=''
export -n _DOTFILES_CATALOG_OPERATION_PID _DOTFILES_CATALOG_OPERATION_SNAPSHOT \
	_DOTFILES_CATALOG_OPERATION_JSON _DOTFILES_CATALOG_OPERATION_TABLE \
	_DOTFILES_CATALOG_OPERATION_APPROVAL _DOTFILES_CATALOG_OPERATION_REVISION

_dotfiles_catalog_context_digest() {
	if [[ -n "${_SOFTWARE_CATALOG_QUALIFICATION_CONTEXT:-}" ]]; then
		printf '%s\n' "$_SOFTWARE_CATALOG_QUALIFICATION_DIGEST"
	else
		local digest
		digest="$(sha256sum -- "$SOFTWARE_CATALOG_SNAPSHOT/approval.json")" || return 2
		printf '%s\n' "${digest%% *}"
	fi
}

dotfiles_catalog_begin() {
	local approval_digest
	if [[ "$_DOTFILES_CATALOG_OPERATION_PID" == "$BASHPID" ]]; then
		[[ "${SOFTWARE_CATALOG_SNAPSHOT:-}" == "$_DOTFILES_CATALOG_OPERATION_SNAPSHOT" &&
			"${SOFTWARE_CATALOG_REVISION:-}" == "$_DOTFILES_CATALOG_OPERATION_REVISION" ]] || return 2
		if [[ -n "${_SOFTWARE_CATALOG_QUALIFICATION_CONTEXT:-}" ]]; then
			software_catalog_begin "$DOTFILES_SHARED_ROOT" || return 2
		else
			software_catalog_load "$_DOTFILES_CATALOG_OPERATION_SNAPSHOT" || return 2
		fi
		approval_digest="$(_dotfiles_catalog_context_digest)" || return 2
		if [[ "$SOFTWARE_CATALOG_DIGEST" != "$_DOTFILES_CATALOG_OPERATION_JSON" ||
			"$SOFTWARE_CATALOG_TABLE_DIGEST" != "$_DOTFILES_CATALOG_OPERATION_TABLE" ||
			"${approval_digest%% *}" != "$_DOTFILES_CATALOG_OPERATION_APPROVAL" ]]; then
			SOFTWARE_CATALOG_SNAPSHOT=''
			return 2
		fi
	else
		SOFTWARE_CATALOG_SNAPSHOT=''
		SOFTWARE_CATALOG_DIGEST=''
		# shellcheck disable=SC2034  # Read by the shared catalog lookup implementation.
		SOFTWARE_CATALOG_TABLE_DIGEST=''
		software_catalog_begin "$DOTFILES_SHARED_ROOT" || {
			printf '%s\n' 'No approved software snapshot. Software changes are blocked; qualify and approve the shared catalog first.' >&2
			return 2
		}
		approval_digest="$(_dotfiles_catalog_context_digest)" || return 2
		_DOTFILES_CATALOG_OPERATION_PID="$BASHPID"
		_DOTFILES_CATALOG_OPERATION_SNAPSHOT="$SOFTWARE_CATALOG_SNAPSHOT"
		_DOTFILES_CATALOG_OPERATION_JSON="$SOFTWARE_CATALOG_DIGEST"
		_DOTFILES_CATALOG_OPERATION_TABLE="$SOFTWARE_CATALOG_TABLE_DIGEST"
		_DOTFILES_CATALOG_OPERATION_APPROVAL="${approval_digest%% *}"
		_DOTFILES_CATALOG_OPERATION_REVISION="${SOFTWARE_CATALOG_REVISION:-}"
	fi
}

dotfiles_catalog_transaction_lock() {
	local key="$1" destination="$2" root install_lock_fd
	[[ "$key" =~ ^[a-z][a-z0-9_.-]*$ && "$destination" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
	root="$(dotfiles_catalog_root "$key")"
	[[ ! -L "$HOME/.local/share/dotfiles-catalog" && ! -L "$root" && ! -L "$root/install.lock" ]] || return 2
	mkdir -p -- "$root" || return 1
	[[ -O "$root" ]] || return 2
	if [[ -e "$root/install.lock" ]]; then
		[[ -f "$root/install.lock" && -O "$root/install.lock" ]] || return 2
	fi
	exec {install_lock_fd}>>"$root/install.lock" || return 1
	if ! flock -n "$install_lock_fd"; then
		exec {install_lock_fd}>&-
		printf 'Another %s installation is running; retry when it finishes.\n' "$key" >&2
		return 75
	fi
	printf -v "$destination" '%s' "$install_lock_fd"
}

dotfiles_catalog_identity() (
	set -o pipefail
	local key keys='|' digest
	(($# > 0)) || return 2
	dotfiles_catalog_get "$1" owner >/dev/null || return 2
	for key in "$@"; do
		[[ "$key" =~ ^[a-z][a-z0-9_.-]*$ ]] || return 2
		keys+="$key|"
	done
	digest="$(awk -F '\t' -v keys="$keys" 'index(keys, "|" $1 "|") {print}' "$SOFTWARE_CATALOG_SNAPSHOT/software.tsv" | LC_ALL=C sort | sha256sum)" || return 2
	printf '%s\n' "${digest%% *}"
)

dotfiles_catalog_component_identity() {
	local key="$1" archive
	case "$key" in
	nodejs)
		dotfiles_catalog_identity nodejs npm nvm
		return $?
		;;
	go)
		dotfiles_catalog_identity go asdf asdf-golang
		return $?
		;;
	npm) if dotfiles_catalog_native_owned nodejs; then
		dotfiles_catalog_identity nodejs npm nvm
		return $?
	fi ;;
	esac
	archive="$(dotfiles_catalog_get "$key" archive)" || return 2
	case "$archive" in
	npm-lock) dotfiles_catalog_identity "$key" nodejs npm nvm ;;
	python-lock) dotfiles_catalog_identity "$key" uv ;;
	*) dotfiles_catalog_identity "$key" ;;
	esac
}

dotfiles_catalog_installed_identity() {
	local key="$1" receipt value size
	if dotfiles_catalog_native_owned "$key"; then
		local -a proof=()
		mapfile -t proof <"$HOME/.local/share/dotfiles-catalog/$key.native" || return 1
		[[ "${#proof[@]}" == 7 ]] || return 1
		printf '%s\n' "${proof[6]}"
		return
	fi
	receipt="$(dotfiles_catalog_root "$key")/current/.catalog-target"
	[[ -f "$receipt" && ! -L "$receipt" && -O "$receipt" ]] || return 1
	size="$(stat -c %s -- "$receipt")" || return 1
	[[ "$size" == 64 || "$size" == 65 ]] || return 1
	value="$(cat "$receipt")" || return 1
	[[ "$value" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "$value"
}

dotfiles_catalog_target() {
	[[ "$(uname -s)" == Linux ]] || return 2
	case "$(uname -m)" in
	x86_64 | amd64)
		if [[ "$(uname -r)" == *[Mm]icrosoft* ]]; then echo wsl2-amd64; else echo linux-amd64; fi
		;;
	aarch64 | arm64) echo linux-arm64 ;;
	*) return 2 ;;
	esac
}

dotfiles_catalog_get() {
	local target
	target="$(dotfiles_catalog_target)" || return 2
	software_catalog_get "$1" "$2" "$target"
}

dotfiles_catalog_external() {
	local key="$1" command_name active root
	command_name="$(dotfiles_catalog_command_name "$key")"
	root="$(dotfiles_catalog_root "$key")"
	active="$(command -v "$command_name" 2>/dev/null || true)"
	if [[ -n "$active" && "$active" != "$HOME/.local/bin/$command_name" ]]; then
		if ! dotfiles_catalog_owned "$key" || [[ "$(realpath -- "$active" 2>/dev/null)" != "$(realpath -- "$HOME/.local/bin/$command_name" 2>/dev/null)" ]]; then
			if [[ "$key" != go ]] || ! dotfiles_catalog_native_owned go ||
				! dotfiles_catalog_native_go_shim_owned "$active" || ! dotfiles_catalog_owned asdf; then return 0; fi
			if ! declare -F dotfiles_catalog_source_checkout_owned >/dev/null; then
				# shellcheck source=/dev/null
				source "$_DOTFILES_CATALOG_LIB/catalog_sources.sh"
			fi
			dotfiles_catalog_source_checkout_owned asdf-golang "${ASDF_DATA_DIR:-$HOME/.asdf}/plugins/golang" || return 0
			local selected
			local -a native_proof=()
			mapfile -t native_proof <"$HOME/.local/share/dotfiles-catalog/go.native" || return 0
			[[ "${#native_proof[@]}" == 7 ]] || return 0
			selected="$(ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}" "$HOME/.local/bin/asdf" which go 2>/dev/null)" || return 0
			[[ "$(realpath -- "$selected" 2>/dev/null)" == "${native_proof[5]}/bin/go" ]] || return 0
		fi
	fi
	if [[ -e "$HOME/.local/bin/$command_name" || -L "$HOME/.local/bin/$command_name" ]]; then
		dotfiles_catalog_managed "$key" || return 0
	fi
	# Never adopt an existing directory based solely on its pathname.
	[[ -e "$root/current" && ! -f "$root/current/.catalog-receipt" ]]
}

dotfiles_catalog_verify() {
	local file="$1" expected="$2" actual
	case "$expected" in
	sha256:*)
		[[ "$expected" =~ ^sha256:[0-9a-f]{64}$ ]] || return 2
		actual="$(sha256sum -- "$file")"
		;;
	sha512:*)
		[[ "$expected" =~ ^sha512:[0-9a-f]{128}$ ]] || return 2
		actual="$(sha512sum -- "$file")"
		;;
	*) return 2 ;;
	esac
	[[ "${actual%% *}" == "${expected#*:}" ]] || {
		printf 'Catalog digest mismatch: preserving the installed software.\n' >&2
		return 2
	}
}

dotfiles_catalog_download() {
	local key="$1" destination="$2" url digest
	local -a request=(-fsSL)
	url="$(dotfiles_catalog_get "$key" url)" || return 2
	digest="$(dotfiles_catalog_get "$key" digest)" || return 2
	[[ "$url" == https://* ]] || return 2
	if [[ "$key" == direnv ]]; then
		request+=(--proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 180
			--retry 2 --retry-all-errors --retry-delay 1 --retry-max-time 180)
	fi
	case "$url" in
	https://github.com/* | https://api.github.com/*)
		github_curl "${request[@]}" -o "$destination" "$url" || return $?
		;;
	*) curl "${request[@]}" --proto '=https' --tlsv1.2 -o "$destination" "$url" || return $? ;;
	esac
	dotfiles_catalog_verify "$destination" "$digest"
}

# Extract only regular files, directories and bounded internal symlinks.
# Reject duplicate members and paths through symlinks before writing anything.
dotfiles_catalog_extract() {
	python3 - "$@" <<'PY'
import os,pathlib,shutil,stat,sys,tarfile,zipfile
kind,source,destination=sys.argv[1:]
root=pathlib.Path(destination)
def name_ok(name):
    p=pathlib.PurePosixPath(name)
    drive=len(name)>1 and name[0].isalpha() and name[1]==':'
    return bool(name) and not drive and not p.is_absolute() and '..' not in p.parts and '\\' not in name and not any(ord(c)<32 for c in name)
def check(entries):
    seen=set(); links=set()
    for name,link in entries:
        if not name_ok(name) or name in seen: raise ValueError('unsafe or duplicate archive member')
        seen.add(name)
        if link is not None:
            if link.startswith('/') or not name_ok(os.path.normpath(str(pathlib.PurePosixPath(name).parent/link))): raise ValueError('escaping archive symlink')
            links.add(name)
    for name in seen:
        if any(str(p) in links for p in pathlib.PurePosixPath(name).parents): raise ValueError('archive member traverses symlink')
if kind in ('tar','tar.gz','tar.xz','tgz'):
    with tarfile.open(source) as archive:
        members=archive.getmembers()
        if not members or any(not(m.isfile() or m.isdir() or m.issym()) for m in members): raise ValueError('unsupported archive entry')
        check([(m.name,m.linkname if m.issym() else None) for m in members])
        for m in members:
            target=root/m.name
            if m.isdir(): target.mkdir(parents=True,exist_ok=True)
            elif m.isfile():
                target.parent.mkdir(parents=True,exist_ok=True)
                with archive.extractfile(m) as src,target.open('wb') as dst: shutil.copyfileobj(src,dst)
                target.chmod(m.mode & 0o777)
        for m in members:
            if m.issym():
                target=root/m.name; target.parent.mkdir(parents=True,exist_ok=True);target.symlink_to(m.linkname)
elif kind=='zip':
    with zipfile.ZipFile(source) as archive:
        members=archive.infolist()
        if not members or any(stat.S_IFMT(m.external_attr>>16) not in (0,stat.S_IFREG,stat.S_IFDIR) for m in members): raise ValueError('unsupported zip entry')
        check([(m.filename.rstrip('/'),None) for m in members])
        for m in members:
            target=root/m.filename
            if m.is_dir(): target.mkdir(parents=True,exist_ok=True)
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                with archive.open(m) as src,target.open('wb') as dst: shutil.copyfileobj(src,dst)
                target.chmod((m.external_attr>>16)&0o777 or 0o644)
else: raise ValueError('unsupported catalog archive format')
PY
}

dotfiles_catalog_version_matches() {
	local command_path="$1" version="$2" version_arg="${3:---version}" raw
	local env_name="${4:-}" env_value="${5:-}"
	local -a argv=()
	read -r -a argv <<<"$version_arg"
	if [[ -n "$env_name" ]]; then
		[[ "$env_name" =~ ^[A-Z][A-Z0-9_]*$ && "$env_value" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
		raw="$(env "$env_name=$env_value" "$command_path" "${argv[@]}" 2>/dev/null)" || return 1
	else
		raw="$("$command_path" "${argv[@]}" 2>/dev/null)" || return 1
	fi
	python3 - "$version" "$raw" <<'PY'
import re,sys
version=sys.argv[1].removeprefix('v')
raise SystemExit(not bool(re.search(r'(?<![0-9A-Za-z.+-])(?:go|v)?'+re.escape(version)+r'(?![0-9A-Za-z.+-])',sys.argv[2])))
PY
}

dotfiles_catalog_upgrade_allowed() {
	local command_path="$1" expected="$2" version_arg="$3" raw
	local env_name="${4:-}" env_value="${5:-}"
	local -a argv=()
	read -r -a argv <<<"$version_arg"
	if [[ -n "$env_name" ]]; then
		[[ "$env_name" =~ ^[A-Z][A-Z0-9_]*$ && "$env_value" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
		raw="$(env "$env_name=$env_value" "$command_path" "${argv[@]}" 2>/dev/null)" || return 1
	else
		raw="$("$command_path" "${argv[@]}" 2>/dev/null)" || return 1
	fi
	dotfiles_catalog_version_is_older "$raw" "$expected"
}

dotfiles_catalog_version_is_older() {
	python3 - "$2" "$1" <<'PY'
import re,sys
expected=sys.argv[1].removeprefix('v')
pattern=r'(?<![0-9A-Za-z])(?:go|v)?([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)'
found=re.search(pattern,sys.argv[2])
if not found or not re.fullmatch(r'[0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?',expected):
    raise SystemExit(1)
def core(version):
    return tuple(map(int,re.split(r'[-+]',version,maxsplit=1)[0].split('.')))
raise SystemExit(not(core(found[1]) < core(expected)))
PY
}

dotfiles_catalog_go_defaults() {
	python3 - "$1" "$2" <<'PYGO'
import pathlib,sys
binary=pathlib.Path(sys.argv[1]); payload=pathlib.Path(sys.argv[2]).resolve()
if binary.name!='go' or binary.parent.name!='bin': raise SystemExit('Go requires its complete SDK layout')
config=binary.parent.parent/'go.env'
if not config.is_file() or config.is_symlink() or config.stat().st_size>65536 or not config.resolve().is_relative_to(payload):
    raise SystemExit('Go SDK environment defaults cannot be verified')
lines=[line for line in config.read_text().splitlines(keepends=True) if not line.startswith('GOTOOLCHAIN=')]
text=''.join(lines)
config.chmod(config.stat().st_mode | 0o200)
config.write_text(text+('' if not text or text.endswith('\n') else '\n')+'GOTOOLCHAIN=local\n')
PYGO
}

dotfiles_catalog_npm_preflight() {
	local field active root
	for field in version url digest; do
		dotfiles_catalog_get npm "$field" >/dev/null || return 2
	done
	[[ "$(dotfiles_catalog_get npm owner)" == dotfiles &&
	"$(dotfiles_catalog_get npm archive)" =~ ^(tar|tar.gz|tgz)$ &&
	"$(dotfiles_catalog_get npm binary)" == package/bin/npm-cli.js ]] || return 2
	root="$(dotfiles_catalog_root npm)"
	active="$(command -v npx 2>/dev/null || true)"
	if [[ -n "$active" && "$active" != "$HOME/.local/bin/npx" ]]; then
		printf 'Preserving external npx; approved npm activation is blocked.\n' >&2
		return 2
	fi
	if [[ -e "$HOME/.local/bin/npx" || -L "$HOME/.local/bin/npx" ]]; then
		[[ -f "$root/current/.catalog-receipt" && -L "$HOME/.local/bin/npx" &&
			"$(readlink -- "$HOME/.local/bin/npx")" == "$root/current/command-npx" ]] || return 2
	fi
}

dotfiles_catalog_chrome_layout() {
	python3 - "$1" "$2" <<'PYCHROME'
import pathlib,sys
root=pathlib.Path(sys.argv[1]); binary=pathlib.PurePosixPath(sys.argv[2])
if len(binary.parts)!=2 or binary.name!='chrome-headless-shell':
    raise SystemExit('Chrome requires the complete headless-shell bundle')
entries=list(root.iterdir())
if len(entries)!=1 or entries[0].name!=binary.parts[0] or not entries[0].is_dir() or entries[0].is_symlink():
    raise SystemExit('Chrome archive contains files outside the approved build directory')
PYCHROME
}

dotfiles_catalog_codex_defaults() {
	python3 - "${CODEX_HOME:-$HOME/.codex}/app-server-daemon/settings.json" "${1:-apply}" <<'PYCODEX'
import json,os,pathlib,stat,sys,tempfile
path=pathlib.Path(sys.argv[1])
mode_action=sys.argv[2]
if mode_action not in ('apply','check'): raise SystemExit('invalid updater settings operation')
if any(p.is_symlink() for p in (path,*path.parents)):
    raise SystemExit('Codex updater settings must not traverse symlinks')
raw=None; mode=0o600
if path.exists():
    if not path.is_file() or path.stat().st_uid!=os.getuid() or path.stat().st_size>1048576:
        raise SystemExit('Codex updater settings cannot be safely updated')
    raw=path.read_bytes(); mode=stat.S_IMODE(path.stat().st_mode)
try:
    data=json.loads(raw) if raw is not None else {}
except (ValueError,UnicodeError):
    raise SystemExit('Codex updater settings contain invalid JSON; preserving them')
if not isinstance(data,dict) or not isinstance(data.get('updater',{}),dict):
    raise SystemExit('Codex updater settings have an invalid schema; preserving them')
updater=data.setdefault('updater',{})
features=data.get('featureOverrides',{})
def integer(value,low,high):
    return type(value) is int and low<=value<=high
if (type(data.get('remoteControlEnabled',False)) is not bool or
    not isinstance(features,dict) or any(type(value) is not bool for value in features.values()) or
    not integer(data.get('shutdownGraceSeconds',60),0,300) or
    not integer(updater.get('updateIntervalMinutes',60),1,4294967295)):
    raise SystemExit('Codex updater settings have an invalid schema; preserving them')
if updater.get('autoUpdateEnabled') is False:
    raise SystemExit(0)
if mode_action=='check': raise SystemExit(1)
updater['autoUpdateEnabled']=False
path.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
fd,name=tempfile.mkstemp(prefix='.settings.catalog-',dir=path.parent)
try:
    with os.fdopen(fd,'w') as stream:
        os.fchmod(stream.fileno(),mode)
        json.dump(data,stream,indent=2); stream.write('\n')
    current=path.read_bytes() if path.exists() else None
    if current!=raw:
        raise SystemExit('Codex updater settings changed concurrently; preserving them')
    os.replace(name,path)
finally:
    if os.path.exists(name): os.unlink(name)
PYCODEX
}

dotfiles_catalog_codex_layout() {
	local payload="$1" version="$2" binary="$3" arch
	case "$(uname -m)" in
	x86_64 | amd64) arch=x86_64 ;;
	aarch64 | arm64) arch=aarch64 ;;
	*) return 2 ;;
	esac
	python3 - "$payload" "$version" "$binary" "$arch-unknown-linux-musl" <<'PYCODEX'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]).resolve(); version,binary,target=sys.argv[2:]
if binary!='bin/codex': raise SystemExit('Codex requires its complete package layout')
for name in ('codex-package.json','bin/codex','bin/codex-code-mode-host','codex-path/rg','codex-resources/bwrap'):
    path=root/name
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root):
        raise SystemExit('Codex package is missing a required helper or resource')
metadata=json.loads((root/'codex-package.json').read_text())
if (metadata.get('version'),metadata.get('target'),metadata.get('entrypoint'))!=(version,target,binary):
    raise SystemExit('Codex package metadata does not match the approved target')
for name in ('bin/codex','bin/codex-code-mode-host','codex-path/rg','codex-resources/bwrap'):
    path=root/name; path.chmod(path.stat().st_mode|0o100)
PYCODEX
}

dotfiles_catalog_npm_payload() {
	local payload="$1" version="$2"
	python3 - "$payload/package" "$version" <<'PYNPM'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); package=json.loads((root/'package.json').read_text())
if package.get('name')!='npm' or package.get('version')!=sys.argv[2]:
    raise SystemExit('npm archive identity/version mismatch')
dependencies=package.get('dependencies',{})
bundled=package.get('bundleDependencies',package.get('bundledDependencies',[]))
if bundled is not True and (not isinstance(bundled,list) or not set(dependencies)<=set(bundled)):
    raise SystemExit('npm archive does not declare its complete bundled closure')
for name in dependencies:
    if not isinstance(name,str) or any(p in ('..','.') for p in name.split('/')) or name.startswith('/'):
        raise SystemExit('invalid npm dependency name')
    path=root/'node_modules'/name/'package.json'
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise SystemExit('npm archive has a missing bundled dependency')
for name in ('npm-cli.js','npx-cli.js'):
    path=root/'bin'/name
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise SystemExit('npm archive has a missing or escaping command')
PYNPM
}

# No caller gets to specify a version: the approved snapshot selects it.
dotfiles_catalog_install() (
	local key="$1" force="${2:-${DOTFILES_FORCE_REINSTALL:-0}}" prepared_archive="${3:-}" identity root version archive binary staging payload candidate command_name version_arg auto_env auto_value
	dotfiles_catalog_begin || return $?
	if [[ "$(dotfiles_catalog_get "$key" kind)" == external ]]; then
		printf '%s is outside automatic catalog management; install and update it manually.\n' "$key"
		return 0
	fi
	[[ "${SOFTWARE_CATALOG_REVISION:-}" =~ ^[0-9a-f]{40}$ ]] || return 2
	if [[ "$key" == nodejs ]] || { [[ "$key" == npm ]] && dotfiles_catalog_native_owned nodejs; }; then
		if ! declare -F dotfiles_catalog_node_install >/dev/null; then
			# shellcheck source=/dev/null
			source "$_DOTFILES_CATALOG_LIB/catalog_runtimes.sh"
		fi
		DOTFILES_FORCE_REINSTALL="$force" dotfiles_catalog_node_install
		return $?
	fi
	if [[ "$key" == go ]]; then
		if ! declare -F dotfiles_catalog_go_install >/dev/null; then
			# shellcheck source=/dev/null
			source "$_DOTFILES_CATALOG_LIB/catalog_runtimes.sh"
		fi
		DOTFILES_FORCE_REINSTALL="$force" dotfiles_catalog_go_install
		return $?
	fi
	[[ "$(dotfiles_catalog_get "$key" owner)" == dotfiles ]] || return 2
	# shellcheck disable=SC2034  # Holds the descriptor through this transaction.
	local catalog_transaction_fd
	dotfiles_catalog_transaction_lock "$key" catalog_transaction_fd || return $?
	version="$(dotfiles_catalog_get "$key" version)" || {
		printf 'Catalog target blocked or unavailable: %s\n' "$key" >&2
		return 2
	}
	archive="$(dotfiles_catalog_get "$key" archive)" || return 2
	if [[ "$archive" == deb ]]; then
		DOTFILES_FORCE_REINSTALL="$force" dotfiles_catalog_install_debs "$key"
		return $?
	fi
	binary="$(dotfiles_catalog_get "$key" binary)" || return 2
	[[ "$binary" =~ ^[A-Za-z0-9_./-]+$ && "$binary" != /* && "$binary" != *'..'* ]] || return 2
	case "$archive" in
	npm-lock | python-lock)
		[[ "$binary" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 2
		if [[ "$archive" == npm-lock ]]; then binary="node_modules/.bin/$binary"; else binary="bin/$binary"; fi
		;;
	esac
	[[ "$key" != npm ]] || dotfiles_catalog_npm_preflight || return 2
	command_name="$(dotfiles_catalog_command_name "$key")"
	root="$(dotfiles_catalog_root "$key")"
	if dotfiles_catalog_external "$key"; then
		printf 'Preserving external %s installation; catalog ownership is not established.\n' "$key" >&2
		return 0
	fi
	identity="$(dotfiles_catalog_component_identity "$key")" || return 2
	version_arg="$(dotfiles_catalog_version_arg "$key")"
	auto_env="$(dotfiles_catalog_get "$key" discovery.auto_update_env 2>/dev/null || true)"
	auto_value="$(dotfiles_catalog_get "$key" discovery.auto_update_value 2>/dev/null || true)"
	# Vendor controls are verified controls, not guessed names.
	case "$key" in
	go) auto_env=GOTOOLCHAIN auto_value=local ;;
	claude_cli) auto_env=DISABLE_UPDATES auto_value=1 ;;
	antigravity_cli) auto_env=AGY_CLI_DISABLE_AUTO_UPDATE auto_value=true ;;
	cursor_cli)
		printf 'Cursor remains blocked: no verified autonomous-update suppression control.\n' >&2
		return 2
		;;
	esac
	if [[ -n "$auto_env" ]]; then
		[[ "$auto_env" =~ ^[A-Z][A-Z0-9_]*$ && "$auto_value" =~ ^[A-Za-z0-9_-]+$ ]] || return 2
	fi
	[[ "$key" != codex_cli ]] || dotfiles_catalog_codex_defaults || return 2
	if dotfiles_catalog_managed "$key"; then
		if dotfiles_catalog_version_matches "$HOME/.local/bin/$command_name" "$version" "$version_arg" "$auto_env" "$auto_value"; then
			if [[ "$force" != 1 ]] && dotfiles_catalog_owned "$key" &&
				[[ "$(dotfiles_catalog_installed_identity "$key" 2>/dev/null || true)" == "$identity" ]]; then
				if [[ "$key" != npm ]] || dotfiles_catalog_version_matches "$HOME/.local/bin/npx" "$version" --version; then
					return 0
				fi
			fi
		elif ! dotfiles_catalog_upgrade_allowed "$HOME/.local/bin/$command_name" "$version" "$version_arg" "$auto_env" "$auto_value"; then
			printf 'Preserving newer or unverifiable managed %s; review version drift before replacement.\n' "$key" >&2
			return 2
		fi
	fi
	[[ ! -L "$root" ]] || return 2
	mkdir -p -- "$root/releases" "$HOME/.local/bin" || return 1
	staging="$(mktemp -d "$root/releases/.staging-XXXXXX")" || return 1
	local previous_current='' current_published=0 command_published=0 npx_published=0 committed=0
	local current_link="$root/.current.$$" command_link="$HOME/.local/bin/.${command_name}.$$"
	local npx_link="$HOME/.local/bin/.npx.$$"
	if [[ -L "$root/current" ]]; then
		previous_current="$(readlink -- "$root/current")" || return 1
	elif [[ -e "$root/current" ]]; then
		rm -rf -- "$staging"
		return 2
	fi
	# shellcheck disable=SC2317,SC2329  # Invoked by the EXIT trap in this subshell.
	dotfiles_catalog_publication_cleanup() {
		local status=$? rollback_ok=1
		if [[ "$committed" == 0 ]]; then
			if [[ "$current_published" == 1 ]]; then
				if [[ -n "$previous_current" ]]; then
					rm -f -- "$current_link"
					ln -s -- "$previous_current" "$current_link" && mv -Tf -- "$current_link" "$root/current" || rollback_ok=0
				else
					rm -f -- "$root/current" || rollback_ok=0
				fi
			fi
			if [[ "$command_published" == 1 ]]; then
				if [[ -e "$staging/previous-command" || -L "$staging/previous-command" ]]; then
					mv -Tf -- "$staging/previous-command" "$HOME/.local/bin/$command_name" || rollback_ok=0
				else
					rm -f -- "$HOME/.local/bin/$command_name" || rollback_ok=0
				fi
			fi
			if [[ "$npx_published" == 1 ]]; then
				if [[ -L "$staging/previous-npx" ]]; then
					mv -Tf -- "$staging/previous-npx" "$HOME/.local/bin/npx" || rollback_ok=0
				else
					rm -f -- "$HOME/.local/bin/npx" || rollback_ok=0
				fi
			fi
		fi
		rm -f -- "$current_link" "$command_link"
		[[ "$key" != npm ]] || rm -f -- "$npx_link"
		if [[ "$committed" == 0 && "$rollback_ok" == 1 ]]; then
			rm -rf -- "$staging"
		elif [[ "$rollback_ok" == 0 ]]; then
			printf 'Catalog publication rollback failed; retaining release at %s for recovery.\n' "$staging" >&2
		fi
		return "$status"
	}
	trap 'dotfiles_catalog_publication_cleanup' EXIT
	payload="$staging/payload"
	mkdir "$payload" || return 1
	case "$archive" in
	npm-lock) dotfiles_catalog_stage_npm "$key" "$staging" "$payload" || return $? ;;
	python-lock) dotfiles_catalog_stage_python "$key" "$staging" "$payload" || return $? ;;
	raw)
		mkdir -p -- "$payload/$(dirname -- "$binary")" || return 1
		dotfiles_catalog_download "$key" "$payload/$binary" || return $?
		;;
	tar | tar.gz | tar.xz | tgz | zip)
		if [[ -n "$prepared_archive" ]]; then
			[[ "$key" == codex_cli && -f "$prepared_archive" && ! -L "$prepared_archive" ]] || return 2
			cp -- "$prepared_archive" "$staging/archive" || return 1
			dotfiles_catalog_verify "$staging/archive" "$(dotfiles_catalog_get "$key" digest)" || return 2
		else
			dotfiles_catalog_download "$key" "$staging/archive" || return $?
		fi
		dotfiles_catalog_extract "$archive" "$staging/archive" "$payload" || return $?
		;;
	*)
		printf 'Unsupported exact catalog adapter %s for %s.\n' "$archive" "$key" >&2
		return 2
		;;
	esac
	candidate="$payload/$binary"
	[[ -f "$candidate" && "$(realpath -- "$candidate")" == "$payload/"* ]] || return 2
	[[ "$key" != chrome_headless ]] || dotfiles_catalog_chrome_layout "$payload" "$binary" || return 2
	[[ "$key" != codex_cli ]] || dotfiles_catalog_codex_layout "$payload" "$version" "$binary" || return 2
	[[ "$key" != go ]] || dotfiles_catalog_go_defaults "$candidate" "$payload" || return 2
	[[ "$key" != npm ]] || dotfiles_catalog_npm_payload "$payload" "$version" || return 2
	chmod u+x "$candidate" || return 1
	dotfiles_catalog_version_matches "$candidate" "$version" "$version_arg" "$auto_env" "$auto_value" || {
		printf 'Catalog version verification failed for %s; preserving installed software.\n' "$key" >&2
		return 2
	}
	# A relative wrapper survives the same-filesystem staging rename.
	{
		printf '%s\n' '#!/usr/bin/env bash'
		if [[ "$archive" == npm-lock ]]; then
			local runtime_node
			IFS= read -r runtime_node <"$staging/.catalog-runtime" || return 2
			printf 'if [[ ! -x %q ]]; then echo "Approved Node.js runtime is unavailable; run dotfiles update." >&2; exit 2; fi\n' "$runtime_node"
			# shellcheck disable=SC2016  # The wrapper preserves its caller's PATH after the pinned runtime.
			printf 'export PATH=%q:"$PATH"\n' "$(dirname -- "$runtime_node")"
		fi
		if [[ "$key" == mermaid_cli ]]; then
			# shellcheck disable=SC2016  # The wrapper reads the caller's environment.
			printf '%s\n' 'if [[ -z "${PUPPETEER_EXECUTABLE_PATH:-}" && -x "$HOME/.local/bin/chrome-headless-shell" ]]; then export PUPPETEER_EXECUTABLE_PATH="$HOME/.local/bin/chrome-headless-shell"; fi'
		fi
		[[ -z "$auto_env" ]] || printf 'export %s=%q\n' "$auto_env" "$auto_value"
		# shellcheck disable=SC2016  # The generated wrapper resolves its path at runtime.
		printf 'exec "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/payload/%s" "$@"\n' "$binary"
	} >"$staging/command"
	chmod 0755 "$staging/command"
	if [[ "$key" == npm ]]; then
		chmod u+x "$payload/package/bin/npx-cli.js" || return 1
		dotfiles_catalog_version_matches "$payload/package/bin/npx-cli.js" "$version" --version || return 2
		# shellcheck disable=SC2016  # Resolve the immutable payload after publication.
		printf '%s\n' '#!/usr/bin/env bash' 'exec "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/payload/package/bin/npx-cli.js" "$@"' >"$staging/command-npx"
		chmod 0755 "$staging/command-npx" || return 1
		if [[ -L "$HOME/.local/bin/npx" ]]; then
			cp -a -- "$HOME/.local/bin/npx" "$staging/previous-npx" || return 1
		fi
	fi
	printf '%s\n%s\n%s\n' "$version" "$SOFTWARE_CATALOG_DIGEST" "${SOFTWARE_CATALOG_REVISION}" >"$staging/.catalog-receipt"
	printf '%s\n' "$identity" >"$staging/.catalog-target" || return 1
	local release="$root/releases/${staging##*/}"
	if [[ -e "$HOME/.local/bin/$command_name" || -L "$HOME/.local/bin/$command_name" ]]; then
		cp -a -- "$HOME/.local/bin/$command_name" "$staging/previous-command" || return 1
	fi
	# Completed releases stay immutable; one symlink rename publishes all files.
	ln -s -- "$release" "$current_link" || return 1
	mv -Tf -- "$current_link" "$root/current" || return 1
	current_published=1
	ln -s -- "$root/current/command" "$command_link" || return 1
	mv -Tf -- "$command_link" "$HOME/.local/bin/$command_name" || return 1
	command_published=1
	if [[ "$key" == npm ]]; then
		ln -s -- "$root/current/command-npx" "$npx_link" || return 1
		mv -Tf -- "$npx_link" "$HOME/.local/bin/npx" || return 1
		npx_published=1
	fi
	dotfiles_catalog_legacy_stamp "$key" "$version" || return 1
	committed=1
	rm -f -- "$staging/previous-command" "$staging/previous-npx"
)

dotfiles_catalog_manual_status() {
	local key="$1" label="$2" command_name executable raw installed='not installed'
	command_name="$(dotfiles_catalog_command_name "$key")"
	executable="$(command -v "$command_name" 2>/dev/null || true)"
	if [[ -n "$executable" ]]; then
		installed=installed
		raw="$(timeout 5 "$executable" --version 2>/dev/null)" || raw=''
		if [[ -n "$raw" ]]; then installed="${raw%%$'\n'*}"; fi
	fi
	printf '%s|%s|—|external\n' "$label" "$installed"
}

dotfiles_catalog_check() {
	local key="$1" installed='not installed' available='—' action=skip command_name root version_arg
	local label="${2:-$key}"
	command_name="$(dotfiles_catalog_command_name "$key")"
	root="$(dotfiles_catalog_root "$key")"
	if dotfiles_catalog_begin && [[ "$(dotfiles_catalog_get "$key" kind)" == external ]]; then
		dotfiles_catalog_manual_status "$key" "$label"
		return 1
	fi
	if ! dotfiles_catalog_begin || ! available="$(dotfiles_catalog_get "$key" version)"; then
		if [[ "$key" == ubuntu_sans_mono_fonts ]]; then
			dotfiles_catalog_check_fonts "$label" '—' blocked
			return 1
		fi
		local apt_receipt="$HOME/.local/share/dotfiles-catalog/$key.apt" package
		if [[ -e "$apt_receipt" || -L "$apt_receipt" ]]; then
			installed=unknown
			if [[ -f "$apt_receipt" && ! -L "$apt_receipt" ]]; then
				IFS= read -r package <"$apt_receipt" || package=''
				if dotfiles_catalog_apt_owned "$key" "$package"; then
					installed="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
					installed="${installed:-not installed}"
				fi
			fi
		elif dotfiles_catalog_managed "$key"; then
			installed="$(dotfiles_catalog_installed "$key")"
		elif dotfiles_catalog_external "$key"; then
			installed='external installation'
		fi
		printf '%s|%s|—|blocked\n' "$label" "$installed"
		return 1
	fi
	if [[ "$key" == ubuntu_sans_mono_fonts ]]; then
		dotfiles_catalog_check_fonts "$label" "$available"
		return $?
	fi
	if [[ "$(dotfiles_catalog_get "$key" archive 2>/dev/null || true)" == deb ]]; then
		dotfiles_catalog_check_deb "$key" "$label" "$available"
		return $?
	fi
	if dotfiles_catalog_external "$key"; then
		installed='external installation' action=external
	elif dotfiles_catalog_managed "$key"; then
		installed="$(dotfiles_catalog_installed "$key")"
		version_arg="$(dotfiles_catalog_version_arg "$key")"
		if [[ "$installed" == installed ]]; then
			action=blocked
		elif dotfiles_catalog_version_matches "$HOME/.local/bin/$command_name" "$available" "$version_arg"; then
			local expected_identity
			expected_identity="$(dotfiles_catalog_component_identity "$key")" || return 2
			if [[ "$(dotfiles_catalog_installed_identity "$key" 2>/dev/null || true)" == "$expected_identity" ]]; then
				action=current
			else action=upgrade; fi
		elif dotfiles_catalog_upgrade_allowed "$HOME/.local/bin/$command_name" "$available" "$version_arg"; then
			action=upgrade
		else
			action=blocked
		fi
	elif command -v "$command_name" >/dev/null 2>&1; then
		installed='external installation' action=external
	fi
	printf '%s|%s|%s|%s\n' "$label" "$installed" "$available" "$action"
	[[ "$action" == upgrade ]]
}

dotfiles_catalog_fonts_owned() {
	local directory="$HOME/.local/share/fonts/ubuntu-sans-mono"
	local -a proof=()
	[[ -d "$directory" && ! -L "$directory" && -f "$directory/.catalog-receipt" &&
		! -L "$directory/.catalog-receipt" && -O "$directory/.catalog-receipt" ]] || return 1
	mapfile -t proof <"$directory/.catalog-receipt"
	[[ "${#proof[@]}" == 1 ]] || return 1
	[[ "${proof[0]}" =~ ^[0-9a-f]{64}$ ]]
}

dotfiles_catalog_check_fonts() {
	local label="$1" available="$2" override="${3:-}" installed='not installed' action=skip
	local directory="$HOME/.local/share/fonts/ubuntu-sans-mono"
	if [[ -e "$directory" || -L "$directory" ]]; then
		if ! dotfiles_catalog_fonts_owned; then
			installed='external installation' action=external
		elif [[ ! -f "$directory/.version" || -L "$directory/.version" ]]; then
			installed=unknown action=blocked
		else
			installed="$(cat "$directory/.version")"
			if [[ "$installed" == "$available" ]]; then
				action=current
			elif dotfiles_catalog_version_is_older "$installed" "$available"; then
				action=upgrade
			else
				action=blocked
			fi
		fi
	fi
	[[ -z "$override" ]] || action="$override"
	printf '%s|%s|%s|%s\n' "$label" "$installed" "$available" "$action"
	[[ "$action" == upgrade ]]
}

dotfiles_catalog_check_deb() {
	local key="$1" label="$2" available="$3" package installed action=skip
	local receipt="$HOME/.local/share/dotfiles-catalog/$key.apt"
	package="$(dotfiles_catalog_get "$key" package)" || return 2
	installed="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
	if [[ -e "$receipt" || -L "$receipt" ]] && ! dotfiles_catalog_apt_owned "$key" "$package"; then
		installed="${installed:-not installed}" action=blocked
	elif [[ -z "$installed" ]]; then
		installed='not installed'
		if command -v "$(dotfiles_catalog_command_name "$key")" >/dev/null 2>&1; then
			installed='external installation' action=external
		fi
	elif [[ ! -f "$HOME/.local/share/dotfiles-catalog/$key.apt" || -L "$HOME/.local/share/dotfiles-catalog/$key.apt" ]]; then
		installed='external installation' action=external
	elif [[ "$installed" == "$available" ]]; then
		action=current
	elif dpkg --compare-versions "$installed" lt "$available"; then
		action=upgrade
	else
		action=blocked
	fi
	printf '%s|%s|%s|%s\n' "$label" "$installed" "$available" "$action"
	[[ "$action" == upgrade ]]
}

dotfiles_catalog_upgrade() {
	local key="$1" before after package before_identity after_identity
	dotfiles_catalog_begin || return $?
	if [[ "$(dotfiles_catalog_get "$key" kind)" == external ]]; then
		printf 'Skipping operator-managed %s.\n' "$key"
		if declare -F upgrade_result_set >/dev/null; then upgrade_result_set skipped; fi
		return 0
	fi
	if [[ "$key" == ubuntu_sans_mono_fonts ]]; then
		local directory="$HOME/.local/share/fonts/ubuntu-sans-mono"
		if ! dotfiles_catalog_fonts_owned; then
			if [[ -e "$directory/.catalog-receipt" || -L "$directory/.catalog-receipt" ]]; then return 2; fi
			printf 'Skipping absent or externally owned fonts.\n'
			if declare -F upgrade_result_set >/dev/null; then upgrade_result_set skipped; fi
			return 0
		fi
		[[ -f "$directory/.version" && ! -L "$directory/.version" ]] || return 2
		before="$(cat "$directory/.version")" || return 2
		dotfiles_catalog_fonts || return $?
		after="$(cat "$directory/.version")" || return 2
		dotfiles_catalog_upgrade_outcome "$before" "$after"
		return 0
	fi
	if [[ "$(dotfiles_catalog_get "$key" archive 2>/dev/null || true)" == deb ]]; then
		if [[ -f "$HOME/.local/share/dotfiles-catalog/$key.apt" ]]; then
			package="$(dotfiles_catalog_get "$key" package)" || return 2
			before="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
			dotfiles_catalog_install_debs "$key" || return $?
			after="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
			dotfiles_catalog_upgrade_outcome "$before" "$after"
			return 0
		fi
	fi
	if ! dotfiles_catalog_managed "$key"; then
		printf 'Skipping absent or externally owned %s.\n' "$key"
		if declare -F upgrade_result_set >/dev/null; then upgrade_result_set skipped; fi
		return 0
	fi
	[[ "$key" != cursor_cli ]] || {
		printf 'Cursor remains blocked: no verified autonomous-update suppression control.\n' >&2
		return 2
	}
	before="$(dotfiles_catalog_installed "$key")"
	before_identity="$(dotfiles_catalog_installed_identity "$key" 2>/dev/null || true)"
	dotfiles_catalog_install "$key" || return $?
	after="$(dotfiles_catalog_installed "$key")"
	after_identity="$(dotfiles_catalog_installed_identity "$key" 2>/dev/null || true)"
	dotfiles_catalog_upgrade_outcome "$before" "$after" "$before_identity" "$after_identity"
}

dotfiles_catalog_upgrade_outcome() {
	local before="$1" after="$2" before_identity="${3:-}" after_identity="${4:-}" result
	if [[ "$before" == "$after" && -n "$after_identity" && "$before_identity" != "$after_identity" ]]; then
		printf 'Approved dependencies refreshed at version %s.\n' "$after"
		result=updated
	elif [[ "$before" == "$after" ]]; then
		printf 'Already current at %s.\n' "$after"
		result=already-current
	else
		printf 'Updated from %s to %s.\n' "$before" "$after"
		result=updated
	fi
	if declare -F upgrade_result_set >/dev/null; then upgrade_result_set "$result"; fi
}

dotfiles_catalog_lock() {
	local key="$1" lock digest
	lock="$(dotfiles_catalog_get "$key" lock)" || return 2
	digest="$(dotfiles_catalog_get "$key" digest)" || return 2
	[[ "$lock" == locks/* && "$lock" != *'..'* && ! -L "$SOFTWARE_CATALOG_SNAPSHOT/$lock" ]] || return 2
	dotfiles_catalog_verify "$SOFTWARE_CATALOG_SNAPSHOT/$lock" "$digest" || return 2
	printf '%s\n' "$SOFTWARE_CATALOG_SNAPSHOT/$lock"
}

dotfiles_catalog_npm_runtime() {
	dotfiles_catalog_begin || return $?
	[[ "$(dotfiles_catalog_get nodejs owner)" == dotfiles && "$(dotfiles_catalog_get npm owner)" == dotfiles ]] || return 2
	dotfiles_catalog_native_owned nodejs && dotfiles_catalog_native_owned npm || return 2
	local -a proof=()
	mapfile -t proof <"$HOME/.local/share/dotfiles-catalog/nodejs.native" || return 2
	[[ "${#proof[@]}" == 7 ]] || return 2
	local prefix="${proof[5]}" node_version npm_version
	node_version="$(dotfiles_catalog_get nodejs version)" || return 2
	npm_version="$(dotfiles_catalog_get npm version)" || return 2
	dotfiles_catalog_version_matches "$prefix/bin/node" "$node_version" --version || return 2
	PATH="$prefix/bin:$PATH" dotfiles_catalog_version_matches "$prefix/bin/npm" "$npm_version" --version || return 2
	printf '%s\n%s\n' "$prefix/bin/node" "$prefix/bin/npm"
}

dotfiles_catalog_stage_npm() {
	local key="$1" staging="$2" payload="$3" lock package version
	lock="$(dotfiles_catalog_lock "$key")" || return 2
	package="$(dotfiles_catalog_get "$key" package)" || return 2
	version="$(dotfiles_catalog_get "$key" version)" || return 2
	cp -- "$lock" "$payload/package-lock.json" || return 1
	# Validate the root package and every downloaded transitive package before
	# npm can execute. npm ci then verifies the integrity of the tarball bytes.
	python3 - "$lock" "$payload/package.json" "$package" "$version" <<'PY'
import json,sys
source,destination,package,version=sys.argv[1:]
with open(source,encoding='utf-8') as f: lock=json.load(f)
packages=lock.get('packages',{})
if lock.get('lockfileVersion',0)<2 or packages.get('node_modules/'+package,{}).get('version')!=version: raise SystemExit('catalog npm version does not match lock')
for name,entry in packages.items():
    if name and (not entry.get('version') or not entry.get('integrity') or not entry.get('resolved') or entry.get('link')): raise SystemExit('npm lock is not a frozen integrity closure')
root=packages.get('',{})
with open(destination,'w',encoding='utf-8') as f: json.dump({key:root[key] for key in ('name','version','dependencies','devDependencies','optionalDependencies') if key in root},f)
PY
	[[ -f "$payload/package.json" ]] || return 2
	local runtime_output
	local -a runtime=()
	runtime_output="$(dotfiles_catalog_npm_runtime)" || {
		printf 'Install the approved Node.js/npm component before installing npm tools.\n' >&2
		return 2
	}
	mapfile -t runtime <<<"$runtime_output"
	[[ "${#runtime[@]}" == 2 && -x "${runtime[0]}" ]] || return 2
	printf '%s\n' "${runtime[@]}" >"$staging/.catalog-runtime" || return 1
	PATH="$(dirname -- "${runtime[0]}"):$PATH"
	export PATH
	PUPPETEER_SKIP_DOWNLOAD=1 "${runtime[1]}" ci --prefix "$payload" --ignore-scripts --omit=dev --no-audit --no-fund >"$staging/npm.log" 2>&1 || {
		printf 'Frozen npm installation failed; preserving installed software.\n' >&2
		return 1
	}
}

dotfiles_catalog_stage_python() {
	local key="$1" staging="$2" payload="$3" lock uv uv_version
	lock="$(dotfiles_catalog_lock "$key")" || return 2
	# uv is independently approved; it never downloads a floating Python.
	dotfiles_catalog_install uv || return $?
	uv="$HOME/.local/bin/uv"
	uv_version="$(dotfiles_catalog_get uv version)" || return 2
	if ! dotfiles_catalog_owned uv || ! dotfiles_catalog_version_matches "$uv" "$uv_version" --version; then
		printf 'The approved owned uv dependency is unavailable; preserving installed software.\n' >&2
		return 2
	fi
	local sync_rc=0
	UV_PYTHON_DOWNLOADS=never "$uv" venv --python python3 "$payload" >"$staging/python.log" 2>&1 || sync_rc=$?
	if ((sync_rc != 0)); then
		cat -- "$staging/python.log" >&2
		return "$sync_rc"
	fi
	UV_PYTHON_DOWNLOADS=never "$uv" pip sync --python "$payload/bin/python" --require-hashes "$lock" >"$staging/sync.log" 2>&1 || sync_rc=$?
	if ((sync_rc != 0)); then
		sync_rc=0
		UV_PYTHON_DOWNLOADS=never UV_SYSTEM_CERTS=true "$uv" pip sync --python "$payload/bin/python" --require-hashes "$lock" >"$staging/sync-retry.log" 2>&1 || sync_rc=$?
		if ((sync_rc != 0)); then
			cat -- "$staging/sync.log" "$staging/sync-retry.log" >&2
			return "$sync_rc"
		fi
	fi
}

dotfiles_catalog_apt_owned() {
	local package="$2" receipt="$HOME/.local/share/dotfiles-catalog/$1.apt"
	local -a proof=()
	[[ -f "$receipt" && ! -L "$receipt" && -O "$receipt" ]] || return 1
	mapfile -t proof <"$receipt"
	[[ "${#proof[@]}" == 3 ]] || return 1
	[[ "${proof[0]}" == "$package" && "$package" =~ ^[a-z0-9][a-z0-9+.-]+$ &&
		"${proof[1]}" =~ ^[0-9][A-Za-z0-9.+:~_-]+$ && "${proof[2]}" =~ ^[0-9a-f]{64}$ ]]
}

dotfiles_catalog_apt_holds() {
	local receipt package key
	local -a packages=()
	for receipt in "$HOME/.local/share/dotfiles-catalog/"*.apt; do
		[[ -e "$receipt" || -L "$receipt" ]] || continue
		key="${receipt##*/}"
		key="${key%.apt}"
		[[ "$(dotfiles_catalog_get "$key" owner)" == dotfiles && "$(dotfiles_catalog_get "$key" archive)" == deb ]] || return 2
		package="$(dotfiles_catalog_get "$key" package)" || return 2
		dotfiles_catalog_apt_owned "$key" "$package" || return 2
		packages+=("$package")
	done
	for package in "${packages[@]}"; do
		sudo apt-mark hold "$package" >/dev/null || return $?
	done
}

dotfiles_catalog_install_debs() (
	local key package version installed root tmp index=0 observed plan name comparison needs_change=0
	local -a files=() packages=() versions=() keys=("$@")
	(($# > 0)) || return 2
	# shellcheck disable=SC2034  # Serializes all vendor package/receipt changes.
	local catalog_transaction_fd
	dotfiles_catalog_transaction_lock apt-vendor catalog_transaction_fd || return $?
	dotfiles_catalog_begin || return $?
	root="$HOME/.local/share/dotfiles-catalog"
	# Resolve every member and ownership before downloading or invoking apt.
	for key in "${keys[@]}"; do
		[[ "$(dotfiles_catalog_get "$key" owner)" == dotfiles ]] || return 2
		[[ "$(dotfiles_catalog_get "$key" archive)" == deb ]] || return 2
		package="$(dotfiles_catalog_get "$key" package)" || return 2
		version="$(dotfiles_catalog_get "$key" version)" || return 2
		[[ "$package" =~ ^[a-z0-9][a-z0-9+.-]+$ && "$version" =~ ^[0-9][A-Za-z0-9.+:~_-]+$ ]] || return 2
		if [[ -e "$root/$key.apt" || -L "$root/$key.apt" ]] && ! dotfiles_catalog_apt_owned "$key" "$package"; then
			printf 'Invalid ownership receipt for apt package %s; preserving the installation.\n' "$package" >&2
			return 2
		fi
		installed="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
		if [[ -n "$installed" && ! -f "$root/$key.apt" ]]; then
			printf 'Preserving external apt package %s.\n' "$package" >&2
			return 0
		fi
		if [[ -n "$installed" ]]; then
			comparison=0
			dpkg --compare-versions "$installed" gt "$version" || comparison=$?
			case "$comparison" in
			0)
				printf 'Preserving newer managed apt package %s; review version drift.\n' "$package" >&2
				return 2
				;;
			1) ;;
			*) return 2 ;;
			esac
		fi
		[[ ! -L "$root/$key.apt" ]] || return 2
		if [[ "$installed" != "$version" || "${DOTFILES_FORCE_REINSTALL:-0}" == 1 ]]; then needs_change=1; fi
		packages+=("$package")
		versions+=("$version")
	done
	if [[ "$needs_change" == 0 ]]; then return 0; fi
	tmp="$(mktemp -d)" || return 1
	trap 'rm -rf -- "$tmp"' EXIT
	for key in "${keys[@]}"; do
		package="${packages[$index]}"
		version="${versions[$index]}"
		dotfiles_catalog_download "$key" "$tmp/$package.deb" || return $?
		[[ "$(dpkg-deb -f "$tmp/$package.deb" Package)" == "$package" ]] || return 2
		[[ "$(dpkg-deb -f "$tmp/$package.deb" Version)" == "$version" ]] || return 2
		files+=("$tmp/$package.deb")
		index=$((index + 1))
	done
	# Hold previously proven packages during dependency resolution. No vendor
	# package outside this exact batch may advance as an implicit dependency.
	dotfiles_catalog_apt_holds || return $?
	plan="$(sudo apt-get -s -o DPkg::Lock::Timeout=600 install --allow-downgrades --allow-change-held-packages "${files[@]}")" || return $?
	while IFS= read -r name; do
		case "$name" in
		powershell | obsidian | docker-ce | docker-ce-cli | containerd.io | docker-buildx-plugin | docker-compose-plugin)
			[[ " ${packages[*]} " == *" $name "* ]] || {
				printf 'Refusing floating vendor dependency %s.\n' "$name" >&2
				return 2
			}
			;;
		esac
	done < <(awk '$1=="Inst" {print $2}' <<<"$plan")
	sudo apt-get -qq -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=600 install -y --allow-downgrades --allow-change-held-packages "${files[@]}" || return $?
	mkdir -p -- "$root" || return 1
	index=0
	for key in "${keys[@]}"; do
		package="${packages[$index]}"
		version="${versions[$index]}"
		observed="$(dpkg-query -W -f='${Version}' "$package")" || return 1
		[[ "$observed" == "$version" ]] || return 2
		printf '%s\n%s\n%s\n' "$package" "$version" "$SOFTWARE_CATALOG_DIGEST" >"$root/$key.apt.$$" || return 1
		mv -f -- "$root/$key.apt.$$" "$root/$key.apt" || return 1
		sudo apt-mark hold "$package" >/dev/null || return $?
		index=$((index + 1))
	done
)

dotfiles_catalog_fonts() (
	local key=ubuntu_sans_mono_fonts version archive parent destination staging font basename installed keep_staging=0
	# shellcheck disable=SC2034  # Holds the descriptor through font publication.
	local catalog_transaction_fd
	dotfiles_catalog_transaction_lock ubuntu_sans_mono_fonts catalog_transaction_fd || return $?
	dotfiles_catalog_begin || return $?
	version="$(dotfiles_catalog_get "$key" version)" || return 2
	archive="$(dotfiles_catalog_get "$key" archive)" || return 2
	parent="$HOME/.local/share/fonts"
	destination="$parent/ubuntu-sans-mono"
	[[ ! -L "$destination" ]] || return 2
	if [[ -e "$destination" ]] && ! dotfiles_catalog_fonts_owned; then
		printf 'Preserving externally owned or unverifiable Ubuntu Sans Mono fonts.\n' >&2
		if [[ -e "$destination/.catalog-receipt" || -L "$destination/.catalog-receipt" ]]; then return 2; fi
		return 0
	fi
	if [[ -d "$destination" ]]; then
		[[ -f "$destination/.version" && ! -L "$destination/.version" ]] || return 2
		installed="$(cat "$destination/.version")" || return 2
		if [[ "$installed" != "$version" ]] && ! dotfiles_catalog_version_is_older "$installed" "$version"; then
			printf 'Preserving newer or unverifiable managed fonts; review version drift.\n' >&2
			return 2
		fi
	fi
	if [[ "${DOTFILES_FORCE_REINSTALL:-0}" != 1 && -f "$destination/.version" && "$(cat "$destination/.version")" == "$version" ]]; then
		install_ubuntu_sans_mono_windows "$destination"
		return $?
	fi
	mkdir -p -- "$parent" || return 1
	staging="$(mktemp -d "$parent/.catalog-fonts-XXXXXX")" || return 1
	trap 'if [[ "$keep_staging" == 0 ]]; then rm -rf -- "$staging"; fi' EXIT
	dotfiles_catalog_download "$key" "$staging/archive" || return $?
	mkdir "$staging/extracted" "$staging/fonts" || return 1
	dotfiles_catalog_extract "$archive" "$staging/archive" "$staging/extracted" || return $?
	if [[ -d "$destination" ]]; then cp -a -- "$destination/." "$staging/fonts/" || return 1; fi
	local count=0
	while IFS= read -r -d '' font; do
		basename="${font##*/}"
		[[ "$basename" != *'['* && "$basename" != *']'* ]] || continue
		[[ ! -e "$staging/seen-$basename" ]] || return 2
		: >"$staging/seen-$basename"
		# Unlink preserved user symlinks before writing the approved bytes.
		rm -f -- "$staging/fonts/$basename" || return 1
		cp -- "$font" "$staging/fonts/$basename" || return 1
		count=$((count + 1))
	done < <(find "$staging/extracted" -type f -iname '*.ttf' -print0)
	((count > 0)) || return 2
	rm -f -- "$staging/fonts/.version" "$staging/fonts/.catalog-receipt" || return 1
	printf '%s\n' "$version" >"$staging/fonts/.version"
	printf '%s\n' "$SOFTWARE_CATALOG_DIGEST" >"$staging/fonts/.catalog-receipt"
	if [[ -e "$destination" ]]; then mv -- "$destination" "$staging/previous" || return 1; fi
	if ! mv -- "$staging/fonts" "$destination"; then
		if [[ -e "$staging/previous" ]] && ! mv -- "$staging/previous" "$destination"; then
			keep_staging=1
			printf 'Font rollback failed; previous fonts retained at %s.\n' "$staging/previous" >&2
		fi
		return 1
	fi
	if ! fc-cache -f "$destination" >/dev/null 2>&1; then
		if ! mv -- "$destination" "$staging/failed"; then
			keep_staging=1
		elif [[ -e "$staging/previous" ]] && ! mv -- "$staging/previous" "$destination"; then
			keep_staging=1
		fi
		if [[ "$keep_staging" == 1 ]]; then
			printf 'Font cache failed and rollback needs recovery; retained files at %s.\n' "$staging" >&2
		fi
		return 1
	fi
	install_ubuntu_sans_mono_windows "$destination"
)

# Existing installers already proved ownership for these layouts. Recognize
# their receipts so adopting the catalog does not strand installed tools.
dotfiles_catalog_managed() {
	local key="$1" helper=''
	dotfiles_catalog_owned "$key" && return 0
	if dotfiles_catalog_has_current "$key"; then return 1; fi
	case "$key" in
	boost_cli) helper=boost_cli_is_dotfiles_owned ;;
	graphify_cli) helper=graphify_cli_is_uv_owned ;;
	codex_cli) helper=codex_standalone_is_installed ;;
	chrome_headless) helper=chrome_headless_is_dotfiles_owned ;;
	markdownlint_cli2 | cspell | mermaid_cli)
		declare -F npm_cli_is_dotfiles_owned >/dev/null && npm_cli_is_dotfiles_owned "$key"
		return $?
		;;
	kubeconform | tflint | zizmor | vale | yt_dlp | trivy | infracost)
		declare -F release_cli_is_dotfiles_owned >/dev/null && release_cli_is_dotfiles_owned "$key"
		return $?
		;;
	esac
	[[ -n "$helper" ]] && declare -F "$helper" >/dev/null && "$helper"
}

dotfiles_catalog_version_arg() {
	if dotfiles_catalog_get "$1" discovery.version_arg 2>/dev/null; then return; fi
	case "$1" in
	kubeconform) echo -v ;;
	boost_cli | go) echo version ;;
	*) echo --version ;;
	esac
}

dotfiles_catalog_installed() {
	local key="$1" command_name raw
	if [[ "$key" == cursor_cli ]]; then
		printf 'installed\n'
		return
	fi
	if [[ "$key" == codex_cli ]] && ! dotfiles_catalog_codex_defaults check >/dev/null 2>&1; then
		printf 'installed\n'
		return
	fi
	command_name="$(dotfiles_catalog_command_name "$key")"
	local -a argv=() environment=()
	case "$key" in
	go) environment=(GOTOOLCHAIN=local) ;;
	claude_cli) environment=(DISABLE_UPDATES=1) ;;
	antigravity_cli) environment=(AGY_CLI_DISABLE_AUTO_UPDATE=true) ;;
	esac
	read -r -a argv <<<"$(dotfiles_catalog_version_arg "$key")"
	raw="$(env "${environment[@]}" "$HOME/.local/bin/$command_name" "${argv[@]}" 2>/dev/null)" || {
		printf 'installed\n'
		return
	}
	python3 - "$raw" <<'PYVERSION'
import re,sys
match=re.search(r'(?<![0-9A-Za-z])(?:go|v)?([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)',sys.argv[1])
print(match[1] if match else 'installed')
PYVERSION
}

dotfiles_catalog_legacy_stamp() {
	local key="$1" version="$2" stamp=''
	if declare -F release_cli_field >/dev/null && release_cli_field "$key" repository >/dev/null 2>&1; then
		stamp="$HOME/.local/share/dotfiles/$key.version"
		version="v${version#v}"
	else
		case "$key" in
		boost_cli)
			stamp="$HOME/.local/share/dotfiles/boost-cli.version"
			version="v${version#v}"
			;;
		markdownlint_cli2 | cspell | mermaid_cli | chrome_headless)
			stamp="$HOME/.local/share/dotfiles/$key.version"
			;;
		esac
	fi
	[[ -n "$stamp" ]] || return 0
	mkdir -p -- "$(dirname -- "$stamp")" || return 1
	printf '%s\n' "$version" >"$stamp.$$" || return 1
	mv -f -- "$stamp.$$" "$stamp"
}
