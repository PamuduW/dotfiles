# shellcheck shell=bash
graphify_fixture() {
	local version="${1:-1.2.3}" uv_version="${2:-0.12.0}" fixture="$TEST_HARNESS_ROOT/catalog-graphify" digest lock_digest
	mkdir -p "$fixture/locks"
	printf 'graphifyy==%s --hash=sha256:%064d\n' "$version" 0 >"$fixture/locks/graphify.txt"
	cat >"$TEST_HARNESS_ROOT/uv" <<'UV'
#!/usr/bin/env bash
set -euo pipefail
printf 'uv:%s\n' "$*" >>"$TEST_COMMAND_LOG"
if [[ "${1:-}" == --version ]]; then echo 'uv __UV_VERSION__'; exit; fi
[[ "${UV_PYTHON_DOWNLOADS:-}" == never ]] || exit 81
case "${1:-}" in
venv)
	prefix="${*: -1}"
	mkdir -p "$prefix/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$prefix/bin/python"
	chmod +x "$prefix/bin/python"
	;;
pip)
	[[ "${2:-}" == sync && " $* " == *' --require-hashes '* ]] || exit 82
	printf 'certs:%s\n' "${UV_SYSTEM_CERTS:-false}" >>"$TEST_COMMAND_LOG"
	if [[ "${TEST_GRAPHIFY_CERT_RETRY:-0}" == 1 && "${UV_SYSTEM_CERTS:-false}" != true ]]; then
		echo 'invalid peer certificate: UnknownIssuer' >&2
		exit 23
	fi
	if [[ "${TEST_GRAPHIFY_SYNC_FAILS:-0}" == 1 ]]; then echo 'frozen sync failed' >&2; exit 74; fi
	lock="${*: -1}"
	version="$(python3 - "$lock" <<'PY'
import pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text().rstrip()+"\n"
match=re.fullmatch(r'graphifyy==([0-9.]+) --hash=sha256:[0-9a-f]{64}\n',text)
if not match: raise SystemExit(1)
print(match[1])
PY
)"
	while (($#)); do
		if [[ "$1" == --python ]]; then prefix="${2%/bin/python}"; break; fi
		shift
	done
	printf '%s\n' '#!/usr/bin/env bash' "echo 'graphify $version'" >"$prefix/bin/graphify"
	chmod +x "$prefix/bin/graphify"
	;;
*) exit 97 ;;
esac
UV
	sed -i "s/__UV_VERSION__/$uv_version/g" "$TEST_HARNESS_ROOT/uv"
	digest="$(sha256sum "$TEST_HARNESS_ROOT/uv")"
	lock_digest="$(sha256sum "$fixture/locks/graphify.txt")"
	printf '%s\n' $'uv\towner\tany\tdotfiles' $'uv\tkind\tany\tsoftware' \
		$'uv\tversion\tany\t'"$uv_version" $'uv\tarchive\tany\traw' $'uv\tbinary\tany\tuv' \
		$'uv\turl\tany\thttps://fixture.invalid/uv' $'uv\tdigest\tany\tsha256:'"${digest%% *}" \
		$'graphify_cli\towner\tany\tdotfiles' $'graphify_cli\tkind\tany\tsoftware' \
		$'graphify_cli\tversion\tany\t'"$version" $'graphify_cli\tarchive\tany\tpython-lock' \
		$'graphify_cli\tpackage\tany\tgraphifyy' $'graphify_cli\tbinary\tany\tbin/graphify' \
		$'graphify_cli\tlock\tany\tlocks/graphify.txt' $'graphify_cli\tdigest\tany\tsha256:'"${lock_digest%% *}" | catalog_fixture_seal "$fixture"
	catalog_fixture_use "$fixture"
	curl() {
		local destination='' url="${*: -1}"
		[[ "$url" == https://fixture.invalid/uv ]] || return 97
		while (($#)); do
			if [[ "$1" == -o ]]; then
				destination="$2"
				break
			fi
			shift
		done
		[[ -n "$destination" ]] || return 97
		cp "$TEST_HARNESS_ROOT/uv" "$destination"
	}
}

graphify_reset() {
	PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
	export PATH
	rm -rf -- "$HOME/.local" "$TEST_FAKE_BIN/uv"
	: >"$TEST_COMMAND_LOG"
	unset TEST_GRAPHIFY_SYNC_FAILS TEST_GRAPHIFY_CERT_RETRY UV_SYSTEM_CERTS
	graphify_fixture 1.2.3 0.12.0
}
