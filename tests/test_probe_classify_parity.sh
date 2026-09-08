#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# The probe classifications exist twice while ADR-0001 stage two is under way:
# in Bash (scripts/lib/components/probes.sh) and in Python
# (scripts/lib/shared/python/probe_classify.py). Until the Bash callers are
# switched over, the two must agree on every state.
#
# This is the same method the renderer migration used, and it is what made those
# ports verifiable rather than hopeful. The states below are the ones the
# clean-machine history names, plus the edges each reading has.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1

if ! command -v python3 >/dev/null 2>&1; then
	printf 'ok - probe classification parity skipped; python3 unavailable\n'
	exit 0
fi

# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/components/probes.sh"

PY_DIR="$REPO_DIR/scripts/lib/shared/python"
failures=0

compare() {
	local label="$1" bash_out="$2" py_out="$3"
	if [[ "$bash_out" == "$py_out" ]]; then
		return 0
	fi
	printf '   %s\n     bash:   %s\n     python: %s\n' "$label" "$bash_out" "$py_out" >&2
	failures=$((failures + 1))
}

py() {
	python3 -c "
import sys
sys.path.insert(0, '$PY_DIR')
import probe_classify as pc
print($1)
"
}

test_portainer_parity() {
	local docker rc name
	for docker in 0 1; do
		for rc in 0 1 124; do
			for name in '' portainer other; do
				local want got
				want="$(_comp_classify_portainer "$docker" "$rc" "$name")"
				got="$(py "pc.portainer(docker_present=bool($docker), rc=$rc, name='$name')")"
				compare "portainer docker=$docker rc=$rc name='$name'" "$want" "$got"
			done
		done
	done
	((failures == 0))
}

test_codex_parity() {
	local state rc
	local before=$failures
	for state in standalone standalone-not-on-path external standalone-shadowed absent unknown-future; do
		for rc in 0 124; do
			local want got
			want="$(_comp_classify_codex_cli "$state" /x/codex '0.153.4' "$rc")"
			got="$(py "pc.codex_cli(state='$state', path='/x/codex', version='0.153.4', rc=$rc)")"
			compare "codex state=$state rc=$rc" "$want" "$got"
			# and with no version, so the path fallback is compared too
			want="$(_comp_classify_codex_cli "$state" /x/codex '' "$rc")"
			got="$(py "pc.codex_cli(state='$state', path='/x/codex', version='', rc=$rc)")"
			compare "codex state=$state rc=$rc no-version" "$want" "$got"
		done
	done
	((failures == before))
}

test_package_count_parity() {
	local before=$failures
	local -a wanted
	local -A installed
	local want got

	wanted=('dnsutils|bind9-dnsutils' 'curl')
	installed=(["bind9-dnsutils"]=1 [curl]=1)
	want="$(_comp_missing_package_count wanted installed)"
	got="$(py "pc.missing_package_count(['dnsutils|bind9-dnsutils','curl'], {'bind9-dnsutils','curl'})")"
	compare 'packages rename-fallback' "$want" "$got"

	installed=([curl]=1)
	want="$(_comp_missing_package_count wanted installed)"
	got="$(py "pc.missing_package_count(['dnsutils|bind9-dnsutils','curl'], {'curl'})")"
	compare 'packages one-missing' "$want" "$got"

	installed=()
	want="$(_comp_missing_package_count wanted installed)"
	got="$(py "pc.missing_package_count(['dnsutils|bind9-dnsutils','curl'], set())")"
	compare 'packages none-installed' "$want" "$got"

	wanted=()
	want="$(_comp_missing_package_count wanted installed)"
	got="$(py "pc.missing_package_count([], set())")"
	compare 'packages empty-list' "$want" "$got"
	((failures == before))
}

test_apt_classification_parity() {
	local before=$failures counts want got
	for counts in '0 0' '53 0' '53 2' '1 1'; do
		# shellcheck disable=SC2086
		set -- $counts
		want="$(_comp_classify_apt_packages "$1" "$2" 'apt packages')"
		got="$(py "pc.apt_packages(package_count=$1, missing=$2, missing_label='apt packages')")"
		compare "apt count=$1 missing=$2" "$want" "$got"
	done
	((failures == before))
}

test_version_parity() {
	local before=$failures want got
	local -a cases=(
		"Go|go||0|go1.23.4||"
		"Go|go|/usr/bin/go|124|||"
		"Go|go|/usr/bin/go|0|go1.23.4||"
		"Go|go|/usr/bin/go|0|go version go1.23.4 linux/amd64|go[0-9.]+|"
		"Go|go|/usr/bin/go|0|unexpected output|go[0-9.]+|"
		"Node|node|/usr/bin/node|0|v22.1.0||node "
		"Go|go|/usr/bin/go|1|go1.23.4||"
	)
	local row
	for row in "${cases[@]}"; do
		IFS='|' read -r ml tl binary rc raw extract prefix <<<"$row"
		want="$(_comp_classify_version "$ml" "$tl" "$binary" "$rc" "$raw" "$extract" "$prefix")"
		got="$(py "pc.version(missing_label='$ml', timeout_label='$tl', binary='$binary', rc=$rc, raw='$raw', extract='$extract', prefix='$prefix')")"
		compare "version [$row]" "$want" "$got"
	done
	((failures == before))
}

test_go_parity() {
	local before=$failures want got row
	local -a cases=(
		"1|0|go version go1.23.4 linux/amd64|0|0|"
		"1|124||1|0|golang 1.22.0"
		"1|0|unexpected output|1|0|golang 1.22.0"
		"1|0|unexpected output|0|0|"
		"0|0||1|0|golang system"
		"0|0||1|0|"
		"0|0||1|124|"
		"0|0||0|0|"
	)
	for row in "${cases[@]}"; do
		IFS='|' read -r gp grc graw ap arc araw <<<"$row"
		want="$(_comp_classify_go "$gp" "$grc" "$graw" "$ap" "$arc" "$araw")"
		got="$(py "pc.go(go_present=bool($gp), go_rc=$grc, go_raw='$graw', asdf_present=bool($ap), asdf_rc=$arc, asdf_raw='$araw')")"
		compare "go [$row]" "$want" "$got"
	done
	((failures == before))
}

check 'portainer classification agrees across 18 states' test_portainer_parity
check 'codex classification agrees across every state and both statuses' test_codex_parity
check 'package counting agrees on renames and absences' test_package_count_parity
check 'apt classification agrees on every count pair' test_apt_classification_parity
check 'version classification agrees across its edges' test_version_parity
check 'go classification agrees across both sources' test_go_parity

test_harness_cleanup
finish_tests
