#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Runtime loader and command doubles.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

# Removing an entrypoint's guard must allow work to reach this sentinel.
test_sudo_rs_stops_before_install_or_apt_work() (
	local entry output rc calls="$TEST_HARNESS_ROOT/sudo-compat.calls"
	sudo() {
		if [[ "$*" == --version ]]; then
			printf 'sudo-rs 0.2.13\n'
		else
			printf 'sudo %s\n' "$*" >>"$calls"
		fi
	}
	sudo_prime() { printf 'password prompt\n' >>"$calls"; }
	_run_install_preamble() { printf 'install preamble\n' >>"$calls"; }
	COMP_INSTALL_ORDER=()
	print_install_summary() { :; }
	apt_upgradable_count() { printf '0\n'; }
	# A cached refresh must not bypass compatibility checks.
	DOTFILES_APT_INDEX_REFRESHED_AT="${EPOCHSECONDS:-$(date +%s)}"
	for entry in run_install _run_apt_index_refresh _update_apt_packages; do
		: >"$calls"
		rc=0
		output="$("$entry" 2>&1)" || rc=$?
		[[ "$rc" -ne 0 ]] || {
			printf '%s did not refuse sudo-rs\n' "$entry" >&2
			return 1
		}
		[[ ! -s "$calls" ]] || {
			cat "$calls" >&2
			return 1
		}
		[[ "$output" == *sudo-rs* && "$output" == *'sudo update-alternatives --set sudo /usr/bin/sudo.ws'* ]] || return 1
	done
)

test_classic_sudo_allows_apt_refresh() (
	local calls="$TEST_HARNESS_ROOT/classic-sudo.calls"
	: >"$calls"
	sudo() {
		case "$*" in
		--version) printf 'Sudo version 1.9.17p2\nSudoers policy plugin version 1.9.17p2\n' ;;
		'apt-get update -qq') printf 'refresh\n' >>"$calls" ;;
		*) return 91 ;;
		esac
	}
	unset DOTFILES_APT_INDEX_REFRESHED_AT
	_run_apt_index_refresh >/dev/null || return 1
	[[ "$(<"$calls")" == refresh ]]
)

check 'sudo-rs stops installation and apt updates before privileged work' test_sudo_rs_stops_before_install_or_apt_work
check 'classic sudo still refreshes apt indexes' test_classic_sudo_allows_apt_refresh
finish_tests
