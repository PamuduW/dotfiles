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
	NVM_DIR="$HOME/.nvm"
	export CODEX_HOME CODEX_INSTALL_DIR NVM_DIR
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

codex_test_create_nvm_install() {
	local version="$1" tree="$HOME/.nvm/versions/node/$1"
	mkdir -p -- "$tree/bin" "$tree/lib/node_modules/@openai/codex/bin"
	codex_test_write_binary "$tree/lib/node_modules/@openai/codex/bin/codex.js"
	ln -s -- '../lib/node_modules/@openai/codex/bin/codex.js' "$tree/bin/codex"
	printf '%s\n' '{"name":"@openai/codex","version":"0.149.1"}' \
		>"$tree/lib/node_modules/@openai/codex/package.json"
	cat >"$tree/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tree="$(cd -- "$(dirname -- "$0")/.." && pwd)"
printf '%s|%s\n' "$tree" "$*" >>"$CODEX_NVM_TEST_LOG"
[[ ! -e "$tree/fail-uninstall" ]] || exit 41
[[ ! -e "$tree/keep-after-uninstall" ]] || exit 0
if [[ -e "$tree/keep-package-after-uninstall" ]]; then
	rm -f -- "$tree/bin/codex"
	exit 0
fi
rm -f -- "$tree/bin/codex"
rm -rf -- "$tree/lib/node_modules/@openai/codex"
EOF
	chmod +x -- "$tree/bin/npm"
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
	local sync_calls
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
external|0|nonzero|cannot migrate unverified external Codex installation
standalone-shadowed|0|nonzero|cannot migrate unverified external Codex installation
EOF
)

test_authorized_nvm_migration_removes_every_copy_then_installs_standalone() (
	local sync_calls=0 output output_file="$TEST_HARNESS_ROOT/codex-nvm-output.log"
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v22.22.2
	codex_test_create_nvm_install v24.19.0
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	mkdir -p -- "$HOME/.codex"
	printf '%s\n' 'model = "fixture"' >"$HOME/.codex/config.toml"

	codex_sync_standalone() {
		sync_calls=$((sync_calls + 1))
		codex_test_create_standalone
		codex_test_write_binary "$CODEX_HOME/packages/standalone/current/bin/codex-code-mode-host"
	}
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	install_codex_cli >"$output_file" 2>&1 || return 1
	output="$(<"$output_file")"
	[[ "$sync_calls" -eq 1 ]] || return 1
	[[ "$(wc -l <"$CODEX_NVM_TEST_LOG")" -eq 2 ]] || return 1
	grep -Fq "$HOME/.nvm/versions/node/v22.22.2|--prefix $HOME/.nvm/versions/node/v22.22.2 uninstall -g @openai/codex" "$CODEX_NVM_TEST_LOG" || return 1
	grep -Fq "$HOME/.nvm/versions/node/v24.19.0|--prefix $HOME/.nvm/versions/node/v24.19.0 uninstall -g @openai/codex" "$CODEX_NVM_TEST_LOG" || return 1
	[[ ! -e "$HOME/.nvm/versions/node/v22.22.2/bin/codex" ]] || return 1
	[[ ! -e "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]] || return 1
	[[ "$(<"$HOME/.codex/config.toml")" == 'model = "fixture"' ]] || return 1
	[[ "$output" == *'Migrating 2 npm-managed Codex installations'* ]] || return 1
	codex_cli_is_standalone_active
)

test_nvm_migration_requires_explicit_noninteractive_authorization() (
	local sync_calls=0 output rc=0
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-declined.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v24.19.0
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	unset DOTFILES_MIGRATE_NPM_CODEX
	export PATH DOTFILES_INTERACTIVE_TTY
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	output="$(install_codex_cli 2>&1)" || rc=$?
	[[ "$rc" -ne 0 && "$sync_calls" -eq 0 ]] || return 1
	[[ -x "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]] || return 1
	[[ ! -s "$CODEX_NVM_TEST_LOG" ]] || return 1
	[[ "$output" == *'DOTFILES_MIGRATE_NPM_CODEX=1'* ]]
)

test_nvm_migration_refuses_unrelated_external_codex() (
	local sync_calls=0 output rc=0
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-unrelated.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v24.19.0
	codex_test_write_binary "$HOME/external/bin/codex"
	PATH="$HOME/external/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	output="$(install_codex_cli 2>&1)" || rc=$?
	[[ "$rc" -ne 0 && "$sync_calls" -eq 0 ]] || return 1
	[[ -x "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]] || return 1
	[[ ! -s "$CODEX_NVM_TEST_LOG" ]] || return 1
	[[ "$output" == *'cannot migrate unverified external Codex installation'* ]]
)

test_nvm_migration_refuses_nvm_wrapper_not_owned_by_codex_package() (
	local sync_calls=0 output rc=0
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-lookalike.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v24.19.0
	rm -f -- "$HOME/.nvm/versions/node/v24.19.0/bin/codex"
	codex_test_write_binary "$HOME/.nvm/versions/node/v24.19.0/bin/codex"
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	output="$(install_codex_cli 2>&1)" || rc=$?
	[[ "$rc" -ne 0 && "$sync_calls" -eq 0 ]] || return 1
	[[ -x "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]] || return 1
	[[ ! -s "$CODEX_NVM_TEST_LOG" ]] || return 1
	[[ "$output" == *'cannot migrate unverified external Codex installation'* ]]
)

test_nvm_migration_refuses_package_only_tree_before_removing_anything() (
	local sync_calls=0 output rc=0
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-package-only.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v24.19.0
	mkdir -p -- "$HOME/.nvm/versions/node/v22.22.2/lib/node_modules/@openai/codex"
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	output="$(install_codex_cli 2>&1)" || rc=$?
	[[ "$rc" -ne 0 && "$sync_calls" -eq 0 ]] || return 1
	[[ -x "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]] || return 1
	[[ ! -s "$CODEX_NVM_TEST_LOG" ]] || return 1
	[[ "$output" == *'cannot migrate unverified external Codex installation'* ]]
)

test_interactive_nvm_migration_requires_and_honors_confirmation() (
	local confirmations=0 sync_calls=0
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-interactive.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v24.19.0
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=true
	unset DOTFILES_MIGRATE_NPM_CODEX
	export PATH DOTFILES_INTERACTIVE_TTY
	ui_confirm_yes_no() {
		confirmations=$((confirmations + 1))
		[[ "$1" == *'Remove the listed npm Codex installations'* ]]
	}
	codex_sync_standalone() {
		sync_calls=$((sync_calls + 1))
		codex_test_create_standalone
		codex_test_write_binary "$CODEX_HOME/packages/standalone/current/bin/codex-code-mode-host"
	}
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	install_codex_cli >/dev/null 2>&1 || return 1
	[[ "$confirmations" -eq 1 && "$sync_calls" -eq 1 ]] || return 1
	[[ ! -e "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]]
)

test_nvm_migration_stops_before_standalone_after_partial_uninstall_failure() (
	local sync_calls=0 output rc=0 output_file="$TEST_HARNESS_ROOT/codex-nvm-partial-output.log"
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-partial.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v22.22.2
	codex_test_create_nvm_install v24.19.0
	: >"$HOME/.nvm/versions/node/v24.19.0/fail-uninstall"
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	install_codex_cli >"$output_file" 2>&1 || rc=$?
	output="$(<"$output_file")"
	[[ "$rc" -ne 0 && "$sync_calls" -eq 0 ]] || return 1
	[[ ! -e "$HOME/.nvm/versions/node/v22.22.2/bin/codex" ]] || return 1
	[[ -x "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]] || return 1
	[[ "$output" == *'standalone was not installed'* ]]
)

test_nvm_migration_rejects_successful_uninstall_that_leaves_codex() (
	local sync_calls=0 output rc=0 output_file="$TEST_HARNESS_ROOT/codex-nvm-leftover-output.log"
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-leftover.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v24.19.0
	: >"$HOME/.nvm/versions/node/v24.19.0/keep-after-uninstall"
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	install_codex_cli >"$output_file" 2>&1 || rc=$?
	output="$(<"$output_file")"
	[[ "$rc" -ne 0 && "$sync_calls" -eq 0 ]] || return 1
	[[ -x "$HOME/.nvm/versions/node/v24.19.0/bin/codex" ]] || return 1
	[[ "$output" == *'commands remain after migration; standalone was not installed'* ]]
)

test_nvm_migration_rejects_leftover_package_without_command() (
	local sync_calls=0 output rc=0 output_file="$TEST_HARNESS_ROOT/codex-nvm-package-leftover-output.log"
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-package-leftover.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_nvm_install v24.19.0
	: >"$HOME/.nvm/versions/node/v24.19.0/keep-package-after-uninstall"
	PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.19.0/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	install_codex_cli >"$output_file" 2>&1 || rc=$?
	output="$(<"$output_file")"
	[[ "$rc" -ne 0 && "$sync_calls" -eq 0 ]] || return 1
	[[ -d "$HOME/.nvm/versions/node/v24.19.0/lib/node_modules/@openai/codex" ]] || return 1
	[[ "$output" == *'npm Codex artifacts remain after migration; standalone was not installed'* ]]
)

test_nvm_migration_unshadows_existing_standalone_without_reinstalling() (
	local sync_calls=0
	codex_test_reset
	CODEX_NVM_TEST_LOG="$TEST_HARNESS_ROOT/codex-nvm-shadowed.log"
	: >"$CODEX_NVM_TEST_LOG"
	export CODEX_NVM_TEST_LOG
	codex_test_create_standalone
	codex_test_create_nvm_install v24.19.0
	PATH="$HOME/.nvm/versions/node/v24.19.0/bin:$HOME/.local/bin:/usr/bin:/bin"
	DOTFILES_INTERACTIVE_TTY=false
	DOTFILES_MIGRATE_NPM_CODEX=1
	export PATH DOTFILES_INTERACTIVE_TTY DOTFILES_MIGRATE_NPM_CODEX
	codex_sync_standalone() { sync_calls=$((sync_calls + 1)); }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }

	install_codex_cli >/dev/null 2>&1 || return 1
	[[ "$sync_calls" -eq 0 ]] || return 1
	codex_cli_is_standalone_active
)

test_codex_scripts_do_not_reference_workspace_runbook() {
	! rg -F 'temp/process.md' "$REPO_DIR/scripts"
}

test_codex_latest_channel_accepts_only_safe_rust_tags() (
	local metadata expected output
	# shellcheck disable=SC2031  # The stub reads each loop fixture in this test subshell.
	codex_latest_channel_json() { printf '%s\n' "$metadata"; }
	while IFS='|' read -r metadata expected; do
		output="$(codex_available_version)"
		[[ "$output" == "$expected" ]] || return 1
	done <<'EOF'
{"tag_name":"rust-v0.150.0","assets":[]}|0.150.0
{"tag_name":"v0.150.0","assets":[]}|—
{"tag_name":"rust-vlatest;touch /tmp/nope","assets":[]}|—
{}|—
EOF
	[[ ! -e /tmp/nope ]]
)

test_codex_semver_comparator_follows_release_precedence() {
	local left _relation right expected
	while read -r left _relation right expected; do
		[[ "$(codex_semver_compare "$left" "$right")" == "$expected" ]] || return 1
	done <<'EOF'
0.149.9 < 0.150.0 -1
0.150.0-alpha < 0.150.0-alpha.1 -1
0.150.0-alpha.1 < 0.150.0-alpha.2 -1
0.150.0-alpha.2 < 0.150.0-beta -1
0.150.0-beta < 0.150.0-beta.1 -1
0.150.0-beta.1 < 0.150.0 -1
0.150.0 = 0.150.0 0
0.151.0 > 0.150.1 1
EOF
}

test_codex_version_number_accepts_only_first_line_safe_versions() {
	[[ "$(codex_version_number 'codex-cli 0.150.0')" == '0.150.0' ]] || return 1
	! codex_version_number $'codex-cli unknown\ncodex-cli 0.150.0' >/dev/null || return 1
	! codex_version_number 'codex-cli v0.150.0' >/dev/null || return 1
	! codex_version_number 'codex-cli 0.150.0;touch /tmp/nope' >/dev/null
}

expect_success 'Codex ownership state matrix uses canonical active-command ownership' test_codex_ownership_state_matrix
expect_success 'Codex state API reports a visible standalone installation' test_codex_standalone_api
expect_success 'Codex standalone ownership rejects lookalike and dangling paths' test_codex_path_boundary_and_canonicalization
expect_success 'Codex multi-node shadowing follows the resolved command' test_shadowed_multi_node_follows_resolved_command
expect_success 'Codex standalone sync uses the verified vendor boundary without profile edits' test_codex_sync_uses_verified_vendor_boundary
expect_success 'Codex standalone sync rejects installer and ownership failures' test_codex_sync_rejects_unverified_results
expect_success 'Codex selected-component install follows the ownership state matrix' test_codex_install_state_matrix
expect_success 'authorized NVM migration removes every Codex copy before standalone install' test_authorized_nvm_migration_removes_every_copy_then_installs_standalone
expect_success 'NVM migration requires explicit authorization outside the TUI' test_nvm_migration_requires_explicit_noninteractive_authorization
expect_success 'NVM migration refuses an unrelated external Codex command' test_nvm_migration_refuses_unrelated_external_codex
expect_success 'NVM migration refuses an NVM wrapper not owned by the Codex package' test_nvm_migration_refuses_nvm_wrapper_not_owned_by_codex_package
expect_success 'NVM migration refuses a package-only tree before removing anything' test_nvm_migration_refuses_package_only_tree_before_removing_anything
expect_success 'interactive NVM migration requires and honors a dedicated confirmation' test_interactive_nvm_migration_requires_and_honors_confirmation
expect_success 'partial NVM uninstall failure stops before standalone installation' test_nvm_migration_stops_before_standalone_after_partial_uninstall_failure
expect_success 'NVM migration rejects an uninstall that leaves Codex behind' test_nvm_migration_rejects_successful_uninstall_that_leaves_codex
expect_success 'NVM migration rejects a leftover package without a command' test_nvm_migration_rejects_leftover_package_without_command
expect_success 'NVM migration unshadows an existing standalone without reinstalling it' test_nvm_migration_unshadows_existing_standalone_without_reinstalling
expect_success 'Codex scripts do not reference the workspace-only migration runbook' test_codex_scripts_do_not_reference_workspace_runbook
expect_success 'Codex latest-channel parsing accepts only validated rust release tags' test_codex_latest_channel_accepts_only_safe_rust_tags
expect_success 'Codex version comparison follows stable and prerelease precedence' test_codex_semver_comparator_follows_release_precedence
expect_success 'Codex installed-version parsing rejects malformed and later-line values' test_codex_version_number_accepts_only_first_line_safe_versions

finish_tests
