#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

expect_success() {
	local name="$1"
	shift
	if "$@"; then pass "$name"; else fail "$name"; fi
}

expect_failure() {
	local name="$1"
	shift
	if "$@"; then fail "$name"; else pass "$name"; fi
}

test_docker_stops_before_restart_on_config_failure() {
	local tmp="$1"
	RESTART_MARKER="$tmp/restarted" bash -c '
		source "$1/scripts/lib/installers/logging.sh"
		source "$1/scripts/lib/installers/docker.sh"
		docker() { printf "Docker version test\n"; }
		groups() { printf "docker\n"; }
		configure_docker_daemon() { return 1; }
		restart_docker_service() { : >"$RESTART_MARKER"; }
		install_docker
	' _ "$ROOT" "$tmp"
}

test_docker_merge_temp_file_uses_sudo_boundary() {
	local installer="$ROOT/scripts/lib/installers/docker.sh"
	grep -Fq 'tmp_file="$(sudo mktemp)"' "$installer" &&
		grep -Fq 'sudo tee "$tmp_file" >/dev/null' "$installer" &&
		grep -Fq 'sudo rm -f "$tmp_file"' "$installer"
}

test_existing_unapproved_origin_is_rejected() {
	local repo="$1/rejected-repo"
	git init -q "$repo"
	git -C "$repo" remote add origin https://example.invalid/unapproved.git
	bash -c '
		source "$1/scripts/lib/agent_bootstrap_paths.sh"
		agent_bootstrap_existing_origin_allowed "$2"
	' _ "$ROOT" "$repo"
}

test_existing_unapproved_origin_can_be_explicitly_bypassed() {
	local repo="$1/bypassed-repo"
	git init -q "$repo"
	git -C "$repo" remote add origin https://example.invalid/unapproved.git
	AGENT_BOOTSTRAP_REPO_URL_ALLOW_ANY=1 bash -c '
		source "$1/scripts/lib/agent_bootstrap_paths.sh"
		agent_bootstrap_existing_origin_allowed "$2"
	' _ "$ROOT" "$repo"
}

test_self_rejects_non_git_directory() {
	local non_git="$1/non-git"
	mkdir -p "$non_git"
	bash -c '
		upgrade_dotfiles_repo() { return 0; }
		_err() { :; }
		source <(sed -n "/^cmd_self()/,/^}/p" "$1/bin/bin/dotfiles")
		DOTFILES_DIR="$2"
		set +e
		cmd_self
		exit $?
	' _ "$ROOT" "$non_git"
}

test_self_rejects_bare_git_repository() {
	local bare_repo="$1/bare.git"
	git init -q --bare "$bare_repo"
	bash -c '
		upgrade_dotfiles_repo() { return 0; }
		_err() { :; }
		source <(sed -n "/^cmd_self()/,/^}/p" "$1/bin/bin/dotfiles")
		DOTFILES_DIR="$2"
		set +e
		cmd_self
		exit $?
	' _ "$ROOT" "$bare_repo"
}

test_report_separator_has_no_stray_trailing_dash() {
	local output
	output="$(NO_COLOR=1 bash -c 'source "$1/scripts/lib/report_table.sh"; rt_print_table_columns' _ "$ROOT")"
	[[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]] &&
		[[ "$(printf '%s\n' "$output" | sed -n '2p')" == *+*+* ]] &&
		! printf '%s\n' "$output" | sed -n '2p' | grep -Eq -- '-[0-9]+$'
}

test_path_status_separator_has_no_numeric_format_artifact() {
	local output
	output="$(NO_COLOR=1 bash -c 'source "$1/scripts/lib/ui.sh"; ui_print_check_result_path_header 100' _ "$ROOT")"
	[[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]] &&
		[[ "$(printf '%s\n' "$output" | sed -n '2p')" == *+*+* ]] &&
		! printf '%s\n' "$output" | sed -n '2p' | grep -Eq -- '-[0-9]+$'
}

test_github_api_failure_names_source_without_leaking_token() {
	local output
	output="$(PATH="$1:/usr/bin:/bin" GITHUB_TOKEN=top-secret bash -c '
		source "$2/scripts/lib/github_api.sh"
		github_api_release_json asdf-vm/asdf
	' _ "$1" "$ROOT" 2>&1)" || true
	[[ "$output" == *'GitHub Releases API request failed for asdf-vm/asdf'* ]] &&
		[[ "$output" != *'top-secret'* ]]
}

test_failed_submenu_action_returns_to_menu_after_pause() {
	local output
	output="$(bash -c '
		set -euo pipefail
		source "$1/scripts/lib/menu_runner.sh"
		state_file="$2/menu-loop-count"
		printf "0\\n" >"$state_file"
		menu_simple_run() {
			calls="$(<"$state_file")"
			calls=$((calls + 1))
			printf "%s\\n" "$calls" >"$state_file"
			if ((calls == 1)); then
				printf "bootstrap\\n"
			else
				return 1
			fi
		}
		ui_clear() { :; }
		ui_pause() { printf "PAUSE_REACHED\\n"; }
		dispatch() { return 1; }
		labels=("Bootstrap" "Back")
		keys=(bootstrap back)
		menu_submenu_loop "Test" "Test" labels keys dispatch
		printf "LOOP_RETURNED\\n"
	' _ "$ROOT" "$1" 2>&1)"
	[[ "$output" == *"PAUSE_REACHED"* ]] && [[ "$output" == *"LOOP_RETURNED"* ]]
}

test_failed_github_release_install_cleans_up_without_unbound_variable() {
	local output
	output="$(TEST_TMPDIR="$1" bash -c '
		set -euo pipefail
		source "$2/scripts/lib/installers/github_release.sh"
		github_latest_release_version() { printf "1.2.3\\n"; }
		_linux_github_arch_suffix() { printf "x86_64\\n"; }
		log_step() { :; }
		mktemp() { command mktemp -d "$TEST_TMPDIR/release.XXXXXX"; }
		curl() { :; }
		sha256sum() { return 1; }
		run_install() { install_lazygit_from_github || :; }
		run_install
		[[ -z "$(find "$TEST_TMPDIR" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]]
	' _ "$1" "$ROOT" 2>&1)"
	[[ "$output" != *"unbound variable"* ]]
}

test_cli_probes_find_installed_local_binaries_before_path_refresh() {
	local home_dir="$1/probe-home" output
	mkdir -p "$home_dir/.local/bin"
	touch "$home_dir/.local/bin/agent" "$home_dir/.local/bin/claude"
	chmod +x "$home_dir/.local/bin/agent" "$home_dir/.local/bin/claude"
	output="$(HOME="$home_dir" PATH="/usr/bin:/bin" bash -c '
		source "$1/scripts/lib/components/probes.sh"
		_comp_probe_cursor_cli
		_comp_probe_claude_cli
	' _ "$ROOT")"
	[[ "$output" == $'installed|cursor cli\ninstalled|claude cli' ]]
}

test_lazygit_uses_current_lowercase_linux_release_asset() {
	local url_log="$1/lazygit-urls"
	URL_LOG="$url_log" bash -c '
		set -euo pipefail
		source "$1/scripts/lib/installers/github_release.sh"
		github_latest_release_version() { printf "1.2.3\\n"; }
		_linux_github_arch_suffix() { printf "x86_64\\n"; }
		log_step() { :; }
		curl() {
			local output="" arg
			while (($#)); do
				arg="$1"
				shift
				[[ "$arg" == "-o" ]] && { output="$1"; shift; }
			done
			printf "%s\\n" "$arg" >>"$URL_LOG"
			: >"$output"
		}
		sha256sum() { return 1; }
		install_lazygit_from_github >/dev/null 2>&1 || :
	' _ "$ROOT"
	grep -Fqx 'https://github.com/jesseduffield/lazygit/releases/download/v1.2.3/lazygit_1.2.3_linux_x86_64.tar.gz' "$url_log"
}

main() {
	local tmp
	tmp="$(mktemp -d)"
	trap 'rm -rf -- "${tmp:-}"' EXIT

	expect_failure 'Docker config failure prevents restart' test_docker_stops_before_restart_on_config_failure "$tmp"
	expect_success 'Docker merge temporary file stays in the sudo boundary' test_docker_merge_temp_file_uses_sudo_boundary
	if [[ ! -e "$tmp/restarted" ]]; then
		pass 'Docker restart was not attempted'
	else
		fail 'Docker restart was not attempted'
	fi
	expect_failure 'unapproved existing agent_bootstrap origin is rejected' test_existing_unapproved_origin_is_rejected "$tmp"
	expect_success 'explicit origin bypass remains available' test_existing_unapproved_origin_can_be_explicitly_bypassed "$tmp"
	expect_failure 'dotfiles self rejects non-git directory' test_self_rejects_non_git_directory "$tmp"
	expect_failure 'dotfiles self rejects bare Git repository' test_self_rejects_bare_git_repository "$tmp"
	expect_success 'report separator has no stray trailing dash' test_report_separator_has_no_stray_trailing_dash
	expect_success 'path-status separator has no numeric format artifact' test_path_status_separator_has_no_numeric_format_artifact

	local curl_dir="$tmp/curl-bin"
	mkdir -p "$curl_dir"
	printf '%s\n' '#!/usr/bin/env bash' 'echo "curl: (22) The requested URL returned error: 403" >&2' 'exit 22' >"$curl_dir/curl"
	chmod +x "$curl_dir/curl"
	expect_success 'GitHub API failures are diagnosable without token leakage' test_github_api_failure_names_source_without_leaking_token "$curl_dir"
	expect_success 'failed submenu action pauses and returns to the menu' test_failed_submenu_action_returns_to_menu_after_pause "$tmp"
	expect_success 'failed GitHub release install cleans up without an unbound variable' test_failed_github_release_install_cleans_up_without_unbound_variable "$tmp"
	expect_success 'CLI probes find installed local binaries before PATH refresh' test_cli_probes_find_installed_local_binaries_before_path_refresh "$tmp"
	expect_success 'lazygit uses the current lowercase Linux release asset' test_lazygit_uses_current_lowercase_linux_release_asset "$tmp"

	printf '%s test(s) passed; %s failed\n' "$PASS" "$FAIL"
	[[ "$FAIL" -eq 0 ]]
}

main "$@"
