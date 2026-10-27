#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
[[ -f "$root/scripts/catalog/qualify-user-tools.py" ]] || {
	printf 'FAIL: missing real user-tools driver\n' >&2
	exit 1
}
rc=0
python3 "$root/scripts/catalog/qualify-user-tools.py" "$temporary/missing-context" \
	--output "$temporary/evidence.json" >"$temporary/output" 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$temporary/evidence.json" ]]
! rg -q Traceback "$temporary/output"
printf 'PASS: invalid user-tools context cannot start installation or write evidence\n'
python3 - "$root" <<'PY'
import importlib.util
import pathlib
import sys
from types import SimpleNamespace

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root.parent / 'dotfiles-shared/scripts/lib/shared/python'))
spec = importlib.util.spec_from_file_location('user_tools_smoke', root / 'scripts/catalog/qualify-user-tools.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, 'select_inventory'), 'Git sources are missing from user-tools observations'
entries = {}
for key, kind, archive in (
    ('runtime', 'software', 'tar.gz'), ('future-source', 'git-source', 'git-source'),
    ('vendor', 'vendor-apt', 'deb'), ('application', 'software', 'deb'),
    ('container', 'software', 'oci'), ('font', 'software', 'zip'),
):
    entries[key] = {'owner': 'dotfiles', 'kind': kind, 'requires': [], 'blockers': [],
                    'targets': {'linux-amd64': {'archive': archive, 'binary': 'fonts' if key == 'font' else key}}}
snapshot = SimpleNamespace(data={'components': entries}, approved=False)
assert set(module.select_inventory(snapshot)) == {'runtime', 'future-source'}
print('User-tools coverage includes future managed Git sources')
PY
