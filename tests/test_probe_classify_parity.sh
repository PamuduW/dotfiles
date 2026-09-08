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
		want="$(_comp_classify_apt_packages "$1" "$2" 'apt packages' "$1 apt packages")"
		got="$(py "pc.apt_packages(package_count=$1, missing=$2, missing_label='apt packages', clean_detail='$1 apt packages')")"
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

test_git_credential_parity() {
	local before=$failures want got row
	local -a cases=(
		"store|true|on-demand|check|true"
		"|true|on-demand|check|true"
		"store|false|on-demand|check|true"
		"store|true|always|check|true"
		"store|true|on-demand||true"
		"store|true|on-demand|check|false"
		"|||||"
	)
	for row in "${cases[@]}"; do
		IFS='|' read -r helper recurse fetch push summary <<<"$row"
		want="$(_comp_classify_git_credential "$helper" "$recurse" "$fetch" "$push" "$summary")"
		got="$(py "pc.git_credential(helper='$helper', recurse='$recurse', fetch='$fetch', push='$push', summary='$summary')")"
		compare "git_credential [$row]" "$want" "$got"
	done
	((failures == before))
}

# Production reads through the batch front end, not through the functions above,
# so the transport is compared too: one process, one line in, one line out, in
# order. The cases include the two the encoding could lose -- a trailing empty
# field, and a value carrying a newline.
test_batch_transport_parity() {
	local before=$failures
	local fs=$'\x1f'
	local -a requests=() wanted=()
	local -a got=()
	local i

	requests+=("portainer${fs}1${fs}1${fs}")
	wanted+=("$(_comp_classify_portainer 1 1 '')")

	requests+=("version${fs}Go${fs}go${fs}/usr/bin/go${fs}0${fs}go version go1.23.4${fs}go[0-9.]+${fs}")
	wanted+=("$(_comp_classify_version Go go /usr/bin/go 0 'go version go1.23.4' 'go[0-9.]+' '')")

	requests+=("codex_cli${fs}standalone-not-on-path${fs}/x/codex${fs}${fs}0")
	wanted+=("$(_comp_classify_codex_cli standalone-not-on-path /x/codex '' 0)")

	# git config --get-all returns one line per helper; the encoding carries the
	# newline rather than truncating the value.
	requests+=("git_credential${fs}store"$'\x1e'"cache${fs}true${fs}on-demand${fs}check${fs}true")
	wanted+=("$(_comp_classify_git_credential $'store\ncache' true on-demand check true)")

	requests+=("apt${fs}1${fs}apt packages${fs}2 apt packages${fs}2${fs}dnsutils|bind9-dnsutils${fs}curl${fs}bind9-dnsutils${fs}curl")
	wanted+=('installed|2 apt packages')

	requests+=("apt${fs}1${fs}apt packages${fs}2 apt packages${fs}2${fs}dnsutils|bind9-dnsutils${fs}curl${fs}curl")
	wanted+=('missing|1 of 2 apt packages not installed')

	# No catalog to read: the reading owns that line too, so the probe has one
	# exit rather than an early printf beside a classification.
	requests+=("apt${fs}0${fs}packages${fs}${fs}0")
	wanted+=('missing|packages.txt not found')

	mapfile -t got < <(printf '%s\n' "${requests[@]}" |
		PYTHONDONTWRITEBYTECODE=1 python3 "$PY_DIR/probe_classify.py")

	if ((${#got[@]} != ${#wanted[@]})); then
		printf '   batch returned %d lines for %d requests\n' "${#got[@]}" "${#wanted[@]}" >&2
		failures=$((failures + 1))
		return 1
	fi
	for i in "${!wanted[@]}"; do
		compare "batch request $i" "${wanted[$i]}" "${got[$i]}"
	done
	((failures == before))
}

# The fallback path answers the same requests when python3 is not there yet.
test_bash_fallback_matches_batch() {
	local before=$failures
	local fs=$'\x1f'
	local -a requests=() python_results=() bash_results=()
	local i

	requests=(
		"version${fs}Node${fs}node${fs}/usr/bin/node${fs}0${fs}v22.1.0${fs}${fs}node "
		"version${fs}Go${fs}go${fs}${fs}0${fs}${fs}${fs}"
		"go${fs}1${fs}0${fs}unexpected output${fs}1${fs}0${fs}golang 1.22.0"
		"portainer${fs}0${fs}0${fs}"
		"apt${fs}1${fs}Python packages${fs}4 apt packages; python3 pip venv ready${fs}4${fs}python3${fs}python3-pip${fs}python3-venv${fs}python3-pil${fs}python3${fs}python3-pip${fs}python3-venv"
		"apt${fs}0${fs}packages${fs}${fs}0"
	)

	mapfile -t python_results < <(printf '%s\n' "${requests[@]}" |
		PYTHONDONTWRITEBYTECODE=1 python3 "$PY_DIR/probe_classify.py")
	_comp_classify_resolve requests bash_results python3-unavailable

	if ((${#bash_results[@]} != ${#python_results[@]})); then
		printf '   fallback returned %d lines for %d requests\n' \
			"${#bash_results[@]}" "${#python_results[@]}" >&2
		failures=$((failures + 1))
		return 1
	fi
	for i in "${!python_results[@]}"; do
		compare "fallback request $i" "${bash_results[$i]}" "${python_results[$i]}"
	done
	((failures == before))
}

test_remaining_readings_parity() {
	local before=$failures want got row
	local name email present count ver
	local -a cases

	# name|bash arguments (| separated); the Python call is built alongside it.
	for row in \
		'git_identity|Ada Lovelace|ada@example.com' \
		'git_identity|Ada Lovelace|' \
		'git_identity||ada@example.com' \
		'git_identity||'; do
		IFS='|' read -r _ name email <<<"$row"
		want="$(_comp_classify_git_identity "$name" "$email")"
		got="$(py "pc.git_identity(name='$name', email='$email')")"
		compare "git_identity [$row]" "$want" "$got"
	done

	local p i v
	for p in 0 1; do
		for i in 0 1; do
			for v in 0 1; do
				want="$(_comp_classify_python_runtime "$p" "$i" "$v")"
				got="$(py "pc.python_runtime(python3_present=bool($p), pip_ok=bool($i), venv_ok=bool($v))")"
				compare "python_runtime $p$i$v" "$want" "$got"
			done
		done
	done

	local found rc owned
	for found in 0 1; do
		for rc in 0 1 124; do
			for owned in 0 1; do
				want="$(_comp_classify_owned_cli boost 'boost cli' ' (Dotfiles managed)' ' (external)' \
					"$found" "$rc" 'boost v0.13.12' /x/boost "$owned")"
				got="$(py "pc.owned_cli(missing_label='boost', timeout_label='boost cli', owned_suffix=' (Dotfiles managed)', external_suffix=' (external)', found=bool($found), rc=$rc, version='boost v0.13.12', path='/x/boost', owned=bool($owned))")"
				compare "owned_cli boost found=$found rc=$rc owned=$owned" "$want" "$got"
				# and with no version, so the path fallback is compared too
				want="$(_comp_classify_owned_cli graphify 'graphify cli' ' (uv)' '' \
					"$found" "$rc" '' /x/graphify "$owned")"
				got="$(py "pc.owned_cli(missing_label='graphify', timeout_label='graphify cli', owned_suffix=' (uv)', external_suffix='', found=bool($found), rc=$rc, version='', path='/x/graphify', owned=bool($owned))")"
				compare "owned_cli graphify found=$found rc=$rc owned=$owned no-version" "$want" "$got"
			done
		done
	done

	cases=('1|210|1.400' '1|0|installed' '0||')
	for row in "${cases[@]}"; do
		IFS='|' read -r present count ver <<<"$row"
		want="$(_comp_classify_monaspace_fonts "$present" "$count" "$ver")"
		got="$(py "pc.monaspace_fonts(present=bool($present), count='$count', version='$ver')")"
		compare "monaspace [$row]" "$want" "$got"
	done

	for present in 0 1; do
		want="$(_comp_classify_ssh_key "$present")"
		got="$(py "pc.ssh_key(present=bool($present))")"
		compare "ssh_key present=$present" "$want" "$got"
	done

	local missing
	for missing in 0 1 8; do
		want="$(_comp_classify_stow_targets "$missing")"
		got="$(py "pc.stow_targets(missing=$missing)")"
		compare "stow_targets missing=$missing" "$want" "$got"
	done

	local systemd append
	for present in 0 1; do
		for systemd in 0 1; do
			for append in 0 1; do
				want="$(_comp_classify_wsl_conf "$present" "$systemd" "$append")"
				got="$(py "pc.wsl_conf(present=bool($present), systemd=bool($systemd), append_windows_path=bool($append))")"
				compare "wsl_conf $present$systemd$append" "$want" "$got"
			done
		done
	done

	((failures == before))
}

check 'portainer classification agrees across 18 states' test_portainer_parity
check 'codex classification agrees across every state and both statuses' test_codex_parity
check 'package counting agrees on renames and absences' test_package_count_parity
check 'apt classification agrees on every count pair' test_apt_classification_parity
check 'version classification agrees across its edges' test_version_parity
check 'go classification agrees across both sources' test_go_parity
check 'git credential classification agrees' test_git_credential_parity
check 'every remaining reading agrees across its states' test_remaining_readings_parity
check 'the batched transport returns the same readings, in order' test_batch_transport_parity
check 'the Bash fallback answers the same batch' test_bash_fallback_matches_batch

test_harness_cleanup
finish_tests
