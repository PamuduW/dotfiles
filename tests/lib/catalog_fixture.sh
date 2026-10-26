# shellcheck shell=bash
# Seal a table supplied on stdin, including lock files already under directory.
catalog_fixture_seal() {
	local directory="$1"
	mkdir -p "$directory"
	cat >"$directory/rows"
	python3 - "$directory" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); raw=json.dumps({'fixture':'approved adapter fixture'}).encode()
p.joinpath('software.json').write_bytes(raw);h=hashlib.sha256(raw).hexdigest()
table='#software-catalog-v1\t'+h+'\n'+p.joinpath('rows').read_text()
p.joinpath('software.tsv').write_text(table);p.joinpath('approval.json').write_text('{}')
p.joinpath('approval').write_text('software-approved-v1\n'+h+'\n'+hashlib.sha256(table.encode()).hexdigest()+'\n'+hashlib.sha256(b'{}').hexdigest()+'\n')
PY
}

# Adapter/orchestration unit tests mock the shared approved-Git boundary.
# Production provenance is exercised by the separate freezer regression tests.
catalog_fixture_use() {
	TEST_APPROVED_CATALOG="$1"
	# Each explicit fixture selection starts a new mocked catalog operation.
	_DOTFILES_CATALOG_OPERATION_PID=''
	SOFTWARE_CATALOG_REVISION="$(printf '%040d' 0)"
	export SOFTWARE_CATALOG_REVISION
	software_catalog_begin() {
		software_catalog_load "$TEST_APPROVED_CATALOG"
	}
	software_catalog_load "$TEST_APPROVED_CATALOG"
}

catalog_fixture_load() {
	local directory="${TEST_HARNESS_ROOT:?}/approved-catalog"
	catalog_fixture_seal "$directory" </dev/null
	# shellcheck source=scripts/lib/software_catalog.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)/software_catalog.sh"
	catalog_fixture_use "$directory"
}
