# shellcheck shell=bash

# Inspect legacy paths without executing their runtime or manager code.
dotfiles_catalog_nvm_inventory() {
	local node_path npm_path npx_path
	node_path="$(command -v node 2>/dev/null)" || return 2
	npm_path="$(command -v npm 2>/dev/null)" || return 2
	npx_path="$(command -v npx 2>/dev/null)" || return 2
	python3 -I -B - "${NVM_DIR:-$HOME/.nvm}" "$HOME" "$1" "$node_path" "$npm_path" "$npx_path" <<'PY'
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
