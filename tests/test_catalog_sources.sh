#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
source "$REPO_DIR/scripts/lib/software_catalog.sh"
if [[ -f "$REPO_DIR/scripts/lib/catalog_sources.sh" ]]; then source "$REPO_DIR/scripts/lib/catalog_sources.sh"; fi
if ! declare -F dotfiles_catalog_source_install >/dev/null; then
	echo 'FAIL: exact manager/plugin source adapter is missing' >&2
	exit 1
fi
export FIXTURE_SOURCE_REPO="$TEST_HARNESS_ROOT/source"
mkdir "$FIXTURE_SOURCE_REPO"
/usr/bin/git -C "$FIXTURE_SOURCE_REPO" init -q
printf 'source version one\n' >"$FIXTURE_SOURCE_REPO/nvm.sh"
/usr/bin/git -C "$FIXTURE_SOURCE_REPO" add nvm.sh
/usr/bin/git -C "$FIXTURE_SOURCE_REPO" -c user.name=Fixture -c user.email=fixture@example.invalid -c core.hooksPath=/dev/null commit -qm one
revision_one="$(/usr/bin/git -C "$FIXTURE_SOURCE_REPO" rev-parse HEAD)"
printf 'source version two\n' >"$FIXTURE_SOURCE_REPO/nvm.sh"
/usr/bin/git -C "$FIXTURE_SOURCE_REPO" add nvm.sh
/usr/bin/git -C "$FIXTURE_SOURCE_REPO" -c user.name=Fixture -c user.email=fixture@example.invalid -c core.hooksPath=/dev/null commit -qm two
revision_two="$(/usr/bin/git -C "$FIXTURE_SOURCE_REPO" rev-parse HEAD)"
rm -f -- "$TEST_FAKE_BIN/git"
cat >"$TEST_FAKE_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
for index in "${!args[@]}"; do
	if [[ "${args[index]}" == fetch ]]; then
		printf 'fetch\n' >>"$TEST_COMMAND_LOG"
		[[ "${TEST_SOURCE_FETCH_FAILS:-0}" != 1 ]] || exit 45
		for next in "${!args[@]}"; do
			if [[ "$next" -gt "$index" && "${args[next]}" == origin ]]; then args[next]="$FIXTURE_SOURCE_REPO"; break; fi
		done
	fi
done
exec /usr/bin/git "${args[@]}"
GIT
chmod +x "$TEST_FAKE_BIN/git"
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"
export PATH
source_target() {
	local fixture_key="${3:-nvm}" repository="${4:-nvm-sh/nvm}"
	printf '%s\n' "$fixture_key"$'\towner\tany\tdotfiles' "$fixture_key"$'\tkind\tany\tgit-source' \
		"$fixture_key"$'\tsource\tany\t'"$repository" "$fixture_key"$'\tversion\tany\t'"$1" \
		"$fixture_key"$'\trevision\tany\t'"$2" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-source"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-source"
}
source_target 1.0.0 "$revision_one"
installed="$(dotfiles_catalog_source_install nvm)"
[[ "$(realpath -- "$installed")" == "$installed" ]] || {
	echo 'FAIL: source adapter returned a mutable current symlink' >&2
	exit 1
}
[[ "$(cat "$installed/nvm.sh")" == 'source version one' ]]
[[ "$(/usr/bin/git -C "$installed" rev-parse HEAD)" == "$revision_one" ]]
[[ "$(/usr/bin/git -C "$installed" config --get remote.origin.url)" == https://github.com/nvm-sh/nvm.git ]]
: >"$TEST_COMMAND_LOG"
[[ "$(dotfiles_catalog_source_install nvm)" == "$installed" ]]
[[ ! -s "$TEST_COMMAND_LOG" ]]
source_target 1.1.0 "$revision_two"
installed="$(dotfiles_catalog_source_install nvm)"
[[ "$(cat "$installed/nvm.sh")" == 'source version two' ]]
previous="$(readlink "$(dotfiles_catalog_root nvm)/current")"
source_target 1.0.0 "$revision_one"
if dotfiles_catalog_source_install nvm; then
	echo 'FAIL: source rollback accepted' >&2
	exit 1
fi
[[ "$(readlink "$(dotfiles_catalog_root nvm)/current")" == "$previous" ]]
source_target 1.2.0 "$(printf '%040d' 1)"
export TEST_SOURCE_FETCH_FAILS=1
rc=0
dotfiles_catalog_source_install nvm >/dev/null 2>&1 || rc=$?
[[ "$rc" == 45 && "$(readlink "$(dotfiles_catalog_root nvm)/current")" == "$previous" ]]
unset TEST_SOURCE_FETCH_FAILS
source_target 1.1.0 "$revision_two"
printf 'local edit\n' >>"$installed/nvm.sh"
: >"$TEST_COMMAND_LOG"
if dotfiles_catalog_source_install nvm; then
	echo 'FAIL: modified source was replaced' >&2
	exit 1
fi
[[ "$(tail -n1 "$installed/nvm.sh")" == 'local edit' && ! -s "$TEST_COMMAND_LOG" ]]
source_target 1.1.0 "$revision_two" asdf-golang asdf-community/asdf-golang
plugin="$(dotfiles_catalog_source_install asdf-golang)"
[[ "$(/usr/bin/git -C "$plugin" rev-parse HEAD)" == "$revision_two" ]]
[[ "$(/usr/bin/git -C "$plugin" config --get remote.origin.url)" == https://github.com/asdf-community/asdf-golang.git ]]
: >"$TEST_COMMAND_LOG"
source_target 1.2.0 "$revision_two" asdf-golang other/unverified
if dotfiles_catalog_source_install asdf-golang; then
	echo 'FAIL: source repository substitution accepted' >&2
	exit 1
fi
[[ ! -s "$TEST_COMMAND_LOG" ]]
source_target 1.2.0 main asdf-golang asdf-community/asdf-golang
if dotfiles_catalog_source_install asdf-golang; then
	echo 'FAIL: floating source ref accepted' >&2
	exit 1
fi
[[ ! -s "$TEST_COMMAND_LOG" ]]
printf 'PASS: manager/plugin source pins preserve modified sources and reject rollback/fetch failure\n'
