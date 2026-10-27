#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import importlib.util
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

root = pathlib.Path(sys.argv[1])
path = root / 'scripts/catalog/qualify-vendor-packages.py'
if not path.is_file():
    raise SystemExit('FAIL: missing real vendor-package smoke driver')
sys.dont_write_bytecode = True
sys.path.insert(0, str(root.parent / 'dotfiles-shared/scripts/lib/shared/python'))
from software_catalog import CatalogError
spec = importlib.util.spec_from_file_location('vendor_smoke', path)
vendor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vendor)


def entry(kind='vendor-apt', package='powershell', binary='pwsh', archive='deb'):
    return {
        'owner': 'dotfiles', 'kind': kind, 'blockers': [],
        'discovery': {'archive': archive},
        'targets': {'linux-amd64': {'archive': archive, 'version': '1.2.3',
                    'package': package, 'binary': binary}},
    }


def snapshot():
    return SimpleNamespace(approved=False, data={'components': {
        'powershell': entry(),
        'obsidian': entry('software', 'obsidian', 'obsidian'),
        'docker.future-package': entry(package='docker-future', binary='docker'),
        'distro-managed': entry('distro', 'bash', 'bash'),
        'other-owner': {**entry(), 'owner': 'agentbot'},
        'ordinary-tool': entry('software', 'tool', 'tool', 'tar.gz'),
    }})


def rows():
    return '\n'.join(f'{phase}\t{key}\t{package}\t1.2.3\t' + 'a' * 64 + '\theld'
                     for phase in ('fresh', 'repeat')
                     for key, package in [('obsidian', 'obsidian'), ('powershell', 'powershell')])


class VendorSmoke(unittest.TestCase):
    def test_invalid_context_writes_no_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            output = pathlib.Path(temp) / 'receipt.json'
            result = subprocess.run([sys.executable, str(path), str(output.parent / 'missing'),
                                     '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertFalse(output.exists())

    def test_existing_evidence_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            output = pathlib.Path(temp) / 'receipt.json'
            output.write_text('existing evidence')
            result = subprocess.run([sys.executable, str(path), str(output.parent / 'missing'),
                                     '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(output.read_text(), 'existing evidence')

    def test_inventory_selects_future_vendor_and_software_deb(self):
        selected = vendor.select_packages(snapshot())
        self.assertEqual(set(selected), {'powershell', 'obsidian', 'docker.future-package'})
        self.assertEqual(selected['docker.future-package']['package'], 'docker-future')

    def test_empty_missing_or_unsupported_inventory_cannot_pass(self):
        candidates = [SimpleNamespace(approved=False, data={'components': {}})]
        for mutate in ('missing', 'unsupported', 'duplicate', 'blocked'):
            data = snapshot()
            if mutate == 'missing':
                data.data['components']['powershell']['targets'] = {}
            elif mutate == 'unsupported':
                data.data['components']['powershell']['targets']['linux-amd64']['archive'] = 'zip'
            elif mutate == 'duplicate':
                data.data['components']['obsidian']['targets']['linux-amd64']['package'] = 'powershell'
            else:
                data.data['components']['powershell']['blockers'] = ['not qualified']
            candidates.append(data)
        for data in candidates:
            with self.subTest(data=data), self.assertRaises(CatalogError):
                vendor.select_packages(data)

    def test_observations_require_exact_versions_digest_holds_and_total_phases(self):
        selected = {key: value for key, value in vendor.select_packages(snapshot()).items()
                    if key in {'powershell', 'obsidian'}}
        observed = vendor.parse_observations(rows(), selected, 'a' * 64)
        self.assertEqual(observed['fresh']['powershell'], {
            'package': 'powershell', 'version': '1.2.3', 'receipt_digest': 'a' * 64,
            'hold': True})
        invalid = [rows().split('\n', 1)[1], rows() + '\n' + rows().splitlines()[0],
                   rows().replace('1.2.3', '2.0.0', 1),
                   rows().replace('a' * 64, 'b' * 64, 1),
                   rows().replace('held', 'unheld', 1), rows() + '\nnoise']
        for raw in invalid:
            with self.subTest(raw=raw), self.assertRaises(CatalogError):
                vendor.parse_observations(raw, selected, 'a' * 64)

    def test_application_probes_hold_on_wrong_owner_pipeline_or_missing_window(self):
        selected = vendor.select_packages(snapshot())
        good = ['/usr/bin/pwsh', 'powershell: /usr/bin/pwsh',
                '/usr/bin/obsidian', 'obsidian: /usr/bin/obsidian',
                '{"message":"catalog-ok","total":10}', 'visible-obsidian-window']
        for failed_index, replacement in ((1, 'external: /usr/bin/pwsh'),
                                          (4, '{"message":"wrong","total":10}'),
                                          (5, '')):
            outputs = good.copy()
            outputs[failed_index] = replacement
            with self.subTest(failed_index=failed_index), patch.object(
                    vendor.subprocess, 'check_output', side_effect=outputs):
                with self.assertRaises(CatalogError):
                    vendor.probe_applications(selected, {'HOME': '/tmp/unused'})
        with patch.object(vendor.subprocess, 'check_output', side_effect=good):
            result = vendor.probe_applications(selected, {'HOME': '/tmp/unused'})
        self.assertEqual(result['powershell']['local_pipeline_json'], 'success')
        self.assertEqual(result['obsidian']['xvfb_visible_window'], 'success')

    def test_source_or_context_changes_hold_before_success_receipt(self):
        data = snapshot()
        data.digest = 'a' * 64
        data.data['components'].pop('docker.future-package')
        data.data['sources'] = {'dotfiles': '1' * 40, 'dotfiles-shared': '2' * 40,
                                'agentbot': '3' * 40}
        shared = root.parent / 'dotfiles-shared'
        sources = {'dotfiles': root, 'dotfiles-shared': shared,
                   'agentbot': root.parent / 'agentbot'}
        original = (data, sources, 'a' * 64)
        variants = [
            [original, CatalogError('qualification source revision changed: agentbot')],
            [original, (data, sources, 'b' * 64)],
            [original, original, CatalogError('qualification source revision changed: dotfiles')],
            [original, original, original],
        ]
        with tempfile.TemporaryDirectory() as temp:
            for variant in variants:
                with self.subTest(variant=variant), patch(
                        'catalog_context.load_qualification_context', side_effect=variant), patch.object(
                        vendor.subprocess, 'check_output', return_value=str(shared)), patch.object(
                        vendor.subprocess, 'run', return_value=SimpleNamespace(returncode=1)), patch.object(
                        vendor.platform, 'freedesktop_os_release',
                        return_value={'ID': 'ubuntu', 'VERSION_ID': '24.04'}), patch.object(
                        vendor.platform, 'machine', return_value='x86_64'), patch.object(
                        vendor.os, 'geteuid', return_value=1001), patch.object(
                        vendor.Path, 'is_file', return_value=True), patch.object(
                        vendor.Path, 'exists', return_value=False), patch.dict(
                        vendor.os.environ, {'GITHUB_ACTIONS': 'true'}), patch.object(
                        vendor.tempfile, 'mkdtemp', return_value=temp), patch.object(
                        vendor, 'install_packages', return_value=rows()), patch.object(
                        vendor, 'probe_applications', return_value={'local': 'success'}):
                    if variant is variants[-1]:
                        result = vendor.smoke(pathlib.Path(temp) / 'context')
                        self.assertEqual(result['scope'], 'vendor-package-smoke-only')
                        self.assertIs(result['approved'], False)
                        self.assertIs(result['docker_daemon_qualified'], False)
                        self.assertEqual(result['catalog_digest'], 'a' * 64)
                    else:
                        with self.assertRaises(CatalogError):
                            vendor.smoke(pathlib.Path(temp) / 'context')

    def test_controller_checks_real_state_and_repeat_preserves_receipts(self):
        with tempfile.TemporaryDirectory() as temp:
            fixture = pathlib.Path(temp)
            loader = fixture / 'scripts/lib/installers/load.sh'
            loader.parent.mkdir(parents=True)
            loader.write_text('''
software_catalog_qualification_begin() { SOFTWARE_CATALOG_DIGEST="$TEST_DIGEST"; }
software_catalog_qualification_source() { printf '%s\\n' "$TEST_ROOT"; }
dotfiles_catalog_begin() { :; }
dotfiles_catalog_get() {
    case "$2" in package) printf '%s\\n' "$1";; version) echo 1.2.3;; esac
}
dotfiles_catalog_install_debs() {
    mkdir -p "$HOME/.local/share/dotfiles-catalog"
    local key
    for key in "$@"; do
        printf '%s\\n1.2.3\\n%s\\n' "$key" "$TEST_DIGEST" >"$HOME/.local/share/dotfiles-catalog/$key.apt"
    done
    touch "$HOME/installed"
}
dotfiles_catalog_apt_owned() { [[ "${FAIL_OWNED:-0}" != 1 ]]; }
dpkg-query() {
    [[ "${DPKG_ERROR:-0}" != 1 ]] || return 2
    [[ -f "$HOME/installed" ]] || return 1
    printf '1.2.3'
}
apt-mark() {
    [[ "$1" == showhold && "${FAIL_HOLD:-0}" != 1 ]] || return 0
    printf 'powershell\\nobsidian\\n'
}
sudo() {
    case "$*" in '-n true' | 'apt-get update') return 0;;
    /usr/sbin/policy-rc.d) return 101;; *) return 2;; esac
}
''')
            selected = {key: value for key, value in vendor.select_packages(snapshot()).items()
                        if key in {'powershell', 'obsidian'}}
            context = fixture / 'context'
            context.write_text('{}')
            context_digest = hashlib.sha256(b'{}').hexdigest()
            for failure in (None, 'FAIL_OWNED', 'FAIL_HOLD', 'PREEXISTING', 'CONTEXT_CHANGED', 'DPKG_ERROR'):
                home = fixture / str(failure)
                home.mkdir()
                if failure == 'PREEXISTING':
                    (home / 'installed').touch()
                env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'TEST_ROOT': str(fixture),
                       'TEST_DIGEST': 'a' * 64}
                if failure:
                    env[failure] = '1'
                with self.subTest(failure=failure), patch.object(vendor, 'ROOT', fixture):
                    if failure:
                        with self.assertRaises(subprocess.CalledProcessError):
                            vendor.install_packages(context, selected, env,
                                                    'b' * 64 if failure == 'CONTEXT_CHANGED' else context_digest)
                        if failure in {'CONTEXT_CHANGED', 'DPKG_ERROR'}:
                            self.assertFalse((home / 'installed').exists())
                    else:
                        raw = vendor.install_packages(context, selected, env, context_digest)
                        actual = vendor.parse_observations(raw, selected, 'a' * 64)
                        self.assertEqual(actual['fresh'], actual['repeat'])


unittest.main(argv=['vendor-smoke'], verbosity=2)
PY
