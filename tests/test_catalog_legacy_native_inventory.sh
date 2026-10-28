#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import importlib.util,json,pathlib,sys,tempfile
from types import SimpleNamespace
root=pathlib.Path(sys.argv[1])
spec=importlib.util.spec_from_file_location('legacy_native',root/'scripts/catalog/legacy_native.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
entries={}
for key,kind,archive,binary in (
    ('future-native','software','tar.gz','future'),
    ('future-raw','software','raw','future-raw'),
    ('nodejs','software','tar.xz','node'),
    ('font','software','zip','fonts'),
    ('dependency','software','npm-lock','dependency'),
    ('vendor','vendor-apt','deb','vendor'),
):
    entries[key]={'owner':'dotfiles','kind':kind,'targets':{'linux-amd64':{'archive':archive,'binary':binary}}}
snapshot=SimpleNamespace(data={'components':entries})
assert set(module.select_native(snapshot))=={'future-native','future-raw'}
data=json.loads((root/'tests/fixtures/catalog-legacy-native.json').read_text())
assert len(data['tools'])>=16, 'frozen native coverage unexpectedly narrowed'
fixture_snapshot=SimpleNamespace(data={'components':{key:{'owner':'dotfiles','kind':'software','targets':{'linux-amd64':item}} for key,item in data['tools'].items()}})
assert module.load_fixture(fixture_snapshot,root/'tests/fixtures/catalog-legacy-native.json')==data['tools']
with tempfile.TemporaryDirectory() as directory:
    path=pathlib.Path(directory)/'fixture.json'
    for change in ('missing','extra','empty','path','url','digest'):
        altered=json.loads(json.dumps(data))
        first=next(iter(altered['tools']))
        if change=='missing': del altered['tools'][first]
        elif change=='extra': altered['tools']['unexplained']=altered['tools'][first]
        elif change=='empty': altered['tools']={}
        elif change=='path': altered['tools'][first]['binary']='../outside'
        elif change=='url': altered['tools'][first]['url']='https://untrusted.invalid/binary'
        else: altered['tools'][first]['digest']='sha256:invalid'
        path.write_text(json.dumps(altered))
        try: module.load_fixture(fixture_snapshot,path)
        except ValueError: pass
        else: raise AssertionError('unsafe or incomplete fixture accepted: '+change)
print('PASS: native legacy inventory includes future tools and rejects incomplete or unsafe fixtures')
PY
