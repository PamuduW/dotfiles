#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
test_harness_report_init

# A real markdownlint-cli2, cspell or mmdc on the machine running the tests
# must never stand in for the fixture.
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"

source "$ROOT/scripts/lib/installers/logging.sh"
# shellcheck source=scripts/lib/installers/npm_cli.sh
source "$ROOT/scripts/lib/installers/npm_cli.sh"

# The native runtime resolver has separate ownership/version regressions.
# Package tests replace that dependency with a fixed local compiler port.
mkdir -p "$TEST_HARNESS_ROOT/runtime/bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo v24.1.0' >"$TEST_HARNESS_ROOT/runtime/bin/node"
chmod +x "$TEST_HARNESS_ROOT/runtime/bin/node"
dotfiles_catalog_npm_runtime() { printf '%s\nnpm\n' "$TEST_HARNESS_ROOT/runtime/bin/node"; }

# Registry installation is mocked at npm ci; the catalog reader and exact
# closure preflight stay real. test_catalog_locks.sh also runs a real npm ci.
serve() {
	SERVED_VERSION="$1"
	SERVED_REPORTED="${2:-$1}"
	local fixture="$TEST_HARNESS_ROOT/catalog-npm" row key label package binary digest
	mkdir -p "$fixture/locks"
	: >"$fixture/input-rows"
	for row in "${NPM_CLI_TOOLS[@]}"; do
		IFS='|' read -r key label package binary <<<"$row"
		python3 - "$fixture/locks/$key.json" "$package" "$SERVED_VERSION" <<'PYLOCK'
import base64,json,pathlib,sys
path,package,version=sys.argv[1:]
lock={'lockfileVersion':3,'packages':{
    '':{'name':'fixture','version':'0.0.0','dependencies':{package:version}},
    'node_modules/'+package:{'version':version,
        'resolved':'https://registry.npmjs.org/'+package+'/-/'+package.rsplit('/',1)[-1]+'-'+version+'.tgz',
        'integrity':'sha512-'+base64.b64encode(bytes(64)).decode()}}}
pathlib.Path(path).write_text(json.dumps(lock))
PYLOCK
		digest="$(sha256sum "$fixture/locks/$key.json")"
		printf '%s\n' "$key"$'\towner\tany\tdotfiles' "$key"$'\tkind\tany\tsoftware' \
			"$key"$'\tversion\tany\t'"$SERVED_VERSION" "$key"$'\tarchive\tany\tnpm-lock' \
			"$key"$'\tpackage\tany\t'"$package" "$key"$'\tbinary\tany\tnode_modules/.bin/'"$binary" \
			"$key"$'\tlock\tany\tlocks/'"$key.json" "$key"$'\tdigest\tany\tsha256:'"${digest%% *}" >>"$fixture/input-rows"
	done
	catalog_fixture_seal "$fixture" <"$fixture/input-rows"
	catalog_fixture_use "$fixture"
	npm() {
		[[ "$1" == ci && " $* " == *' --ignore-scripts '* && " $* " == *' --omit=dev '* &&
			" $* " == *' --no-audit '* && " $* " == *' --no-fund '* && "${PUPPETEER_SKIP_DOWNLOAD:-}" == 1 ]] || return 97
		local prefix='' key binary package candidate_package version row label
		while (($#)); do
			if [[ "$1" == --prefix ]]; then
				prefix="$2"
				break
			fi
			shift
		done
		local -a pin=()
		mapfile -t pin < <(
			python3 - "$prefix/package.json" "$prefix/package-lock.json" <<'PYPIN'
import json,sys
package,lock=(json.load(open(p)) for p in sys.argv[1:])
assert package['dependencies']==lock['packages']['']['dependencies']
name,version=next(iter(package['dependencies'].items()))
assert lock['packages']['node_modules/'+name]['version']==version
print(name);print(version)
PYPIN
		)
		[[ "${#pin[@]}" == 2 ]] || return 97
		package="${pin[0]}" version="${pin[1]}"
		printf 'ci:%s@%s\n' "$package" "$version" >>"$TEST_URL_LOG"
		[[ "${NPM_INSTALL_FAILS:-0}" != 1 ]] || return 1
		for row in "${NPM_CLI_TOOLS[@]}"; do
			IFS='|' read -r key label candidate_package binary <<<"$row"
			[[ "$package" == "$candidate_package" ]] || continue
			mkdir -p "$prefix/node_modules/.bin"
			printf '%s\n' '#!/usr/bin/env bash' \
				'if [[ "${1:-}" == --env ]]; then echo "${PUPPETEER_EXECUTABLE_PATH:-unset}"; exit; fi' \
				'if [[ "${1:-}" == --runtime ]]; then node --version; exit; fi' \
				"echo '$SERVED_REPORTED'" >"$prefix/node_modules/.bin/$binary"
			chmod +x "$prefix/node_modules/.bin/$binary"
			return
		done
		return 97
	}
}

reset_home() {
	rm -rf -- "$HOME/.local" "$TEST_URL_LOG"
	mkdir -p "$(dirname -- "$TEST_URL_LOG")"
	: >"$TEST_URL_LOG"
	unset NPM_INSTALL_FAILS
}

own() {
	serve "$2"
	install_npm_cli "$1" >/dev/null
	: >"$TEST_URL_LOG"
}

test_fresh_install_links_a_wrapper_into_its_own_prefix() (
	local row key label binary package
	for row in "${NPM_CLI_TOOLS[@]}"; do
		IFS='|' read -r key label package binary <<<"$row"
		reset_home
		binary="$(npm_cli_field "$key" binary)"
		package="$(npm_cli_field "$key" package)"
		serve 1.2.3

		install_npm_cli "$key" >/dev/null || return 1
		[[ "$("$HOME/.local/bin/$binary" --runtime)" == v24.1.0 ]] || return 1

		[[ -L "$HOME/.local/bin/$binary" ]] || return 1
		[[ "$(readlink -f "$HOME/.local/bin/$binary")" == "$HOME/.local/share/dotfiles-catalog/$key/releases/"*/command ]] || return 1
		[[ "$("$HOME/.local/bin/$binary")" == 1.2.3 ]] || return 1
		[[ "$(<"$HOME/.local/share/dotfiles/$key.version")" == 1.2.3 ]] || return 1
		grep -Fqx "ci:${package}@1.2.3" "$TEST_URL_LOG" || return 1
		[[ "$(find "$HOME/.local/share/dotfiles-catalog/$key/releases" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]] || return 1
		npm_cli_is_dotfiles_owned "$key" || return 1
	done
)

test_mermaid_wrapper_uses_the_chrome_headless_shell() (
	reset_home
	serve 12.0.0
	install_npm_cli mermaid_cli >/dev/null || return 1
	[[ "$("$HOME/.local/bin/mmdc" --env)" == unset ]] || return 1

	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' >"$HOME/.local/bin/chrome-headless-shell"
	chmod +x "$HOME/.local/bin/chrome-headless-shell"
	[[ "$("$HOME/.local/bin/mmdc" --env)" == "$HOME/.local/bin/chrome-headless-shell" ]] || return 1
	[[ "$(PUPPETEER_EXECUTABLE_PATH=/opt/chrome "$HOME/.local/bin/mmdc" --env)" == /opt/chrome ]] || return 1

	# The other tools' wrappers set nothing.
	serve 10.3.6
	install_npm_cli cspell >/dev/null || return 1
	! grep -q PUPPETEER "$HOME/.local/share/dotfiles-catalog/cspell/current/command"
)

test_a_failed_npm_install_leaves_nothing() (
	reset_home
	serve 1.2.3
	NPM_INSTALL_FAILS=1
	! install_npm_cli cspell >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/cspell" && ! -e "$HOME/.local/share/dotfiles-catalog/cspell/current" ]] || return 1
	! compgen -G "$HOME/.local/share/dotfiles-catalog/cspell/releases/.staging-*" >/dev/null
)

test_a_command_reporting_another_version_is_refused() (
	reset_home
	serve 1.2.3 9.9.9
	! install_npm_cli cspell >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/cspell" && ! -e "$HOME/.local/share/dotfiles/cspell.version" ]]
)

test_an_external_command_is_preserved_even_when_forced() (
	reset_home
	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'echo 0.1.0' >"$HOME/.local/bin/cspell"
	chmod +x "$HOME/.local/bin/cspell"
	serve 1.2.3

	DOTFILES_FORCE_REINSTALL=1 install_npm_cli cspell >/dev/null 2>&1 || return 1
	[[ ! -L "$HOME/.local/bin/cspell" && ! -s "$TEST_URL_LOG" ]] || return 1
	[[ "$(npm_cli_installed_tag cspell)" == 0.1.0 ]]
)

test_an_owned_command_is_skipped_unless_forced() (
	reset_home
	own cspell 1.2.3
	install_npm_cli cspell >/dev/null || return 1
	[[ ! -s "$TEST_URL_LOG" ]] || return 1
	DOTFILES_FORCE_REINSTALL=1 install_npm_cli cspell >/dev/null || return 1
	grep -Fqx 'ci:cspell@1.2.3' "$TEST_URL_LOG"
)

test_update_replaces_an_owned_prefix_and_its_stamp() (
	reset_home
	own markdownlint_cli2 0.23.2
	upgrade_result_set() { printf '%s\n' "$1" >"$TEST_HARNESS_ROOT/result"; }
	serve 0.23.3

	upgrade_markdownlint_cli2 >/dev/null || return 1
	[[ "$(npm_cli_installed_tag markdownlint_cli2)" == 0.23.3 ]] || return 1
	[[ "$(<"$HOME/.local/share/dotfiles/markdownlint_cli2.version")" == 0.23.3 ]] || return 1
	[[ "$(<"$TEST_HARNESS_ROOT/result")" == updated ]] || return 1
	! compgen -G "$HOME/.local/share/dotfiles-catalog/markdownlint_cli2/.current.*" >/dev/null || return 1

	upgrade_markdownlint_cli2 >/dev/null || return 1
	[[ "$(<"$TEST_HARNESS_ROOT/result")" == already-current ]]
)

test_update_without_approved_pin_preserves_the_command() (
	reset_home
	own cspell 1.2.3
	TEST_APPROVED_CATALOG="$TEST_HARNESS_ROOT/missing-npm-catalog"

	! upgrade_cspell >/dev/null 2>&1 || return 1
	[[ "$(npm_cli_installed_tag cspell)" == 1.2.3 ]]
)

test_update_check_reports_installed_available_and_action() (
	reset_home
	local row
	serve 12.0.0
	row="$(check_mermaid_cli || true)"
	[[ "$row" == 'Mermaid CLI|not installed|12.0.0|skip' ]] || return 1

	own mermaid_cli 11.0.0
	serve 12.0.0
	row="$(check_mermaid_cli)" || return 1
	[[ "$row" == 'Mermaid CLI|11.0.0|12.0.0|upgrade' ]] || return 1

	rm -f -- "$HOME/.local/share/dotfiles-catalog/mermaid_cli/current/.catalog-receipt"
	row="$(check_mermaid_cli || true)"
	[[ "$row" == 'Mermaid CLI|external installation|12.0.0|external' ]]
)

test_wrappers_route_to_each_tool() (
	local name
	for name in check_markdownlint_cli2 check_cspell check_mermaid_cli \
		upgrade_markdownlint_cli2 upgrade_cspell upgrade_mermaid_cli; do
		declare -F "$name" >/dev/null || return 1
	done
)

expect_success 'each npm CLI installs into its own prefix behind a linked wrapper' test_fresh_install_links_a_wrapper_into_its_own_prefix
expect_success 'the Mermaid CLI wrapper uses the Chrome headless shell unless told otherwise' test_mermaid_wrapper_uses_the_chrome_headless_shell
expect_success 'a failed npm install leaves nothing behind' test_a_failed_npm_install_leaves_nothing
expect_success 'a command reporting another version is refused' test_a_command_reporting_another_version_is_refused
expect_success 'an external command is preserved, forced or not' test_an_external_command_is_preserved_even_when_forced
expect_success 'an owned command is skipped unless forced, then reinstalled' test_an_owned_command_is_skipped_unless_forced
expect_success 'update replaces an owned prefix and its stamp' test_update_replaces_an_owned_prefix_and_its_stamp
expect_success 'update without an approved pin preserves the command' test_update_without_approved_pin_preserves_the_command
expect_success 'update check reports installed, available and action' test_update_check_reports_installed_available_and_action

expect_success 'per-tool wrappers exist for the update registry' test_wrappers_route_to_each_tool

finish_tests
