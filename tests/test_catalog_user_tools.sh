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
del entries['future-source']['targets']['linux-amd64']['archive']
del entries['future-source']['targets']['linux-amd64']['binary']
entries['future-source']['targets']['linux-amd64']['revision'] = 'a' * 40
snapshot = SimpleNamespace(data={'components': entries}, approved=False)
assert set(module.select_inventory(snapshot)) == {'runtime', 'future-source'}
print('User-tools coverage includes future managed Git sources')
PY
python3 - "$root" <<'PY'
import ast
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
tree = ast.parse((root / 'scripts/catalog/qualify-user-tools.py').read_text())
scripts = [ast.literal_eval(node.value) for node in ast.walk(tree)
           if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'script' for target in node.targets)]
assert len(scripts) == 1
prefix = scripts[0].split('software_catalog_qualification_begin', 1)[0]
with tempfile.TemporaryDirectory() as home:
    result = subprocess.run(
        ['bash', '-c', prefix + '\ndeclare -F dotfiles_catalog_source_install >/dev/null\n', 'bash', str(root)],
        env={'PATH': '/usr/bin:/bin', 'HOME': home, 'LANG': 'C.UTF-8', 'DOTFILES_SHARED_DIR': str(root.parent / 'dotfiles-shared')},
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr or 'driver did not load the managed Git source API'
print('User-tools driver loads its Git source installation API')
PY
