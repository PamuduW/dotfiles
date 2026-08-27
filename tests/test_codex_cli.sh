#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
# shellcheck source=tests/lib/dotfiles_env.sh
source "$TEST_DIR/lib/dotfiles_env.sh"

codex_test_reset() {
	local path_dir="$TEST_HARNESS_ROOT/codex-path"
	rm -rf -- "$HOME/.codex" "$HOME/.local" "$HOME/.nvm" "$HOME/external" "$path_dir"
	mkdir -p -- "$path_dir"
	PATH="$path_dir:/usr/bin:/bin"
	export PATH
	CODEX_HOME="$HOME/.codex"
	CODEX_INSTALL_DIR="$HOME/.local/bin"
	export CODEX_HOME CODEX_INSTALL_DIR
}

codex_test_write_binary() {
	local path="$1"
	mkdir -p -- "$(dirname -- "$path")"
	printf '%s\n' '#!/usr/bin/env bash' 'printf "codex-cli 0.150.1\\n"' >"$path"
	chmod +x -- "$path"
}

codex_test_create_standalone() {
	local root release
	root="$CODEX_HOME/packages/standalone"
	release="$root/releases/0.150.0-x86_64-unknown-linux-musl"
	codex_test_write_binary "$release/bin/codex"
	ln -s -- 'releases/0.150.0-x86_64-unknown-linux-musl' "$root/current"
	mkdir -p -- "$CODEX_INSTALL_DIR"
	ln -s -- "$root/current/bin/codex" "$CODEX_INSTALL_DIR/codex"
}

codex_test_put_on_path() {
	PATH="$1:/usr/bin:/bin"
	export PATH
}

codex_test_create_nvm_wrapper() {
	local version="$1"
	codex_test_write_binary "$HOME/.nvm/versions/node/$version/bin/codex"
}

codex_test_configure_case() {
	local name="$1" nvm_bin
	codex_test_reset
	case "$name" in
	absent) ;;
	partial-standalone-root)
		mkdir -p -- "$CODEX_HOME/packages/standalone/releases"
		: >"$CODEX_HOME/packages/standalone/install.lock"
		;;
	standalone-active)
		codex_test_create_standalone
		codex_test_put_on_path "$CODEX_INSTALL_DIR"
		;;
	standalone-other-release-active)
		codex_test_create_standalone
		codex_test_write_binary "$CODEX_HOME/packages/standalone/releases/0.149.0-x86_64-unknown-linux-musl/bin/codex"
		mkdir -p -- "$HOME/standalone-old/bin"
		ln -s -- "$CODEX_HOME/packages/standalone/releases/0.149.0-x86_64-unknown-linux-musl/bin/codex" \
			"$HOME/standalone-old/bin/codex"
		codex_test_put_on_path "$HOME/standalone-old/bin"
		;;
	standalone-not-on-path)
		codex_test_create_standalone
		;;
	standalone-shadowed)
		codex_test_create_standalone
		codex_test_create_nvm_wrapper v24.0.0
		nvm_bin="$HOME/.nvm/versions/node/v24.0.0/bin"
		codex_test_put_on_path "$nvm_bin"
		;;
	standalone-shadowed-multi-node)
		codex_test_create_standalone
		codex_test_create_nvm_wrapper v22.0.0
		codex_test_create_nvm_wrapper v24.0.0
		nvm_bin="$HOME/.nvm/versions/node/v24.0.0/bin"
		codex_test_put_on_path "$nvm_bin"
		;;
	nvm-node-wrapper)
		codex_test_create_nvm_wrapper v24.0.0
		codex_test_put_on_path "$HOME/.nvm/versions/node/v24.0.0/bin"
		;;
	unrelated-local-binary)
		codex_test_write_binary "$HOME/external/bin/codex"
		codex_test_put_on_path "$HOME/external/bin"
		;;
	dangling-visible-link)
		mkdir -p -- "$CODEX_INSTALL_DIR"
		ln -s -- "$HOME/missing/codex" "$CODEX_INSTALL_DIR/codex"
		codex_test_write_binary "$HOME/external/bin/codex"
		codex_test_put_on_path "$CODEX_INSTALL_DIR:$HOME/external/bin"
		;;
	*)
		printf 'unknown Codex fixture: %s\n' "$name" >&2
		return 2
		;;
	esac
}

test_codex_ownership_state_matrix() {
	local -a cases=(
		'absent|absent'
		'partial-standalone-root|absent'
		'standalone-active|standalone'
		'standalone-other-release-active|standalone-shadowed'
		'standalone-not-on-path|standalone-shadowed'
		'standalone-shadowed|standalone-shadowed'
		'standalone-shadowed-multi-node|standalone-shadowed'
		'nvm-node-wrapper|external'
		'unrelated-local-binary|external'
		'dangling-visible-link|external'
	)
	local case_name expected actual
	for case_name in "${cases[@]}"; do
		IFS='|' read -r case_name expected <<<"$case_name"
		codex_test_configure_case "$case_name"
		actual="$(codex_cli_install_state)"
		[[ "$actual" == "$expected" ]] || {
			printf '%s: expected %s, got %s\n' "$case_name" "$expected" "$actual" >&2
			return 1
		}
	done
}

test_codex_standalone_api() {
	codex_test_configure_case standalone-active
	[[ "$(codex_standalone_root)" == "$HOME/.codex/packages/standalone" ]] || return 1
	[[ "$(codex_visible_install_path)" == "$HOME/.local/bin/codex" ]] || return 1
	[[ "$(codex_active_command)" == "$HOME/.local/bin/codex" ]] || return 1
	codex_standalone_is_installed || return 1
	codex_cli_is_standalone_active || return 1
}

test_codex_path_boundary_and_canonicalization() {
	codex_test_configure_case standalone-active
	codex_path_is_standalone_owned "$HOME/.local/bin/codex" || return 1
	codex_test_write_binary "$HOME/.codex/packages/standalone-evil/current/bin/codex"
	codex_test_write_binary "$HOME/.nvm/versions/node/v24/bin/codex"
	if codex_path_is_standalone_owned "$HOME/.codex/packages/standalone-evil/current/bin/codex"; then return 1; fi
	if codex_path_is_standalone_owned "$HOME/.nvm/versions/node/v24/bin/codex"; then return 1; fi
	ln -s -- "$HOME/missing/codex" "$CODEX_INSTALL_DIR/dangling-codex"
	if codex_path_is_standalone_owned "$HOME/.local/bin/dangling-codex"; then return 1; fi
}

test_shadowed_multi_node_follows_resolved_command() {
	codex_test_configure_case standalone-shadowed-multi-node
	rm -f -- "$HOME/.nvm/versions/node/v22.0.0/bin/codex"
	[[ "$(codex_active_command)" == "$HOME/.nvm/versions/node/v24.0.0/bin/codex" ]] || return 1
	[[ "$(codex_cli_install_state)" == standalone-shadowed ]] || return 1
}

expect_success 'Codex ownership state matrix uses canonical active-command ownership' test_codex_ownership_state_matrix
expect_success 'Codex state API reports a visible standalone installation' test_codex_standalone_api
expect_success 'Codex standalone ownership rejects lookalike and dangling paths' test_codex_path_boundary_and_canonicalization
expect_success 'Codex multi-node shadowing follows the resolved command' test_shadowed_multi_node_follows_resolved_command

finish_tests
