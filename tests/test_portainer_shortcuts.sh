#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Sourced helpers and test doubles.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init

portainer_case() (
	local scenario="$1" output rc=0
	local calls="$TEST_HARNESS_ROOT/portainer-calls"
	local attempts="$TEST_HARNESS_ROOT/portainer-attempts"
	: >"$calls"
	: >"$attempts"
	DOTFILES_DIR="$REPO_DIR"
	source "$REPO_DIR/bash/.bash_aliases"
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1" in
		start)
			[[ "$scenario" != start-failure ]] || return 42
			printf 'portainer\n'
			;;
		inspect)
			[[ "$scenario" != inspect-failure ]] || return 1
			printf '2026-10-21T05:53:38.000000000Z\n'
			;;
		*) return 1 ;;
		esac
	}
	docker() {
		printf '%s\n' "$*" >>"$calls"
		[[ "$*" == 'logs --since 2026-10-21T05:53:38.000000000Z --tail 200 portainer' ]] || return 1
		printf '.\n' >>"$attempts"
		case "$scenario" in
		token | fallback)
			if [[ "$scenario" == fallback && "${via_sudo:-0}" != 1 ]]; then
				printf 'permission denied\n' >&2
				return 1
			fi
			printf 'unrelated log content\nsetup_token=dummy-setup-token\n' >&2
			;;
		delayed)
			[[ "$(wc -l <"$attempts")" -lt 3 ]] || printf 'setup_token=delayed-dummy-token\n' >&2
			;;
		initialized) printf 'starting HTTPS server\n' >&2 ;;
		unavailable)
			printf 'logs unavailable\n' >&2
			return 1
			;;
		esac
	}
	sudo() {
		[[ "$1" == docker ]] || return 1
		shift
		via_sudo=1 docker "$@"
	}
	sleep() { :; }
	output="$(dpot 2>&1)" || rc=$?
	if [[ "$scenario" == start-failure ]]; then
		[[ "$rc" == 42 && "$(<"$calls")" == 'start portainer' ]] || return 1
		[[ "$output" != *'Portainer started'* ]]
		return
	fi
	[[ "$rc" == 0 && "$output" == *'Portainer started at https://localhost:9443'* ]] || return 1
	[[ "$output" != *'unrelated log content'* && "$output" != *'permission denied'* ]] || return 1
	case "$scenario" in
	token | fallback) [[ "$output" == $'portainer\nSetup token: dummy-setup-token\nPortainer started at https://localhost:9443' ]] ;;
	delayed) [[ "$output" == *'Setup token: delayed-dummy-token'* && "$(wc -l <"$attempts")" == 3 ]] ;;
	initialized) [[ "$output" != *'Setup token:'* && "$(wc -l <"$attempts")" == 1 ]] ;;
	unavailable | inspect-failure) [[ "$output" != *'Setup token:'* && "$output" == *'docker logs portainer'* ]] ;;
	timeout) [[ "$output" != *'Setup token:'* && "$(wc -l <"$attempts")" == 10 && "$output" == *'docker logs portainer'* ]] ;;
	esac
)

check 'dpot shows the setup token from stderr before the URL without dumping logs' portainer_case token
check 'dpot waits briefly for delayed startup logs' portainer_case delayed
check 'dpot leaves initialized startup output free of a token' portainer_case initialized
check 'dpot preserves start failure and does not inspect or read logs' portainer_case start-failure
check 'dpot can retrieve startup logs with the existing sudo fallback' portainer_case fallback
check 'dpot keeps start successful when logs are unavailable' portainer_case unavailable
check 'dpot does not fall back to historical logs if startup time cannot be read' portainer_case inspect-failure
check 'dpot bounds waiting when no token or readiness log appears' portainer_case timeout

test_harness_cleanup
finish_tests
