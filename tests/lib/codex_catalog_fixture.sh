# shellcheck shell=bash
make_codex_fixture() {
	local version="$1" helper="${2:-yes}" reported_version="${3:-$1}" payload="$TEST_HARNESS_ROOT/bundle"
	rm -rf -- "$payload"
	mkdir -p "$payload/bin" "$payload/codex-path" "$payload/codex-resources"
	cat >"$payload/bin/codex" <<'CODEX'
#!/usr/bin/env bash
if ! python3 - "${CODEX_HOME:-$HOME/.codex}/app-server-daemon/settings.json" <<'PY'
import json,sys
try:
    settings=json.load(open(sys.argv[1]))
    assert settings['updater']['autoUpdateEnabled'] is False
except (OSError,ValueError,KeyError,AssertionError):
    raise SystemExit(1)
PY
then : >"$TEST_CODEX_UPDATE_MARKER"; exit 91; fi
CODEX
	printf 'echo "codex-cli %s"\n' "$reported_version" >>"$payload/bin/codex"
	local path
	for path in codex-path/rg codex-resources/bwrap bin/codex-code-mode-host; do
		[[ "$path" != bin/codex-code-mode-host || "$helper" == yes ]] || continue
		printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$payload/$path"
		chmod +x "$payload/$path"
	done
	chmod +x "$payload/bin/codex"
	printf '{"version":"%s","target":"x86_64-unknown-linux-musl","entrypoint":"bin/codex"}\n' "$version" >"$payload/codex-package.json"
	tar -czf "$TEST_HARNESS_ROOT/codex.tgz" -C "$payload" .
	local digest
	digest="$(sha256sum "$TEST_HARNESS_ROOT/codex.tgz")"
	printf '%s\n' $'codex_cli\towner\tany\tdotfiles' $'codex_cli\tkind\tany\tsoftware' \
		$'codex_cli\tversion\tany\t'"$version" $'codex_cli\tarchive\tany\ttar' \
		$'codex_cli\tbinary\tany\tbin/codex' $'codex_cli\turl\tany\thttps://fixture.invalid/codex.tgz' \
		$'codex_cli\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-codex"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-codex"
}
