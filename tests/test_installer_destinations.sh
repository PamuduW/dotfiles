#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$ROOT/scripts/lib/installers/logging.sh"
source "$ROOT/scripts/lib/installers/boost.sh"
source "$ROOT/scripts/lib/installers/antigravity.sh"
source "$ROOT/scripts/lib/installers/release_cli.sh"
source "$ROOT/scripts/lib/installers/chrome_headless.sh"
source "$ROOT/scripts/lib/installers/npm_cli.sh"

test_directory_destinations_stop_before_download() (
	local tool destination rc=0 calls="$TEST_HARNESS_ROOT/downloads"
	github_curl() {
		echo download >>"$calls"
		return 9
	}
	antigravity_curl() {
		echo download >>"$calls"
		return 9
	}
	curl() {
		echo download >>"$calls"
		return 9
	}
	npm() {
		echo download >>"$calls"
		return 9
	}
	for tool in boost agy kubeconform chrome-headless-shell cspell; do
		destination="$HOME/.local/bin/$tool"
		mkdir -p "$destination"
		printf 'preserve\n' >"$destination/sentinel"
		: >"$calls"
		rc=0
		case "$tool" in
		boost) boost_install_release v1.2.3 digest >/dev/null 2>&1 || rc=$? ;;
		agy) antigravity_install_release 1.2.3 url digest >/dev/null 2>&1 || rc=$? ;;
		kubeconform) release_cli_install_release kubeconform v1.2.3 digest >/dev/null 2>&1 || rc=$? ;;
		chrome-headless-shell) chrome_headless_install_release 1.2.3.4 url >/dev/null 2>&1 || rc=$? ;;
		cspell) npm_cli_install_release cspell 1.2.3 >/dev/null 2>&1 || rc=$? ;;
		esac
		[[ "$rc" -ne 0 && ! -s "$calls" ]] || return 1
		[[ "$(<"$destination/sentinel")" == preserve ]] || return 1
	done
)

test_failed_binary_stamp_restores_original_file() (
	local dir="$TEST_HARNESS_ROOT/activation"
	mkdir "$dir"
	printf 'old\n' >"$dir/command"
	printf 'new\n' >"$dir/candidate"
	printf 'old-version\n' >"$dir/stamp"
	mv() {
		[[ "${*: -1}" != "$dir/stamp" ]] || return 9
		command mv "$@"
	}
	! activate_managed_install "$dir/candidate" "$dir/command" '' "$dir/stamp" '' new-version || return 1
	[[ "$(<"$dir/command")" == old && "$(<"$dir/stamp")" == old-version ]]
)

test_failed_restoration_retains_a_reported_backup() (
	local dir="$TEST_HARNESS_ROOT/recovery" output backup
	mkdir "$dir"
	echo old >"$dir/command"
	echo new >"$dir/candidate"
	echo old-version >"$dir/stamp"
	mv() {
		[[ "${*: -1}" != "$dir/stamp" && "${*: -2:1}" != */previous ]] || return 9
		command mv "$@"
	}
	output="$(activate_managed_install "$dir/candidate" "$dir/command" '' "$dir/stamp" '' new-version 2>&1)" && return 1
	backup="$(find "$dir" -name previous -type f -print -quit)"
	[[ -n "$backup" && "$(<"$backup")" == old && "$output" == *"$(dirname -- "$backup")"* ]]
)

test_termination_rolls_back_the_active_file() (
	local dir="$TEST_HARNESS_ROOT/terminated" rc=0
	mkdir "$dir"
	echo old >"$dir/command"
	echo new >"$dir/candidate"
	echo old-version >"$dir/stamp"
	mv() {
		if [[ "${*: -1}" == "$dir/stamp" ]]; then kill -TERM "$BASHPID"; fi
		command mv "$@"
	}
	activate_managed_install "$dir/candidate" "$dir/command" '' "$dir/stamp" '' new-version || rc=$?
	[[ "$rc" -eq 143 && "$(<"$dir/command")" == old && "$(<"$dir/stamp")" == old-version ]]
)

expect_success 'failed restoration retains a reported private backup' test_failed_restoration_retains_a_reported_backup
expect_success 'termination during publication restores the old file and stamp' test_termination_rolls_back_the_active_file

expect_success 'affected command installers preserve directory destinations without downloads' test_directory_destinations_stop_before_download
expect_success 'failed binary stamp publication restores the original file and stamp' test_failed_binary_stamp_restores_original_file
finish_tests
