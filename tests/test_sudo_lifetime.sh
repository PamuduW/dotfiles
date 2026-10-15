#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$REPO_DIR/scripts/lib/shared_resolve.sh"
dotfiles_shared_require "$REPO_DIR"

run_lifetime() {
	local mode="$1" terminal="$2" end="$3" logged="$4" want="$5" custom_signal="${6:-no}"
	local probe="$TEST_HARNESS_ROOT/$mode-$terminal-$end-$logged-$custom_signal" status=0
	mkdir -p "$probe"
	MODE="$mode" TERMINAL="$terminal" END="$end" LOGGED="$logged" CUSTOM_SIGNAL="$custom_signal" \
		PROBE="$probe" REPO_DIR="$REPO_DIR" DOTFILES_SHARED_LIB="$DOTFILES_SHARED_LIB" bash <<'CHILD' >/dev/null 2>&1 || status=$?
set -euo pipefail
trap 'printf "%s\n" "$?" >"$PROBE/prior-exit"' EXIT
if [[ "$CUSTOM_SIGNAL" == yes ]]; then
	trap 'printf handled >"$PROBE/signal"; exit 23' TERM
fi
DOTFILES_DIR="$PROBE"
source "$REPO_DIR/scripts/lib/action_log.sh"
source "$DOTFILES_SHARED_LIB/sudo_prime.sh"
sudo() {
	printf '%s\n' "$*" >>"$PROBE/calls"
	case "$*" in
	'-n true') [[ "$MODE" == prior ]] ;;
	'-v' | '-A -v') [[ "$MODE" != denied ]] ;;
	'-k') return 0 ;;
	*) return 1 ;;
	esac
}
if [[ "$MODE" == absent ]]; then
	command() {
		[[ "$*" == '-v sudo' ]] && return 1
		builtin command "$@"
	}
fi
tty_available() { [[ "$TERMINAL" == tty ]]; }
tty_printf() { :; }
if [[ "$LOGGED" == yes ]]; then start_action_log; fi
sudo_prime || true
# A second prime and a child exit must not transfer or duplicate ownership.
if [[ "$MODE" == fresh ]]; then
	sudo() {
		printf '%s\n' "$*" >>"$PROBE/calls"
		return 0
	}
	sudo_prime
	(sudo_prime_cleanup)
fi
if [[ "$LOGGED" == yes ]]; then finalize_log_file; start_action_log; fi
case "$END" in
success) exit 0 ;;
failure) exit 17 ;;
TERM) kill -TERM "$$" ;;
INT) kill -INT "$$" ;;
HUP) kill -HUP "$$" ;;
esac
CHILD
	[[ "$status" == "$want" ]] || return 1
	[[ "$(cat "$probe/prior-exit")" == "$want" ]] || return 1
	if [[ "$custom_signal" == yes ]]; then
		[[ "$(cat "$probe/signal")" == handled ]] || return 1
	fi
	local invalidations=0
	if [[ -f "$probe/calls" ]]; then
		invalidations="$(grep -c '^-k$' "$probe/calls" || true)"
	fi
	if [[ "$mode" == fresh ]]; then
		[[ "$invalidations" == 1 ]]
	else
		[[ "$invalidations" == 0 ]]
	fi
}

for terminal in tty notty; do
	for logged in yes no; do
		for ending in success failure TERM INT HUP; do
			case "$ending" in success) want=0 ;; failure) want=17 ;; TERM) want=143 ;; INT) want=130 ;; HUP) want=129 ;; esac
			expect_success "fresh sudo: $terminal log=$logged $ending preserves cleanup/status" run_lifetime fresh "$terminal" "$ending" "$logged" "$want"
		done
		for mode in prior denied absent; do
			expect_success "$mode sudo: $terminal log=$logged leaves authentication alone" run_lifetime "$mode" "$terminal" success "$logged" 0
		done
	done
done

expect_success "existing TERM handler remains in control and exit still cleans sudo" run_lifetime fresh notty TERM no 23 yes

test_harness_cleanup
finish_tests
