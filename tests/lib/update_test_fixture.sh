# shellcheck shell=bash
# Shared fail-closed fixture for the update module test suites.

install_state_git_fake() {
	rm -f "$TEST_FAKE_BIN/git"
	cat >"$TEST_FAKE_BIN/git" <<'FAKE'
#!/usr/bin/env bash
set -u
printf 'git' >>"${TEST_COMMAND_LOG:?}"
for arg in "$@"; do printf '\t%s' "$arg" >>"$TEST_COMMAND_LOG"; done
printf '\n' >>"$TEST_COMMAND_LOG"
args=("$@")
if [[ "${args[0]:-}" == -C ]]; then args=("${args[@]:2}"); fi
cmd="${args[*]}"
state="${TEST_REPO_STATE:-current}"
case "$cmd" in
  'rev-parse --is-inside-work-tree') printf 'true\n' ;;
  'rev-parse --is-bare-repository') printf 'false\n' ;;
  'remote get-url origin')
    [[ "$state" == no-origin ]] && exit 2
    [[ "$state" == wrong-origin ]] && { printf 'https://github.com/other/dotfiles.git\n'; exit 0; }
    printf 'https://github.com/PamuduW/dotfiles.git\n' ;;
  'symbolic-ref -q --short HEAD') [[ "$state" == detached ]] && exit 1; printf 'main\n' ;;
  'rev-parse --abbrev-ref --symbolic-full-name @{upstream}')
    [[ "$state" == no-upstream ]] && exit 1
    [[ "$state" == other-remote ]] && { printf 'fork/main\n'; exit 0; }
    printf 'origin/main\n' ;;
  'status --short --untracked-files=all')
    case "$state" in
      dirty|dirty-current|dirty-ahead|dirty-behind|dirty-diverged)
        printf ' M scripts/example.sh\n?? local-change\n'
        ;;
      status-failure) exit 25 ;;
    esac ;;
  'fetch --prune')
    if [[ "$state" == fetch-failure || "${TEST_FETCH_FAILURE:-0}" == 1 ]]; then printf 'fetch diagnostic\n' >&2; exit 23; fi
    [[ "$state" == fetch-output ]] && printf 'From github.com:PamuduW/dotfiles\n'
    exit 0 ;;
  'rev-list --left-right --count HEAD...@{upstream}')
    case "$state" in
      ahead|dirty-ahead) printf '2\t0\n' ;;
      behind|dirty-behind|pull-failure) printf '0\t3\n' ;;
      diverged|dirty-diverged) printf '2\t3\n' ;;
      *) printf '0\t0\n' ;;
    esac ;;
  'pull --ff-only')
    if [[ "$state" == pull-failure ]]; then printf 'pull diagnostic\n' >&2; exit 24; fi
    exit 0 ;;
  'status -sb') printf '## main\n' ;;
  *) printf 'unexpected fake git call: %s\n' "$cmd" >&2; exit 97 ;;
esac
FAKE
	chmod 700 "$TEST_FAKE_BIN/git"
}

confirm_state() { [[ "${TEST_CONFIRM:-no}" == yes ]]; }
declare -A TEST_REPO_RESULT=()
run_gate() {
	TEST_REPO_STATE="$1" TEST_CONFIRM="${2:-no}"
	export TEST_REPO_STATE TEST_CONFIRM
	TEST_REPO_RESULT=()
	repo_update_run "$TEST_HARNESS_ROOT/repo" 'dotfiles repo' confirm_state TEST_REPO_RESULT 'PamuduW/dotfiles' >/dev/null 2>&1
	TEST_REPO_RC=$?
	return 0
}
pull_count() { grep -c $'git\t-C\t.*\tpull\t--ff-only$' "$TEST_COMMAND_LOG" || true; }

install_state_git_fake
[[ -f "$REPO_DIR/scripts/lib/repo_update.sh" ]] && source "$REPO_DIR/scripts/lib/repo_update.sh"
DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/bin/bin/dotfiles" >/dev/null
source "$REPO_DIR/scripts/lib/shared/tui/menu_runner.sh"
source "$REPO_DIR/scripts/menus/initial_setup.sh"
source "$REPO_DIR/scripts/menus/update.sh"
