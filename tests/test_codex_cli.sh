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

codex_sync_test_prepare() {
	codex_test_reset
	CODEX_SYNC_TEST_MODE="$1"
	CODEX_SYNC_CALL_LOG="$TEST_HARNESS_ROOT/codex-sync-call.log"
	CODEX_SYNC_PATH_LOG="$TEST_HARNESS_ROOT/codex-sync-path.log"
	CODEX_SYNC_NPM_LOG="$TEST_HARNESS_ROOT/codex-sync-npm.log"
	CODEX_SYNC_PROFILE="$HOME/.bashrc"
	printf '%s\n' '# managed profile fixture' >"$CODEX_SYNC_PROFILE"
	cp -- "$CODEX_SYNC_PROFILE" "$TEST_HARNESS_ROOT/profile.before"
	: >"$CODEX_SYNC_CALL_LOG"
	: >"$CODEX_SYNC_PATH_LOG"
	: >"$CODEX_SYNC_NPM_LOG"
	export CODEX_SYNC_TEST_MODE CODEX_SYNC_CALL_LOG CODEX_SYNC_PATH_LOG CODEX_SYNC_NPM_LOG CODEX_SYNC_PROFILE
}

run_vendor_shell_installer() {
	printf '%s|%s|%s\n' "$1" "$2" "$3" >"$CODEX_SYNC_CALL_LOG"
	printf '%s\n' "$PATH" >"$CODEX_SYNC_PATH_LOG"
	case ":$PATH:" in
	*":$HOME/.local/bin:"*) ;;
	*) printf '%s\n' '# vendor path marker' >>"$CODEX_SYNC_PROFILE" ;;
	esac

	case "$CODEX_SYNC_TEST_MODE" in
	success)
		codex_test_create_standalone
		codex_test_write_binary "$CODEX_HOME/packages/standalone/current/bin/codex-code-mode-host"
		;;
	exit-31) return 31 ;;
	missing-visible)
		codex_test_write_binary "$CODEX_HOME/packages/standalone/current/bin/codex-code-mode-host"
		;;
	external-visible)
		codex_test_write_binary "$HOME/external/bin/codex"
		mkdir -p -- "$CODEX_INSTALL_DIR"
		ln -s -- "$HOME/external/bin/codex" "$CODEX_INSTALL_DIR/codex"
		codex_test_write_binary "$CODEX_HOME/packages/standalone/current/bin/codex-code-mode-host"
		;;
	missing-helper) codex_test_create_standalone ;;
	*) return 98 ;;
	esac
}

npm() {
	printf '%s\n' "$*" >>"$CODEX_SYNC_NPM_LOG"
	return 97
}

test_codex_sync_uses_verified_vendor_boundary() {
	codex_sync_test_prepare success
	codex_sync_standalone || return 1
	[[ "$(<"$CODEX_SYNC_CALL_LOG")" == 'https://chatgpt.com/codex/install.sh|Codex CLI|CODEX_NON_INTERACTIVE=1' ]] || return 1
	case ":$(<"$CODEX_SYNC_PATH_LOG"):" in
	*":$CODEX_INSTALL_DIR:"*) ;;
	*) return 1 ;;
	esac
	cmp -s -- "$TEST_HARNESS_ROOT/profile.before" "$CODEX_SYNC_PROFILE" || return 1
	[[ -x "$CODEX_HOME/packages/standalone/current/bin/codex-code-mode-host" ]] || return 1
	[[ ! -s "$CODEX_SYNC_NPM_LOG" ]]
}

test_codex_sync_rejects_unverified_results() {
	local mode output rc
	for mode in exit-31 missing-visible external-visible missing-helper; do
		codex_sync_test_prepare "$mode"
		rc=0
		output="$(codex_sync_standalone 2>&1)" || rc=$?
		[[ "$rc" -ne 0 ]] || {
			printf '%s unexpectedly succeeded\n' "$mode" >&2
			return 1
		}
		if [[ "$mode" == exit-31 ]]; then
			[[ "$rc" -eq 31 ]] || return 1
		fi
		[[ "$output" != *'installed successfully'* ]] || return 1
		[[ ! -s "$CODEX_SYNC_NPM_LOG" ]] || return 1
	done
}

test_codex_install_state_matrix() (
	local fixture_state output rc expected_calls expected_rc expected_message
	local sync_calls installer_body
	local output_file="$TEST_HARNESS_ROOT/codex-install-output.log"
	local config_file="$HOME/.codex/config.toml"
	mkdir -p -- "$(dirname -- "$config_file")"
	printf '%s\n' 'model = "fixture"' >"$config_file"
	cp -- "$config_file" "$TEST_HARNESS_ROOT/codex-config.before"

	codex_cli_install_state() { printf '%s\n' "$fixture_state"; }
	codex_active_command() { printf '%s\n' "$HOME/.nvm/versions/node/v24.0.0/bin/codex"; }
	log_step() { printf '%s\n' "$1"; }
	log_ok() { printf '%s\n' "$1"; }
	log_skip() { printf '%s\n' "$1"; }
	codex_sync_standalone() {
		sync_calls=$((sync_calls + 1))
		return 0
	}
	installer_body="$(declare -f install_codex_cli)"
	! rg -q '\b(npm|rm)\b' <<<"$installer_body" || return 1

	while IFS='|' read -r fixture_state expected_calls expected_rc expected_message; do
		sync_calls=0
		rc=0
		install_codex_cli >"$output_file" 2>&1 || rc=$?
		output="$(<"$output_file")"
		[[ "$sync_calls" -eq "$expected_calls" ]] || return 1
		if [[ "$expected_rc" == zero ]]; then
			[[ "$rc" -eq 0 ]] || return 1
		else
			[[ "$rc" -ne 0 ]] || return 1
			[[ "$output" == *"$HOME/.nvm/versions/node/v24.0.0/bin/codex"* ]] || return 1
			[[ "$output" == *'README.md#codex-cli-migration'* ]] || return 1
		fi
		[[ "$output" == *"$expected_message"* ]] || return 1
		cmp -s -- "$TEST_HARNESS_ROOT/codex-config.before" "$config_file" || return 1
	done <<'EOF'
absent|1|zero|Codex CLI standalone installed
standalone|0|zero|Codex CLI standalone already installed
external|0|nonzero|external Codex installation must be removed explicitly
standalone-shadowed|0|nonzero|another Codex command shadows the standalone install
EOF
)

test_codex_scripts_do_not_reference_workspace_runbook() {
	! rg -F 'temp/process.md' "$REPO_DIR/scripts"
}

expect_success 'Codex ownership state matrix uses canonical active-command ownership' test_codex_ownership_state_matrix
expect_success 'Codex state API reports a visible standalone installation' test_codex_standalone_api
expect_success 'Codex standalone ownership rejects lookalike and dangling paths' test_codex_path_boundary_and_canonicalization
expect_success 'Codex multi-node shadowing follows the resolved command' test_shadowed_multi_node_follows_resolved_command
expect_success 'Codex standalone sync uses the verified vendor boundary without profile edits' test_codex_sync_uses_verified_vendor_boundary
expect_success 'Codex standalone sync rejects installer and ownership failures' test_codex_sync_rejects_unverified_results
expect_success 'Codex selected-component install follows the ownership state matrix' test_codex_install_state_matrix
expect_success 'Codex scripts do not reference the workspace-only migration runbook' test_codex_scripts_do_not_reference_workspace_runbook

finish_tests
