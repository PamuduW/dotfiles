#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/software_catalog.sh"
export TEST_CODEX_UPDATE_MARKER="$TEST_HARNESS_ROOT/automatic-update"
mkdir -p "$HOME/.codex/app-server-daemon"
printf '%s\n' 'model = "keep-user-model"' >"$HOME/.codex/config.toml"
printf '%s\n' '{"remoteControlEnabled":true,"updater":{"autoUpdateEnabled":true,"updateIntervalMinutes":23},"custom":{"keep":"value"}}' >"$HOME/.codex/app-server-daemon/settings.json"
source "$TEST_DIR/lib/codex_catalog_fixture.sh"
curl() {
	printf 'download\n' >>"$TEST_HARNESS_ROOT/downloads"
	while (($#)); do
		if [[ "$1" == -o ]]; then
			cp "$TEST_HARNESS_ROOT/codex.tgz" "$2"
			return
		fi
		shift
	done
	return 1
}
uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; -r) echo fixture ;; esac }
make_codex_fixture 1.2.3
dotfiles_catalog_install codex_cli
[[ ! -e "$TEST_CODEX_UPDATE_MARKER" ]]
[[ "$("$HOME/.local/bin/codex" --version)" == 'codex-cli 1.2.3' ]]
python3 - "$HOME/.codex/app-server-daemon/settings.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
assert data=={'remoteControlEnabled':True,'updater':{'autoUpdateEnabled':False,'updateIntervalMinutes':23},'custom':{'keep':'value'}}
PY
[[ "$(cat "$HOME/.codex/config.toml")" == 'model = "keep-user-model"' ]]
make_codex_fixture 1.2.4 no
if dotfiles_catalog_install codex_cli; then
	echo 'FAIL: incomplete Codex package replaced the working bundle' >&2
	exit 1
fi
[[ "$("$HOME/.local/bin/codex" --version)" == 'codex-cli 1.2.3' ]]
previous="$(readlink "$HOME/.local/share/dotfiles-catalog/codex_cli/current")"
before="$(wc -l <"$TEST_HARNESS_ROOT/downloads")"
printf 'invalid user JSON\n' >"$HOME/.codex/app-server-daemon/settings.json"
if DOTFILES_FORCE_REINSTALL=1 dotfiles_catalog_install codex_cli; then
	echo 'FAIL: malformed daemon settings were overwritten' >&2
	exit 1
fi
[[ "$(readlink "$HOME/.local/share/dotfiles-catalog/codex_cli/current")" == "$previous" ]]
[[ "$(cat "$HOME/.codex/app-server-daemon/settings.json")" == 'invalid user JSON' ]]
[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
[[ ! -e "$TEST_CODEX_UPDATE_MARKER" ]]
make_codex_fixture 1.2.3
# The daemon parses the complete known schema before honoring false. A bad
# neighboring setting must not make an apparently disabled updater default on.
for invalid in \
	'{"updater":{"autoUpdateEnabled":false,"updateIntervalMinutes":0}}' \
	'{"updater":{"autoUpdateEnabled":false,"updateIntervalMinutes":true}}' \
	'{"updater":{"autoUpdateEnabled":false},"remoteControlEnabled":"yes"}' \
	'{"updater":{"autoUpdateEnabled":false},"featureOverrides":{"test":1}}' \
	'{"updater":{"autoUpdateEnabled":false},"shutdownGraceSeconds":301}'; do
	printf '%s\n' "$invalid" >"$HOME/.codex/app-server-daemon/settings.json"
	if DOTFILES_FORCE_REINSTALL=1 dotfiles_catalog_install codex_cli; then
		echo 'FAIL: invalid daemon schema bypassed updater preflight' >&2
		exit 1
	fi
	[[ "$(cat "$HOME/.codex/app-server-daemon/settings.json")" == "$invalid" ]]
	[[ "$(wc -l <"$TEST_HARNESS_ROOT/downloads")" == "$before" ]]
done
printf 'invalid user JSON\n' >"$HOME/.codex/app-server-daemon/settings.json"
status="$(dotfiles_catalog_check codex_cli 2>/dev/null || true)"
[[ "$status" == 'codex_cli|installed|1.2.3|blocked' ]]
[[ ! -e "$TEST_CODEX_UPDATE_MARKER" ]] || {
	echo 'FAIL: read-only status executed Codex with an unverifiable updater control' >&2
	exit 1
}
[[ "$(cat "$HOME/.codex/app-server-daemon/settings.json")" == 'invalid user JSON' ]]
printf 'PASS: complete Codex bundle requires updater suppression before execution and preserves user settings\n'
