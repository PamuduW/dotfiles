#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"
source "$TEST_DIR/lib/codex_catalog_fixture.sh"
export TEST_CODEX_UPDATE_MARKER="$TEST_HARNESS_ROOT/automatic-update"
uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; -r) echo fixture ;; esac }
curl() {
	while (($#)); do
		if [[ "$1" == -o ]]; then
			cp "$TEST_HARNESS_ROOT/codex.tgz" "$2"
			return
		fi
		shift
	done
	return 1
}
migration_case() (
	local mode="$1" tree package output rc=0 confirmations=0
	export HOME="$TEST_HARNESS_ROOT/$mode/home" NVM_DIR="$TEST_HARNESS_ROOT/$mode/home/.nvm"
	export CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin"
	export DOTFILES_MIGRATE_NPM_CODEX=1 DOTFILES_INTERACTIVE_TTY=false
	local version
	for version in v22 v24; do
		tree="$NVM_DIR/versions/node/$version"
		package="$tree/lib/node_modules/@openai/codex"
		mkdir -p "$tree/bin" "$package/bin"
		printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-cli 0.1.0"' >"$package/bin/codex.js"
		chmod +x "$package/bin/codex.js"
		printf '%s\n' '{"name":"@openai/codex","version":"0.1.0"}' >"$package/package.json"
		ln -s ../lib/node_modules/@openai/codex/bin/codex.js "$tree/bin/codex"
		printf '%s\n' '#!/usr/bin/env bash' 'exit 96' >"$tree/bin/npm"
		chmod +x "$tree/bin/npm"
	done
	PATH="$HOME/.local/bin:$NVM_DIR/versions/node/v24/bin:/usr/bin:/bin"
	export PATH
	mkdir -p "$CODEX_HOME"
	printf 'model = "keep-model"\n' >"$CODEX_HOME/config.toml"
	make_codex_fixture 1.2.3
	case "$mode" in
	legacy-shadowed)
		mkdir -p "$CODEX_HOME/packages/standalone/releases/old/bin" "$HOME/.local/bin"
		cp "$package/bin/codex.js" "$CODEX_HOME/packages/standalone/releases/old/bin/codex"
		ln -s releases/old "$CODEX_HOME/packages/standalone/current"
		ln -s "$CODEX_HOME/packages/standalone/current/bin/codex" "$HOME/.local/bin/codex"
		PATH="$NVM_DIR/versions/node/v24/bin:$HOME/.local/bin:/usr/bin:/bin"
		;;
	declined) unset DOTFILES_MIGRATE_NPM_CODEX ;;
	interactive-yes | interactive-no)
		unset DOTFILES_MIGRATE_NPM_CODEX
		DOTFILES_INTERACTIVE_TTY=true
		ui_confirm_yes_no() { [[ "$1" == *'Remove the listed npm Codex installations'* && "$mode" == interactive-yes ]]; }
		;;
	bad-package-name) printf '%s\n' '{"name":"unrelated","version":"0.1.0"}' >"$package/package.json" ;;
	bad-artifact) printf corrupt >>"$TEST_HARNESS_ROOT/codex.tgz" ;;
	missing-helper) make_codex_fixture 1.2.3 no ;;
	hidden-foreign)
		mkdir -p "$HOME/external"
		cp "$package/bin/codex.js" "$HOME/external/codex"
		PATH="$PATH:$HOME/external"
		;;
	foreign)
		mkdir -p "$HOME/external"
		cp "$package/bin/codex.js" "$HOME/external/codex"
		PATH="$HOME/external:$PATH"
		;;
	package-only) mkdir -p "$NVM_DIR/versions/node/v20/lib/node_modules/@openai/codex" ;;
	unowned-wrapper)
		rm "$tree/bin/codex"
		cp "$package/bin/codex.js" "$tree/bin/codex"
		;;
	esac
	mv() {
		if [[ "$mode" == removal-failure && "${2:-}" == "$NVM_DIR/versions/node/v24/bin/codex" ]]; then return 41; fi
		if [[ "$mode" == publication-failure && "${*: -1}" == "$HOME/.local/bin/codex" ]]; then return 42; fi
		command mv "$@"
	}
	output="$(install_codex_cli 2>&1)" || rc=$?
	if [[ "$mode" == success || "$mode" == interactive-yes || "$mode" == legacy-shadowed ]]; then
		[[ "$rc" == 0 ]] || {
			printf '%s\n' "$output" >&2
			return 1
		}
		[[ "$("$HOME/.local/bin/codex" --version)" == 'codex-cli 1.2.3' ]] || return 1
		dotfiles_catalog_owned codex_cli || return 1
		for version in v22 v24; do
			[[ ! -e "$NVM_DIR/versions/node/$version/bin/codex" ]] || return 1
			[[ ! -e "$NVM_DIR/versions/node/$version/lib/node_modules/@openai/codex" ]] || return 1
		done
	else
		[[ "$rc" != 0 ]] || {
			echo "FAIL: $mode accepted migration" >&2
			return 1
		}
		for version in v22 v24; do
			[[ -x "$NVM_DIR/versions/node/$version/bin/codex" ]] || {
				echo "FAIL: $mode lost $version command" >&2
				return 1
			}
			[[ -f "$NVM_DIR/versions/node/$version/lib/node_modules/@openai/codex/package.json" ]] || return 1
		done
		[[ ! -e "$HOME/.local/bin/codex" && ! -L "$HOME/.local/bin/codex" ]] || return 1
	fi
	[[ "$(cat "$CODEX_HOME/config.toml")" == 'model = "keep-model"' ]] || return 1
	[[ ! -e "$TEST_CODEX_UPDATE_MARKER" ]]
)
for mode in success legacy-shadowed declined interactive-yes interactive-no bad-package-name bad-artifact missing-helper foreign hidden-foreign package-only unowned-wrapper removal-failure publication-failure; do
	check "Codex catalog migration: $mode" migration_case "$mode"
done
finish_tests
