#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

# A real markdownlint-cli2, cspell or mmdc on the machine running the tests
# must never stand in for the fixture.
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"

source "$ROOT/scripts/lib/installers/logging.sh"
# shellcheck source=scripts/lib/installers/npm_cli.sh
source "$ROOT/scripts/lib/installers/npm_cli.sh"

# serve <version> [reported-version]: npm's registry and install, faked. The
# installed command prints the reported version (default <version>).
serve() {
	SERVED_VERSION="$1"
	SERVED_REPORTED="${2:-$1}"
	npm() {
		case "$1" in
		view)
			[[ -n "$SERVED_VERSION" ]] || return 1
			printf '%s\n' "$SERVED_VERSION"
			;;
		install)
			local prefix='' spec="${*: -1}" key binary
			while (($#)); do
				[[ "$1" == --prefix ]] && prefix="$2"
				shift
			done
			printf 'install:%s\n' "$spec" >>"$TEST_URL_LOG"
			[[ "${NPM_INSTALL_FAILS:-0}" != 1 ]] || return 1
			for key in markdownlint_cli2 cspell mermaid_cli; do
				[[ "$spec" == "$(npm_cli_field "$key" package)@"* ]] || continue
				binary="$(npm_cli_field "$key" binary)"
				mkdir -p "$prefix/node_modules/.bin"
				printf '%s\n' '#!/usr/bin/env bash' \
					'if [[ "${1:-}" == --env ]]; then echo "${PUPPETEER_EXECUTABLE_PATH:-unset}"; exit; fi' \
					"echo '$SERVED_REPORTED'" >"$prefix/node_modules/.bin/$binary"
				chmod +x "$prefix/node_modules/.bin/$binary"
			done
			;;
		*) return 1 ;;
		esac
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
	local key binary package
	for key in markdownlint_cli2 cspell mermaid_cli; do
		reset_home
		binary="$(npm_cli_field "$key" binary)"
		package="$(npm_cli_field "$key" package)"
		serve 1.2.3

		install_npm_cli "$key" >/dev/null || return 1

		[[ -L "$HOME/.local/bin/$binary" ]] || return 1
		[[ "$(readlink -f "$HOME/.local/bin/$binary")" == "$HOME/.local/share/dotfiles-npm/$key/bin/$binary" ]] || return 1
		[[ "$("$HOME/.local/bin/$binary")" == 1.2.3 ]] || return 1
		[[ "$(<"$HOME/.local/share/dotfiles/$key.version")" == 1.2.3 ]] || return 1
		grep -Fqx "install:${package}@1.2.3" "$TEST_URL_LOG" || return 1
		! compgen -G "$HOME/.local/share/dotfiles-npm/${key}.staging.*" >/dev/null || return 1
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
	! grep -q PUPPETEER "$HOME/.local/share/dotfiles-npm/cspell/bin/cspell"
)

test_a_failed_npm_install_leaves_nothing() (
	reset_home
	serve 1.2.3
	NPM_INSTALL_FAILS=1
	! install_npm_cli cspell >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/cspell" && ! -e "$HOME/.local/share/dotfiles-npm/cspell" ]] || return 1
	! compgen -G "$HOME/.local/share/dotfiles-npm/cspell.staging.*" >/dev/null
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
	grep -Fqx 'install:cspell@1.2.3' "$TEST_URL_LOG"
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
	! compgen -G "$HOME/.local/share/dotfiles-npm/markdownlint_cli2.previous.*" >/dev/null || return 1

	upgrade_markdownlint_cli2 >/dev/null || return 1
	[[ "$(<"$TEST_HARNESS_ROOT/result")" == already-current ]]
)

test_update_without_registry_answer_preserves_the_command() (
	reset_home
	own cspell 1.2.3
	SERVED_VERSION=''

	! upgrade_cspell >/dev/null 2>&1 || return 1
	[[ "$(npm_cli_installed_tag cspell)" == 1.2.3 ]]
)

test_update_check_reports_installed_available_and_action() (
	reset_home
	local row
	serve 12.0.0
	row="$(check_mermaid_cli || true)"
	[[ "$row" == 'Mermaid CLI|not installed|—|skip' ]] || return 1

	own mermaid_cli 11.0.0
	serve 12.0.0
	row="$(check_mermaid_cli)" || return 1
	[[ "$row" == 'Mermaid CLI|11.0.0|12.0.0|upgrade' ]] || return 1

	rm -f -- "$HOME/.local/share/dotfiles/mermaid_cli.version"
	row="$(check_mermaid_cli || true)"
	[[ "$row" == 'Mermaid CLI|11.0.0|—|external' ]]
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
expect_success 'update without an npm registry answer preserves the command' test_update_without_registry_answer_preserves_the_command
expect_success 'update check reports installed, available and action' test_update_check_reports_installed_available_and_action
expect_success 'per-tool wrappers exist for the update registry' test_wrappers_route_to_each_tool
