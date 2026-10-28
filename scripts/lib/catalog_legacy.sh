# shellcheck shell=bash

# Inspect legacy paths without executing their runtime or manager code.
dotfiles_catalog_local_inventory() {
	local key="$1" command_name="$2" extra="${3:-}" active
	active="$(command -v "$command_name" 2>/dev/null)" || return 2
	/usr/bin/python3 -I -B - "$key" "$command_name" "$HOME" "$active" "$extra" <<'PY'
import errno,hashlib,json,os,pathlib,re,stat,sys
key,name,home,active,extra=sys.argv[1:]
home,active=map(pathlib.Path,(home,active)); records={}
def require(value):
    if not value: raise ValueError('unverifiable local command')
def directory(path):
    require(path.is_absolute() and path.is_dir() and not path.is_symlink())
    require(path.resolve()==path and path.stat().st_uid==os.geteuid())
def parents(path):
    relative=path.parent.relative_to(home)
    current=home
    for part in relative.parts:
        current=current/part; directory(current)
def inspect(path):
    for _ in range(8):
        require(path.is_absolute() and path.is_relative_to(home))
        require(not path.is_relative_to(home/'.local/share/dotfiles-catalog'))
        parents(path); metadata=path.lstat()
        require(metadata.st_uid==os.geteuid())
        identity=[metadata.st_mode,metadata.st_uid,metadata.st_dev,metadata.st_ino]
        if stat.S_ISLNK(metadata.st_mode):
            target=os.readlink(path); records[str(path)]=[*identity,target]
            path=pathlib.Path(os.path.normpath(str(path.parent/target)))
            continue
        require(stat.S_ISREG(metadata.st_mode) and os.access(path,os.X_OK))
        if path in allowed: require(metadata.st_nlink==1)
        require(not metadata.st_mode&(stat.S_ISUID|stat.S_ISGID))
        try: require(not os.getxattr(path,'security.capability'))
        except OSError as error: require(error.errno in {errno.ENODATA,errno.ENOTSUP})
        require(metadata.st_size<=536870912)
        digest=hashlib.sha256(); size=0
        with path.open('rb') as stream:
            for block in iter(lambda:stream.read(1048576),b''):
                size+=len(block); require(size<=536870912); digest.update(block)
            after=os.fstat(stream.fileno())
        require((metadata.st_ino,metadata.st_size,metadata.st_mtime_ns)==(after.st_ino,after.st_size,after.st_mtime_ns))
        records[str(path)]=[*identity,digest.hexdigest()]
        return path
    raise ValueError('local command has too many symbolic links')
try:
    require(re.fullmatch(r'[a-z][a-z0-9_.-]*',key))
    require(key not in {'nodejs','npm','go','asdf','nvm','asdf-golang'})
    require(re.fullmatch(r'[A-Za-z0-9_+.-]+',name) and name not in {'.','..'})
    require(not any(ord(c)<32 or ord(c)==127 for c in str(home)+str(active)+extra))
    directory(home)
    canonical=home/'.local/bin'/name; bridge=home/'bin'/name
    allowed={canonical,bridge}
    if extra:
        require(re.fullmatch(re.escape(str(home))+r'/\.nvm/versions/node/v[0-9]+\.[0-9]+\.[0-9]+/bin/'+re.escape(name),extra))
        allowed.add(pathlib.Path(extra))
    require(active in allowed)
    current=home/'.local/share/dotfiles-catalog'/key/'current'
    require(not current.exists() and not current.is_symlink())
    for path in (home/'.local',home/'.local/bin'):
        if path.exists() or path.is_symlink(): directory(path)
    executable=inspect(active); aliases=[]
    for path in sorted(allowed,key=str):
        if not path.exists() and not path.is_symlink(): continue
        require(inspect(path)==executable)
        if path!=canonical: aliases.append(str(path))
    digest=hashlib.sha256(json.dumps(records,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    print('\t'.join([digest,str(active),*aliases]))
except (OSError,ValueError,RuntimeError):
    print('Unreceipted local command paths are foreign, changed or unverifiable; preserving them.',file=sys.stderr)
    raise SystemExit(2)
PY
}

dotfiles_catalog_local_migration_authorized() {
	case "${DOTFILES_MIGRATE_LOCAL_TOOLS:-}" in
	1) return 0 ;;
	'') ;;
	*)
		printf 'DOTFILES_MIGRATE_LOCAL_TOOLS must be 1 when set.\n' >&2
		return 2
		;;
	esac
	if [[ "${DOTFILES_INTERACTIVE_TTY:-false}" == true ]] && declare -F ui_confirm_yes_no >/dev/null; then
		ui_confirm_yes_no "  Replace the listed unreceipted $1 command with catalog version $2 and keep a recovery copy?"
		return $?
	fi
	return 1
}

dotfiles_catalog_local_version_allowed() {
	local executable="$1" expected="$2" version_arg="$3" env_name="${4:-}" env_value="${5:-}" parsed
	local -a argv=()
	read -r -a argv <<<"$version_arg"
	# A separate process group keeps descendant output inside the probe deadline.
	parsed="$(
		/usr/bin/python3 -I -B - "$executable" "$env_name" "$env_value" "${argv[@]}" <<'PY'
import os,re,selectors,signal,subprocess,sys,time
process=None; finished=False
def interrupted(_signal,_frame): raise InterruptedError('version probe interrupted')
for event in (signal.SIGINT,signal.SIGTERM,signal.SIGHUP): signal.signal(event,interrupted)
try:
    environment={key:os.environ[key] for key in ('HOME','PATH','NVM_DIR','ASDF_DATA_DIR','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME') if key in os.environ}
    environment['LANG']='C.UTF-8'
    if sys.argv[2]:
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*',sys.argv[2]) or not re.fullmatch(r'[A-Za-z0-9_-]+',sys.argv[3]): raise ValueError('invalid updater control')
        environment[sys.argv[2]]=sys.argv[3]
    deadline=time.monotonic()+5
    process=subprocess.Popen([sys.argv[1],*sys.argv[4:]],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,env=environment,start_new_session=True)
    raw=bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout,selectors.EVENT_READ)
        while True:
            remaining=deadline-time.monotonic()
            if remaining<=0 or not selector.select(remaining): raise TimeoutError('version probe timed out')
            block=os.read(process.stdout.fileno(),min(8193-len(raw),8193))
            if not block: break
            raw.extend(block)
            if len(raw)>8192: raise ValueError('version output exceeds its bound')
    status=process.wait(timeout=max(.01,deadline-time.monotonic())); finished=True
    if status: raise ValueError('version probe failed')
    match=re.search(rb'(?<![0-9A-Za-z])(?:go|v)?([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)',raw)
    if not match: raise ValueError('unverifiable version')
    print(match[1].decode('ascii'))
except (OSError,ValueError,TimeoutError,subprocess.SubprocessError):
    raise SystemExit(2)
finally:
    if process is not None:
        if not finished:
            try: os.killpg(process.pid,signal.SIGKILL)
            except ProcessLookupError: pass
            try: process.wait(timeout=1)
            except (OSError,subprocess.TimeoutExpired): pass
        process.stdout.close()
PY
	)" || return 2
	[[ "${parsed#v}" == "${expected#v}" ]] || dotfiles_catalog_version_is_older "$parsed" "$expected"
}

dotfiles_catalog_nvm_inventory() {
	local node_path npm_path npx_path
	node_path="$(command -v node 2>/dev/null)" || return 2
	npm_path="$(command -v npm 2>/dev/null)" || return 2
	npx_path="$(command -v npx 2>/dev/null)" || return 2
	/usr/bin/python3 -I -B - "${NVM_DIR:-$HOME/.nvm}" "$HOME" "$1" "$node_path" "$npm_path" "$npx_path" <<'PY'
import hashlib,json,os,pathlib,re,sys
root,home=map(pathlib.Path,sys.argv[1:3]); version=sys.argv[3]
active=dict(zip(('node','npm','npx'),map(pathlib.Path,sys.argv[4:])))
def require(condition):
    if not condition: raise ValueError('legacy NVM paths cannot be safely migrated')
def plain(path):
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink())
    require(path.stat().st_uid==os.geteuid())
def regular(path):
    plain(path); require(path.is_file())
try:
    require(root==home/'.nvm' and not any(ord(c)<32 or ord(c)==127 for c in str(root)))
    plain(root)
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',version))
    for key in ('nodejs','npm'):
        receipt=home/'.local/share/dotfiles-catalog'/(key+'.native')
        require(not receipt.exists() and not receipt.is_symlink())
    require(all(path.is_absolute() for path in active.values()))
    node=active['node'].resolve(strict=True)
    prefix=node.parent.parent
    require(node==prefix/'bin/node' and prefix.parent==root/'versions/node')
    require(re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+',prefix.name))
    for path in (root/'versions',root/'versions/node',prefix,prefix/'bin'):
        plain(path); require(path.is_dir())
    for path in (root/'alias',home/'.local/bin'):
        if path.exists() or path.is_symlink():
            plain(path); require(path.is_dir())
    regular(node); require(os.access(node,os.X_OK))
    files=[node]
    for name in ('npm','npx'):
        expected=prefix/'lib/node_modules/npm/bin'/(name+'-cli.js')
        regular(expected); require(os.access(expected,os.X_OK))
        require(active[name].resolve(strict=True)==expected)
        require((prefix/'bin'/name).is_symlink() and (prefix/'bin'/name).resolve()==expected)
        files.append(expected)
    for name in ('nvm.sh','bash_completion','nvm-exec'):
        path=root/name; regular(path); files.append(path)
    for name,path in active.items():
        alias=home/'.local/bin'/name
        require(path in (prefix/'bin'/name,alias))
        if alias.exists() or alias.is_symlink():
            require(alias.is_symlink() and alias.lstat().st_uid==os.geteuid())
            require(alias.resolve(strict=True)==path.resolve(strict=True))
        files.append(alias)
    default=root/'alias/default'
    if default.exists() or default.is_symlink(): regular(default)
    files.append(default)
    target=root/'versions/node'/('v'+version)
    require(target==prefix or (not target.exists() and not target.is_symlink()))
    digest=hashlib.sha256()
    for path in files:
        digest.update(json.dumps(str(path)).encode()+b'\0')
        if path.is_symlink(): digest.update(os.readlink(path).encode()+b'\0')
        elif path.exists():
            digest.update(str(path.stat().st_mode).encode()+b'\0')
            with path.open('rb') as stream:
                for block in iter(lambda:stream.read(1048576),b''): digest.update(block)
        else: digest.update(b'missing')
        digest.update(b'\0')
    print(str(prefix)+'\t'+digest.hexdigest())
except (OSError,ValueError,RuntimeError):
    print('Legacy NVM layout is external, changed or unverifiable; preserving it.',file=sys.stderr)
    raise SystemExit(2)
PY
}

dotfiles_catalog_nvm_migration_authorized() {
	case "${DOTFILES_MIGRATE_NVM:-}" in
	1) return 0 ;;
	'') ;;
	*)
		printf 'DOTFILES_MIGRATE_NVM must be 1 when set.\n' >&2
		return 2
		;;
	esac
	if [[ "${DOTFILES_INTERACTIVE_TTY:-false}" == true ]] && declare -F ui_confirm_yes_no >/dev/null; then
		ui_confirm_yes_no '  Migrate the listed NVM installation to the approved Node/npm catalog?'
		return $?
	fi
	printf 'Re-run with DOTFILES_MIGRATE_NVM=1 to authorize only this NVM migration.\n' >&2
	return 2
}

dotfiles_catalog_asdf_go_inventory() {
	local go_path asdf_path approved_asdf=0
	go_path="$(command -v go 2>/dev/null)" || return 2
	asdf_path="$(command -v asdf 2>/dev/null)" || return 2
	if declare -F dotfiles_catalog_owned >/dev/null && dotfiles_catalog_owned asdf; then approved_asdf=1; fi
	/usr/bin/python3 -I -B - "${ASDF_DATA_DIR:-$HOME/.asdf}" "$HOME" "$1" "$go_path" "$asdf_path" "$approved_asdf" "$DOTFILES_SHARED_ROOT" <<'PY'
import hashlib,json,os,pathlib,re,sys
sys.path.insert(0,str(pathlib.Path(sys.argv[7])/"scripts/lib/shared/python"))
from catalog_git_source import read_git,verify_checkout
root,home=map(pathlib.Path,sys.argv[1:3]); target=sys.argv[3]
active_go,active_asdf=map(pathlib.Path,sys.argv[4:6]); approved_asdf=sys.argv[6]=='1'
def require(condition):
    if not condition: raise ValueError('legacy Go/asdf paths cannot be safely migrated')
def plain(path):
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink())
    require(path.stat().st_uid==os.geteuid())
def regular(path):
    plain(path); require(path.is_file())
try:
    require(root==home/'.asdf' and not any(ord(c)<32 or ord(c)==127 for c in str(root)))
    require(not os.environ.get('ASDF_GOLANG_VERSION'))
    require(os.environ.get('ASDF_TOOL_VERSIONS_FILENAME','.tool-versions')=='.tool-versions')
    require(os.environ.get('ASDF_DIR',str(root))==str(root))
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',target))
    for path in (root,root/'bin',root/'shims',root/'plugins',root/'installs',root/'installs/golang'):
        plain(path); require(path.is_dir())
    receipt=home/'.local/share/dotfiles-catalog/go.native'
    require(not receipt.exists() and not receipt.is_symlink())
    selection=home/'.tool-versions'; regular(selection)
    require(selection.stat().st_size<=65536)
    versions=[line.split() for line in selection.read_text().splitlines() if line.split()[:1]==['golang']]
    require(len(versions)==1 and len(versions[0])==2)
    version=versions[0][1]; require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',version))
    for directory in (pathlib.Path.cwd(),*pathlib.Path.cwd().parents):
        if directory==home: break
        override=directory/'.tool-versions'
        require(not override.exists() and not override.is_symlink())
    install=root/'installs/golang'/version; plain(install)
    binary=install/'go/bin/go'; regular(binary); require(os.access(binary,os.X_OK))
    manager=root/'bin/asdf'; regular(manager); require(os.access(manager,os.X_OK))
    public_asdf=home/'.local/bin/asdf'
    require(active_asdf in (manager,public_asdf))
    if public_asdf.exists() or public_asdf.is_symlink(): require(approved_asdf)
    else: require(active_asdf==manager)
    shim=root/'shims/go'; regular(shim)
    require(shim.stat().st_size<=65536 and os.access(shim,os.X_OK))
    public_go=home/'.local/bin/go'
    require(active_go in (shim,binary,public_go))
    if public_go.exists() or public_go.is_symlink():
        require(public_go.is_symlink() and public_go.lstat().st_uid==os.geteuid())
        require(public_go.resolve(strict=True)==binary)
    candidate=root/'installs/golang'/target
    require(candidate==install or (not candidate.exists() and not candidate.is_symlink()))
    plugin=root/'plugins/golang'; plain(plugin); plain(plugin/'.git'); require((plugin/'.git').is_dir())
    regular(plugin/'bin/install'); require(os.access(plugin/'bin/install',os.X_OK))
    revision=read_git(plugin,'rev-parse','HEAD'); require(re.fullmatch(r'[0-9a-f]{40}',revision))
    require(read_git(plugin,'remote','get-url','origin').removesuffix('.git') in (
        'https://github.com/asdf-community/asdf-golang','git@github.com:asdf-community/asdf-golang',
        'ssh://git@github.com/asdf-community/asdf-golang'))
    verify_checkout(plugin,revision,allow_ignored=False)
    digest=hashlib.sha256(revision.encode())
    for path in (binary,manager,shim,selection,public_go):
        digest.update(json.dumps(str(path)).encode()+b'\0')
        if path.is_symlink(): digest.update(os.readlink(path).encode()+b'\0')
        elif path.exists():
            digest.update(str(path.stat().st_mode).encode()+b'\0')
            with path.open('rb') as stream:
                for block in iter(lambda:stream.read(1048576),b''): digest.update(block)
        else: digest.update(b'missing')
        digest.update(b'\0')
    print(str(install)+'\t'+digest.hexdigest())
except (OSError,ValueError,RuntimeError):
    print('Legacy Go/asdf layout is external, modified or unverifiable; preserving it.',file=sys.stderr)
    raise SystemExit(2)
PY
}

dotfiles_catalog_asdf_go_migration_authorized() {
	case "${DOTFILES_MIGRATE_ASDF_GO:-}" in
	1) return 0 ;;
	'') ;;
	*)
		printf 'DOTFILES_MIGRATE_ASDF_GO must be 1 when set.\n' >&2
		return 2
		;;
	esac
	if [[ "${DOTFILES_INTERACTIVE_TTY:-false}" == true ]] && declare -F ui_confirm_yes_no >/dev/null; then
		ui_confirm_yes_no '  Migrate the listed Go/asdf installation to the approved catalog?'
		return $?
	fi
	printf 'Re-run with DOTFILES_MIGRATE_ASDF_GO=1 to authorize only this Go/asdf migration.\n' >&2
	return 2
}
