# shellcheck shell=bash

# Inspect legacy paths without executing their runtime or manager code.
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
	/usr/bin/python3 -I -B - "${ASDF_DATA_DIR:-$HOME/.asdf}" "$HOME" "$1" "$go_path" "$asdf_path" "$approved_asdf" <<'PY'
import hashlib,json,os,pathlib,re,subprocess,sys
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
    environment={'PATH':'/usr/bin:/bin','HOME':str(home),'LANG':'C.UTF-8',
                 'GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_NOSYSTEM':'1','GIT_TERMINAL_PROMPT':'0'}
    def git(*arguments):
        return subprocess.run(['/usr/bin/git','-c','core.hooksPath=/dev/null','-c','core.fsmonitor=false',
                               '-C',str(plugin),*arguments],env=environment,text=True,
                              capture_output=True,timeout=30,check=True).stdout.strip()
    require(git('rev-parse','--show-toplevel')==str(plugin))
    revision=git('rev-parse','HEAD'); require(re.fullmatch(r'[0-9a-f]{40}',revision))
    require(git('remote','get-url','origin').removesuffix('.git') in (
        'https://github.com/asdf-community/asdf-golang','git@github.com:asdf-community/asdf-golang',
        'ssh://git@github.com/asdf-community/asdf-golang'))
    expected={}
    for record in git('ls-tree','-r','-z',revision).split('\0'):
        if not record: continue
        metadata,name=record.split('\t',1); mode,kind,blob=metadata.split()
        relative=pathlib.PurePosixPath(name)
        require(not relative.is_absolute() and str(relative)==name and not any(p in ('.','..') for p in relative.parts))
        require(kind=='blob' and mode in ('100644','100755','120000') and re.fullmatch(r'[0-9a-f]{40}',blob))
        require(name not in expected and len(expected)<4096)
        expected[name]=(mode,blob)
    require('bin/install' in expected)
    indexed={}
    for record in git('ls-files','--stage','-z').split('\0'):
        if not record: continue
        metadata,name=record.split('\t',1); mode,blob,stage=metadata.split()
        require(stage=='0' and name not in indexed)
        indexed[name]=(mode,blob)
    require(indexed==expected)
    observed=set()
    for directory,dirs,files in os.walk(plugin,followlinks=False):
        for name in list(dirs):
            path=pathlib.Path(directory)/name
            if path==plugin/'.git': dirs.remove(name)
            elif path.is_symlink(): dirs.remove(name); files.append(name)
        for name in files:
            observed.add(str((pathlib.Path(directory)/name).relative_to(plugin)))
            require(len(observed)<=4096)
    require(observed==set(expected))
    total=0
    for name,(mode,blob) in expected.items():
        path=plugin/name; metadata=path.lstat()
        require(metadata.st_uid==os.geteuid())
        if path.is_symlink():
            require(mode=='120000'); content=os.fsencode(os.readlink(path))
            actual=hashlib.sha1(b'blob '+str(len(content)).encode()+b'\0'+content).hexdigest()
        else:
            require(path.is_file() and mode in ('100644','100755'))
            require(bool(metadata.st_mode&0o111)==(mode=='100755') and metadata.st_size<=4194304)
            total+=metadata.st_size; require(total<=33554432)
            digest=hashlib.sha1(b'blob '+str(metadata.st_size).encode()+b'\0')
            with path.open('rb') as stream:
                for block in iter(lambda:stream.read(1048576),b''): digest.update(block)
            actual=digest.hexdigest()
        require(actual==blob)
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
except (OSError,ValueError,RuntimeError,subprocess.SubprocessError):
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
