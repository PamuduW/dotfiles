#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
script = root / 'scripts/catalog/qualify-docker.py'
assert script.is_file(), 'missing real Docker lifecycle qualification driver'
with tempfile.TemporaryDirectory() as temporary:
    output = pathlib.Path(temporary) / 'result.json'
    for extra in ([], ['--disposable-host']):
        result = subprocess.run(
            [sys.executable, str(script), '/missing-context', '--output', str(output), *extra],
            capture_output=True, text=True, check=False,
        )
        assert result.returncode == 2, result.stderr
        assert not output.exists()
        assert 'Traceback' not in result.stderr
    output.write_text('preserve-existing-evidence')
    result = subprocess.run(
        [sys.executable, str(script), '/missing-context', '--output', str(output), '--disposable-host'],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 2, result.stderr
    assert output.read_text() == 'preserve-existing-evidence'
print('Docker lifecycle preflight preserves this host and existing evidence')
PY
