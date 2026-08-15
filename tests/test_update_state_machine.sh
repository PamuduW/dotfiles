#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

passed=0 failed=0
pass() { printf 'ok - %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; failed=$((failed + 1)); }
expect_success() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

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
  'remote get-url origin') [[ "$state" == no-origin ]] && exit 2; printf 'https://github.com/example/dotfiles.git\n' ;;
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
run_gate() { TEST_REPO_STATE="$1" TEST_CONFIRM="${2:-no}"; export TEST_REPO_STATE TEST_CONFIRM; repo_update_gate "$TEST_HARNESS_ROOT/repo" confirm_state >/dev/null 2>&1; }
pull_count() { grep -c $'git\t-C\t.*\tpull\t--ff-only$' "$TEST_COMMAND_LOG" || true; }

test_state_table_outcomes() {
	local pair state expected
	for pair in current:current dirty:stopped detached:stopped no-upstream:stopped other-remote:stopped diverged:stopped fetch-failure:stopped; do
		state="${pair%%:*}" expected="${pair#*:}"; test_harness_reset_logs; run_gate "$state" no
		if [[ "$REPO_UPDATE_OUTCOME" != "$expected" ]]; then
			printf 'state %s: expected %s, got %s (%s)\n' "$state" "$expected" "$REPO_UPDATE_OUTCOME" "${REPO_UPDATE_REASON:-none}" >&2
			return 1
		fi
	done
}

test_dirty_history_matrix_fetches_classifies_and_stops() {
	local pair state expected
	for pair in dirty-current:current dirty-ahead:ahead dirty-behind:behind dirty-diverged:diverged; do
		state="${pair%%:*}" expected="${pair#*:}"
		test_harness_reset_logs
		run_gate "$state" yes
		[[ "$REPO_UPDATE_OUTCOME" == stopped && "$REPO_UPDATE_STATE" == "$expected" ]] || return 1
		[[ "$REPO_UPDATE_REASON" == dirty && "$REPO_UPDATE_DIRTY" == 1 ]] || return 1
		[[ "$REPO_UPDATE_CHANGES" == *' M scripts/example.sh'* && "$REPO_UPDATE_UPSTREAM" == origin/main ]] || return 1
		grep -Eq $'git\t-C\t.*\tfetch\t--prune$' "$TEST_COMMAND_LOG" || return 1
		grep -Eq $'git\t-C\t.*\trev-list\t--left-right\t--count\tHEAD\.\.\.@\{upstream\}$' "$TEST_COMMAND_LOG" || return 1
		[[ "$(pull_count)" -eq 0 ]] || return 1
	done
}

test_dirty_fetch_failure_preserves_changes_and_unknown_freshness() {
	test_harness_reset_logs
	TEST_REPO_STATE=dirty-current TEST_CONFIRM=yes TEST_FETCH_FAILURE=1
	export TEST_REPO_STATE TEST_CONFIRM TEST_FETCH_FAILURE
	repo_update_gate "$TEST_HARNESS_ROOT/repo" confirm_state >/dev/null 2>&1
	unset TEST_FETCH_FAILURE
	[[ "$REPO_UPDATE_OUTCOME" == stopped && "$REPO_UPDATE_REASON" == fetch-failed ]] || return 1
	[[ "$REPO_UPDATE_DIRTY" == 1 && "$REPO_UPDATE_CHANGES" == *'?? local-change'* ]] || return 1
	! grep -Eq $'git\t-C\t.*\trev-list\t' "$TEST_COMMAND_LOG"
}

test_status_failure_stops_before_fetch() {
	test_harness_reset_logs
	run_gate status-failure yes
	[[ "$REPO_UPDATE_OUTCOME" == stopped && "$REPO_UPDATE_REASON" == status-failed ]] || return 1
	! grep -Eq $'git\t-C\t.*\t(fetch|rev-list|pull)(\t|$)' "$TEST_COMMAND_LOG"
}

test_git_sequence_captures_changes_before_fetch_and_classification() {
	test_harness_reset_logs
	run_gate dirty-behind yes
	local status_line fetch_line classify_line
	status_line="$(grep -n $'git\t-C\t.*\tstatus\t--short\t--untracked-files=all$' "$TEST_COMMAND_LOG" | cut -d: -f1)"
	fetch_line="$(grep -n $'git\t-C\t.*\tfetch\t--prune$' "$TEST_COMMAND_LOG" | cut -d: -f1)"
	classify_line="$(grep -n $'git\t-C\t.*\trev-list\t--left-right\t--count' "$TEST_COMMAND_LOG" | cut -d: -f1)"
	[[ -n "$status_line" && -n "$fetch_line" && -n "$classify_line" ]] || return 1
	((status_line < fetch_line && fetch_line < classify_line))
}

test_only_confirmed_behind_pulls() {
	test_harness_reset_logs; run_gate behind no; [[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	test_harness_reset_logs; run_gate behind yes; [[ "$REPO_UPDATE_OUTCOME" == relaunch_required && "$(pull_count)" -eq 1 ]]
}

test_blocked_states_never_pull() {
	local state
	for state in dirty detached no-upstream other-remote diverged fetch-failure; do test_harness_reset_logs; run_gate "$state" yes; [[ "$(pull_count)" -eq 0 ]] || return 1; done
	test_harness_reset_logs; run_gate pull-failure yes; [[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 1 ]]
}

test_non_origin_upstream_stops_before_fetch() {
	test_harness_reset_logs
	run_gate other-remote yes
	[[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	! grep -Eq $'git\t-C\t.*\t(fetch|pull)(\t|$)' "$TEST_COMMAND_LOG"
}

test_ahead_requires_continue() {
	test_harness_reset_logs; run_gate ahead no; [[ "$REPO_UPDATE_OUTCOME" == stopped && "$(pull_count)" -eq 0 ]] || return 1
	test_harness_reset_logs; run_gate ahead yes; [[ "$REPO_UPDATE_OUTCOME" == ahead_continue && "$(pull_count)" -eq 0 ]]
}

test_success_requires_relaunch_without_old_work() {
	test_harness_reset_logs; run_gate behind yes
	[[ "$REPO_UPDATE_OUTCOME" == relaunch_required ]] || return 1
	! grep -Eq $'^(apt-get|sudo|stow|curl|npx)\t' "$TEST_COMMAND_LOG"
}

test_relaunch_is_injectable() (
	local called="$TEST_HARNESS_ROOT/relaunch.called"
	repo_update_relaunch() { printf '%s\n' "$*|${SETUP_CALLER:-}" >"$called"; }
	SETUP_CALLER=dotfiles repo_update_relaunch dotfiles update --all
	grep -Fqx 'dotfiles update --all|dotfiles' "$called" && [[ ! -e "$TEST_FAKE_BIN/exec" ]]
)

test_cmd_update_executes_outcome_contract() (
	local events="$TEST_HARNESS_ROOT/cmd-update.events" replies=''
	: >"$events"
	repo_update_gate() { printf 'gate\n' >>"$events"; REPO_UPDATE_OUTCOME="${TEST_GATE_OUTCOME:?}"; }
	_dotfiles_confirm() {
		local answer="${replies%% *}"
		[[ "$replies" == *' '* ]] && replies="${replies#* }" || replies=''
		printf 'confirm:%s\n' "$1" >>"$events"
		[[ "$answer" == yes ]]
	}
	print_report_table() { printf 'report\n' >>"$events"; }
	print_upgrade_summary() { printf 'summary:%s\n' "$1" >>"$events"; }
	_run_update_downstream() { printf 'downstream:%s\n' "$1" >>"$events"; }
	repo_update_relaunch() { printf 'relaunch:%s|%s\n' "$*" "${SETUP_CALLER:-}" >>"$events"; }
	_dotfiles_wait_for_reload() { printf 'wait\n' >>"$events"; }

	TEST_GATE_OUTCOME=stopped
	if cmd_update >/dev/null 2>&1; then return 1; fi
	[[ "$(<"$events")" == gate ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=current; replies=no
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == gate && "$(sed -n '2p' "$events")" == report && "$(sed -n '3p' "$events")" == confirm:* ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=current; replies='yes no'
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == gate && "$(sed -n '2p' "$events")" == report && "$(sed -n '3p' "$events")" == confirm:* && "$(sed -n '4p' "$events")" == confirm:* && "$(sed -n '5p' "$events")" == downstream:false && "$(sed -n '6p' "$events")" == summary:false ]] || return 1
	grep -Fqx 'confirm:Include Node.js, npm, Go, and Monaspace fonts (--all)?' "$events" || return 1

	: >"$events"; TEST_GATE_OUTCOME=current; replies='yes yes'
	cmd_update >/dev/null || return 1
	[[ "$(sed -n '5p' "$events")" == downstream:true && "$(sed -n '6p' "$events")" == summary:true ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=ahead_continue; replies=yes
	cmd_update --all >/dev/null || return 1
	[[ "$(sed -n '3p' "$events")" == confirm:* && "$(sed -n '4p' "$events")" == downstream:true && "$(sed -n '5p' "$events")" == summary:true ]] || return 1

	: >"$events"; TEST_GATE_OUTCOME=relaunch_required; replies=yes; SETUP_CALLER=dotfiles
	cmd_update --all >/dev/null || return 1
	grep -Fq "wait" "$events" || return 1
	grep -Fq "relaunch:${DOTFILES_DIR}/install.sh|dotfiles" "$events" || return 1
	! grep -Fq downstream "$events"
)

test_cmd_update_reports_dirty_paths_and_remote_state_before_stopping() (
	repo_update_gate() {
		REPO_UPDATE_OUTCOME=stopped
		REPO_UPDATE_REASON=dirty
		REPO_UPDATE_STATE=behind
		REPO_UPDATE_AHEAD=0
		REPO_UPDATE_BEHIND=3
		REPO_UPDATE_DIRTY=1
		REPO_UPDATE_UPSTREAM=origin/main
		REPO_UPDATE_CHANGES=$' M scripts/example.sh\n?? local-change'
	}
	local output rc
	set +e; output="$(cmd_update 2>&1)"; rc=$?; set -e
	[[ "$rc" -ne 0 && "$output" == *'Repository update'* ]] || return 1
	[[ "$output" == *'2 local change(s)'* && "$output" == *'blocked'* ]] || return 1
	[[ "$output" == *'origin/main'* && "$output" == *'3 commit(s) behind'* ]] || return 1
	[[ "$output" == *' M scripts/example.sh'* && "$output" == *'?? local-change'* ]] || return 1
	[[ "$output" == *'Repository pull and downstream updates stopped.'* ]]
)

test_dirty_change_report_is_bounded_and_copyable() (
	local i output status_lines='' printed
	for i in $(seq 1 22); do status_lines+="?? path-${i}"$'\n'; done
	REPO_UPDATE_CHANGES="${status_lines%$'\n'}"
	output="$(_print_repo_update_changes)"
	printed="$(grep -c '^  ?? path-' <<<"$output")"
	[[ "$printed" -eq 20 && "$output" == *'... 2 more local change(s)'* ]] || return 1
	[[ "$output" == *'git -C '* && "$output" == *' status --short --untracked-files=all'* ]]
)

test_downstream_executes_apt_first_and_all_matrix() (
	local events="$TEST_HARNESS_ROOT/downstream.events"
	: >"$events"
	sudo() { printf 'sudo:%s\n' "$*" >>"$events"; }
	npm_available_version() { printf '12.0.2\n'; }
	_run_upgrade_step() {
		printf 'step:%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" >>"$events"
		UPGRADE_STEP_RESULT["$1"]=ok
	}

	_run_update_downstream false >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == 'sudo:apt-get update -qq' ]] || return 1
	grep -Fq 'step:apt packages|' "$events" || return 1
	! grep -Eq 'step:(Node.js \(nvm\)|npm|Go \(asdf\)|Monaspace fonts)\|' "$events" || return 1

	: >"$events"
	_run_update_downstream true >/dev/null || return 1
	[[ "$(sed -n '1p' "$events")" == 'sudo:apt-get update -qq' ]] || return 1
	grep -Fq 'step:Graphify CLI|' "$events" || return 1
	grep -Fq 'step:Node.js (nvm)|' "$events" || return 1
	grep -Fqx 'step:npm|npm install -g npm@12.0.2 --engine-strict --allow-remote=all|upgrade_npm|12.0.2' "$events" || return 1
	grep -Fq 'step:Go (asdf)|' "$events" || return 1
	grep -Fq 'step:Monaspace fonts|' "$events"
)

test_node_probe_uses_nvm_default_when_shell_path_is_stale() (
	_load_nvm() { :; }
	node() { printf 'v24.16.0\n'; }
	nvm() {
		if [[ "$1 ${2:-}" == 'version default' ]]; then
			printf 'v24.18.0\n'
			return 0
		fi
		return 1
	}

	[[ "$(node_installed_version)" == '24.18.0' ]]
)

test_npm_probe_reports_upgrade_current_and_missing_states() (
	local output npm_mode=upgrade
	_load_nvm() { :; }
	npm() {
		case "$*" in
		--version)
			[[ "$npm_mode" == current ]] && printf '12.0.1\n' || printf '11.16.0\n'
			;;
		'view npm version') printf '12.0.1\n' ;;
		*) return 97 ;;
		esac
	}

	output="$(check_npm || true)"
	[[ "$output" == 'npm|11.16.0|12.0.1|upgrade (--all)' ]] || return 1

	npm_mode=current
	output="$(check_npm || true)"
	[[ "$output" == 'npm|12.0.1|12.0.1|up to date' ]] || return 1

	unset -f npm
	command() {
		[[ "$*" == '-v npm' ]] && return 1
		builtin command "$@"
	}
	output="$(check_npm || true)"
	[[ "$output" == 'npm|not installed|—|skip' ]]
)

test_npm_version_reached_requires_a_safe_equal_or_newer_version() (
	local installed=12.0.2
	npm_installed_version() { printf '%s\n' "$installed"; }

	npm_version_reached 12.0.2 || return 1
	installed=12.1.0
	npm_version_reached 12.0.2 || return 1
	installed=12.0.1
	! npm_version_reached 12.0.2 || return 1
	installed="$NOT_INSTALLED"
	! npm_version_reached 12.0.2 || return 1
	installed=garbage
	! npm_version_reached 12.0.2 || return 1
	! npm_version_reached 'latest;touch /tmp/nope'
)

test_npm_upgrade_accepts_verified_nvm_result() (
	local installed=12.0.1 calls="$TEST_HARNESS_ROOT/npm-nvm-success.calls"
	: >"$calls"
	_load_nvm() { :; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		*) printf 'npm:%s\n' "$*" >>"$calls"; return 97 ;;
		esac
	}
	nvm() { printf 'nvm:%s\n' "$*" >>"$calls"; installed=12.0.2; }

	upgrade_npm 12.0.2 || return 1
	grep -Fqx 'nvm:install-latest-npm' "$calls" || return 1
	! grep -Fq 'npm:install' "$calls"
)

test_npm_upgrade_falls_back_after_false_nvm_success() (
	local installed=12.0.1 calls="$TEST_HARNESS_ROOT/npm-false-success.calls"
	: >"$calls"
	_load_nvm() { :; }
	nvm() { printf 'nvm:%s\n' "$*" >>"$calls"; return 0; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all')
			printf 'npm:%s\n' "$*" >>"$calls"
			installed=12.0.2
			;;
		*) return 97 ;;
		esac
	}

	upgrade_npm 12.0.2 || return 1
	grep -Fqx 'npm:install -g npm@12.0.2 --engine-strict --allow-remote=all' "$calls"
)

test_npm_upgrade_fallback_can_recover_from_nvm_failure() (
	local installed=12.0.1
	_load_nvm() { :; }
	nvm() { return 23; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') installed=12.0.2 ;;
		*) return 97 ;;
		esac
	}

	upgrade_npm 12.0.2
)

test_npm_upgrade_fails_when_fallback_command_fails() (
	local installed=12.0.1
	_load_nvm() { :; }
	nvm() { return 0; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') return 24 ;;
		*) return 97 ;;
		esac
	}

	if upgrade_npm 12.0.2; then return 1; fi
)

test_npm_upgrade_fails_when_fallback_leaves_old_version() (
	local installed=12.0.1
	_load_nvm() { :; }
	nvm() { return 0; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') return 0 ;;
		*) return 97 ;;
		esac
	}

	if upgrade_npm 12.0.2; then return 1; fi
)

test_npm_upgrade_skips_commands_when_already_current() (
	local installed=12.0.2 calls="$TEST_HARNESS_ROOT/npm-current.calls"
	: >"$calls"
	_load_nvm() { :; }
	nvm() { printf 'nvm:%s\n' "$*" >>"$calls"; return 97; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		*) printf 'npm:%s\n' "$*" >>"$calls"; return 97 ;;
		esac
	}

	upgrade_npm 12.0.2 || return 1
	[[ ! -s "$calls" ]]
)

test_npm_failed_postcheck_sets_retryable_failed_step() (
	local installed=12.0.1 output="$TEST_HARNESS_ROOT/npm-failed-step.output"
	_load_nvm() { :; }
	nvm() { return 0; }
	npm() {
		case "$*" in
		--version) printf '%s\n' "$installed" ;;
		'install -g npm@12.0.2 --engine-strict --allow-remote=all') return 0 ;;
		*) return 97 ;;
		esac
	}
	C_BOLD='' C_YELLOW='' C_RED=$'\033[31m' C_RESET=$'\033[0m'

	_run_upgrade_step 'npm' 'npm install -g npm@12.0.2 --engine-strict --allow-remote=all' upgrade_npm 12.0.2 >"$output" 2>&1
	[[ "${UPGRADE_STEP_RESULT[npm]}" == failed ]] || return 1
	grep -Fq 'retry manually: npm install -g npm@12.0.2 --engine-strict --allow-remote=all' "$output"
)

test_unverifiable_cli_probes_label_latest_unchecked() (
	local output
	agent() { [[ "$1" == --version ]] && printf '2026.07.23-e383d2b\n'; }
	claude() { [[ "$1" == --version ]] && printf '2.1.220 (Claude Code)\n'; }
	copilot() { [[ "$1" == --version ]] && printf 'GitHub Copilot CLI 1.0.75.\n'; }

	output="$(check_cursor_cli || true)"
	[[ "$output" == 'Cursor CLI|2026.07.23-e383d2b|—|latest unchecked' ]] || return 1
	output="$(check_claude_cli || true)"
	[[ "$output" == 'Claude CLI|2.1.220 (Claude Code)|—|latest unchecked' ]] || return 1
	output="$(check_copilot_cli || true)"
	[[ "$output" == 'Copilot CLI|GitHub Copilot CLI 1.0.75.|—|latest unchecked' ]]
)

test_graphify_probe_reports_uv_owned_and_external_states() (
	local output
	graphify() { [[ "$1" == --version ]] && printf 'graphify 1.2.3\n'; }
	uv() {
		case "$*" in
		'tool list') printf '%s\n' 'graphifyy v1.2.3' ;;
		*) return 97 ;;
		esac
	}
	output="$(check_graphify_cli || true)"
	[[ "$output" == 'Graphify CLI|graphify 1.2.3|—|latest unchecked' ]] || return 1

	uv() {
		[[ "$*" == 'tool list' ]] && printf '%s\n' 'other-tool v1.0.0'
	}
	output="$(check_graphify_cli || true)"
	[[ "$output" == 'Graphify CLI|graphify 1.2.3|—|externally managed' ]]
)

test_graphify_probe_skips_when_not_installed() (
	local output
	graphify_command() { return 1; }
	output="$(check_graphify_cli || true)"
	[[ "$output" == 'Graphify CLI|not installed|—|skip' ]]
)

test_graphify_upgrade_uses_uv_tool_upgrade() (
	local output calls="$TEST_HARNESS_ROOT/graphify-upgrade.calls"
	: >"$calls"
	graphify() { [[ "$1" == --version ]] && printf 'graphify 1.2.3\n'; }
	agentbot() { printf 'agentbot:%s\n' "$*" >>"$calls"; return 97; }
	uv() {
		printf 'uv:%s\n' "$*" >>"$calls"
		case "$*" in
		'tool list') printf '%s\n' 'graphifyy v1.2.3' ;;
		'tool upgrade graphifyy') return 0 ;;
		*) return 97 ;;
		esac
	}
	output="$(upgrade_graphify_cli)" || return 1
	grep -Fqx 'uv:tool upgrade graphifyy' "$calls" || return 1
	! grep -Fq 'agentbot:' "$calls" || return 1
	grep -Fq "If Agentbot's Graphify integration is enabled, run agentbot graphify setup" <<<"$output" || return 1
	grep -Fq 'or agentbot update to refresh the installed skill.' <<<"$output"
)

test_graphify_upgrade_failure_has_copyable_retry_command() (
	local output calls="$TEST_HARNESS_ROOT/graphify-failure.calls"
	: >"$calls"
	graphify() { [[ "$1" == --version ]] && printf 'graphify 1.2.3\n'; }
	uv() {
		printf 'uv:%s\n' "$*" >>"$calls"
		case "$*" in
		'tool list') printf '%s\n' 'graphifyy v1.2.3' ;;
		'tool upgrade graphifyy') return 23 ;;
		*) return 97 ;;
		esac
	}
	C_RED=$'\033[31m' C_RESET=$'\033[0m'
	output="$(_run_upgrade_step 'Graphify CLI' 'uv tool upgrade graphifyy' upgrade_graphify_cli 2>&1)"
	grep -Fqx 'uv:tool upgrade graphifyy' "$calls"
	grep -Fq 'retry manually: uv tool upgrade graphifyy' <<<"$output" || return 1
	! grep -Fq "Agentbot's Graphify integration" <<<"$output"
)

test_upgrade_step_marks_failures_in_red_with_retry_command() (
	local output
	C_BOLD='' C_YELLOW='' C_RED=$'\033[31m' C_RESET=$'\033[0m'
	_failing_probe() { return 7; }

	output="$(_run_upgrade_step 'probe' 'probe --retry' _failing_probe 2>&1)"
	grep -Fq $'\033[31m>> FAILED (exit 7) — retry manually: probe --retry <<\033[0m' <<<"$output"
)

test_upgrade_step_omits_failure_marker_after_success() (
	local output
	C_BOLD='' C_YELLOW='' C_RED=$'\033[31m' C_RESET=$'\033[0m'
	_successful_probe() { printf 'probe ok\n'; }

	output="$(_run_upgrade_step 'probe' 'probe --retry' _successful_probe 2>&1)"
	grep -Fq 'probe ok' <<<"$output" || return 1
	! grep -Fq '>> FAILED' <<<"$output"
)

test_node_upgrade_stops_when_nvm_install_fails() (
	local calls="$TEST_HARNESS_ROOT/node-upgrade.calls"
	: >"$calls"
	_load_nvm() { :; }
	nvm() {
		printf 'nvm:%s\n' "$*" >>"$calls"
		[[ "$1" != install ]]
	}

	if upgrade_node; then
		return 1
	fi
	grep -Fqx 'nvm:install --lts' "$calls" || return 1
	! grep -Fq 'nvm:alias' "$calls"
)

test_go_upgrade_stops_when_asdf_install_fails() (
	local calls="$TEST_HARNESS_ROOT/go-upgrade.calls"
	: >"$calls"
	asdf() {
		printf 'asdf:%s\n' "$*" >>"$calls"
		[[ "$1" != install ]]
	}

	if upgrade_go; then
		return 1
	fi
	grep -Fqx 'asdf:install golang latest' "$calls" || return 1
	! grep -Eq '^asdf:(set|reshim)' "$calls"
)

test_cursor_update_falls_back_to_official_installer() (
	local calls="$TEST_HARNESS_ROOT/cursor-update.calls" output="$TEST_HARNESS_ROOT/cursor-update.output"
	: >"$calls"
	C_RED=$'\033[31m' C_RESET=$'\033[0m'
	export C_RED C_RESET
	agent() {
		printf 'agent:%s\n' "$*" >>"$calls"
		return 7
	}
	curl() {
		printf 'curl:%s\n' "$*" >>"$calls"
		printf '%s\n' 'printf "official-installer\n"'
	}

	if ! upgrade_cursor_cli >"$output" 2>&1; then
		return 1
	fi
	grep -Fqx 'agent:update' "$calls" || return 1
	grep -Fqx 'curl:-fsSL https://cursor.com/install' "$calls" || return 1
	grep -Fqx 'official-installer' "$output" || return 1
	grep -Fq $'\033[31m>> FAILED (exit 7) — retry manually: agent update <<\033[0m' "$output"
)

test_apt_report_probe_uses_cached_indices_without_sudo() (
	local count sudo_calls=0
	apt-get() { printf '%s\n' 'Inst cached-package'; }
	sudo() { sudo_calls=$((sudo_calls + 1)); return 99; }
	count="$(apt_upgradable_count)"
	[[ "$count" -eq 1 ]] || return 1
	[[ "$sudo_calls" -eq 0 ]]
)

test_update_report_uses_clear_title_spacing_and_aligned_action_rule() (
	local output_file="$TEST_HARNESS_ROOT/update-report.output"
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|up to date'; }
	NO_COLOR=1 print_report_table >"$output_file"
	[[ "$(sed -n '1p' "$output_file")" == '==Update report==' ]] || return 1
	grep -Fq $'==Update report==\n\ncomponent' "$output_file" || return 1
	! grep -Fq 'Upgrade report' "$output_file" || return 1
	grep -Fq $'everything looks current.\n\n' "$output_file" || return 1
	grep -Eq '^-------------------\+------------------------------\+------------------------\+-----------------' "$output_file"
)

test_update_and_upgrade_rows_keep_the_last_column_width() (
	local output line_lengths
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|up to date'; }

	line_lengths="$(NO_COLOR=1 print_report_table | awk '/^(component|apt packages|---)/ { print length($0) }')"
	[[ "$line_lengths" == $'93\n93\n93' ]] || return 1

	line_lengths="$(NO_COLOR=1 print_upgrade_summary false | awk '/^(component|apt packages|---)/ { print length($0) }')"
	[[ "$line_lengths" == $'93\n93\n93' ]]
)

test_update_rows_align_unicode_available_cells() (
	local output
	_collect_check_rows() { printf '%s\n' 'Cursor CLI|2026.07.09-a3815c0|—|up to date'; }
	output="$(NO_COLOR=1 print_report_table)"
	awk '
	/^Cursor CLI/ {
		pipes=""
		for (i = 1; i <= length($0); i++) if (substr($0, i, 1) == "|") pipes = pipes i ","
		if (length($0) != 93 || pipes != "20,51,76,") exit 1
		found=1
	}
	END { exit(found ? 0 : 1) }
	' <<<"$output"
)

test_repository_update_preview_uses_semantic_colors() (
	local output prompt
	REPO_UPDATE_STATE=behind
	REPO_UPDATE_BEHIND=2
	C_BOLD=$'\033[1m' C_CYAN=$'\033[36m' C_ORANGE=$'\033[38;5;208m' C_DIM=$'\033[2m' C_YELLOW=$'\033[33m' C_RESET=$'\033[0m'
	output="$(_print_repo_update_table)"
	grep -Fq $'\033[1m\033[33mRepository update\033[0m' <<<"$output" || return 1
	! grep -Fq '==Repository update==' <<<"$output" || return 1
	grep -Fq $'\033[1mcomponent' <<<"$output" || return 1
	grep -Fq $'\033[2m-------------------+' <<<"$output" || return 1
	grep -Fq $'\033[33m2 commit(s) behind' <<<"$output" || return 1
	grep -Fq $'\033[36mpull --ff-only' <<<"$output" || return 1

	if prompt="$(printf 'n\n' | _dotfiles_confirm 'Pull 2 commit(s) with --ff-only?')"; then
		return 1
	fi
	grep -Fq $'\033[33mPull 2 commit(s) with --ff-only?' <<<"$prompt"
)

test_update_topics_use_submenu_yellow() (
	local output
	C_BOLD=$'\033[1m' C_CYAN=$'\033[36m' C_ORANGE=$'\033[38;5;208m' C_YELLOW=$'\033[33m' C_RESET=$'\033[0m'
	_collect_check_rows() { printf '%s\n' 'apt packages|system packages|none|up to date'; }
	output="$(print_report_table)" 2>/dev/null || true
	grep -Fq $'\033[33m==Update report==' <<<"$output" || return 1

	_upgrade_topic_probe() { :; }
	output="$(_run_upgrade_step lazygit 'dotfiles update' _upgrade_topic_probe)"
	grep -Fq $'\033[33m== lazygit ==' <<<"$output" || return 1

	repo_update_gate() { REPO_UPDATE_OUTCOME=current; }
	print_report_table() { :; }
	_dotfiles_confirm() { return 0; }
	_run_update_downstream() { :; }
	print_upgrade_summary() { :; }
	output="$(cmd_update)"
	grep -Fq $'\033[38;5;208m=== Upgrade ===' <<<"$output"
)

test_repository_fetch_notice_uses_cyan() (
	local output
	C_CYAN=$'\033[36m' C_RESET=$'\033[0m'
	TEST_REPO_STATE=fetch-output
	export TEST_REPO_STATE
	output="$(repo_update_gate "$TEST_HARNESS_ROOT/repo" confirm_state 2>&1)" || return 1
	grep -Fq $'\033[36mFrom github.com:PamuduW/dotfiles' <<<"$output"
)

test_repository_fetch_notice_colors_each_line() (
	local output
	C_CYAN=$'\033[36m' C_RESET=$'\033[0m'
	output="$(_repo_update_print_fetch_output $'From github.com:PamuduW/dotfiles\n   42abceb..9a0f501  main -> origin/main')"
	[[ "$output" == *$'\033[36mFrom github.com:PamuduW/dotfiles\033[0m'* ]] || return 1
	[[ "$output" == *$'\033[36m   42abceb..9a0f501  main -> origin/main\033[0m'* ]]
)

test_update_apply_uses_high_level_upgrade_heading_without_opt_in_plan() (
	local output
	repo_update_gate() { REPO_UPDATE_OUTCOME=current; }
	print_report_table() { :; }
	_dotfiles_confirm() { return 0; }
	_run_update_downstream() { printf '%s\n' '== apt packages =='; }
	print_upgrade_summary() { :; }
	output="$(cmd_update)"
	grep -Fq '=== Upgrade ===' <<<"$output" || return 1
	grep -Fq '== apt packages ==' <<<"$output" || return 1
	! grep -Fq 'Opt-in plan:' <<<"$output"
)

test_upgrade_summary_marks_repo_gate_as_handled() (
	_collect_check_rows() { printf '%s\n' 'dotfiles repo|main@abc123|none|up to date'; }
	local output
	output="$(print_upgrade_summary false)"
	grep -Fq 'dotfiles repo' <<<"$output" || return 1
	grep -Fq '| ok' <<<"$output"
)

test_tui_runs_shared_update_without_submenu() (
	local fake_dotfiles="$TEST_HARNESS_ROOT/fake-dotfiles"
	local events="$TEST_HARNESS_ROOT/tui-update.events" tty_output="$TEST_HARNESS_ROOT/tui-update.tty"
	cat >"$fake_dotfiles" <<'FAKE'
#!/usr/bin/env bash
printf 'dotfiles:%s\n' "$*" >>"${TEST_TUI_EVENTS:?}"
exit "${TEST_DOTFILES_RC:-0}"
FAKE
	chmod 700 "$fake_dotfiles"
	export TEST_TUI_EVENTS="$events" DOTFILES_TTY_PATH="$tty_output"
	: >"$events"
	resolve_dotfiles_cmd() { printf '%s\n' "$fake_dotfiles"; }
	ui_print_header() { printf 'header:%s|%s\n' "$1" "$2"; }

	run_update_flow || return 1
	[[ "$(sed -n '1p' "$events")" == 'dotfiles:update' && "$(wc -l <"$events")" -eq 1 ]] || return 1
	grep -Fq 'header:Update|Dotfiles › Update' "$tty_output" || return 1
	! declare -F update_menu >/dev/null 2>&1
)

test_tui_detects_a_relaunched_update_child() (
	local fake_dotfiles="$TEST_HARNESS_ROOT/fake-relaunch-dotfiles"
	local tty_output="$TEST_HARNESS_ROOT/relaunch-update.tty"
	cat >"$fake_dotfiles" <<'FAKE'
#!/usr/bin/env bash
: >"${DOTFILES_RELAUNCH_MARKER:?}"
FAKE
	chmod 700 "$fake_dotfiles"
	export DOTFILES_TTY_PATH="$tty_output"
	resolve_dotfiles_cmd() { printf '%s\n' "$fake_dotfiles"; }
	ui_print_header() { :; }
	run_update_flow || return 1
	[[ "${DOTFILES_UPDATE_RELAUNCHED:-false}" == true ]]
)

test_stopped_paths_have_no_downstream() {
	test_harness_reset_logs; run_gate dirty yes
	! grep -Eq $'^(apt-get|sudo|stow|curl|npx)\t' "$TEST_COMMAND_LOG"
}

test_status_is_strictly_local() {
	local output="$TEST_HARNESS_ROOT/status.out"
	test_harness_reset_logs; TEST_REPO_STATE=current "$REPO_DIR/bin/bin/dotfiles" status >"$output"
	grep -Fqi unchecked "$output" || return 1
	! grep -Eq $'git\t.*\t(fetch|pull|ls-remote)(\t|$)|^(curl|npx|sudo|stow|apt-get)\t' "$TEST_COMMAND_LOG"
}

test_root_tui_status_omits_unchecked_freshness_without_network() (
	local output="$TEST_HARNESS_ROOT/root-status.output"
	export DOTFILES_STATUS_OUTPUT="$output"
	COMP_KEYS=(sample)
	COMP_LABELS=('Sample')
	menu_tty_cols() { printf '80\n'; }
	ui_clear() { :; }
	ui_print_header() { printf 'header:%s|%s\n' "$1" "$2"; }
	ui_print_report_table_columns() { printf 'columns\n'; }
	_install_summary_probe() { printf 'installed|present\n'; }
	_install_short_label() { printf '%s\n' "$1"; }
	ui_print_report_table_row() { printf 'row:%s|%s|%s\n' "$1" "$2" "$3"; }
	ui_print_report_rollup() { printf 'rollup:%s|%s|%s\n' "$1" "$2" "$3"; }
	test_harness_reset_logs
	run_status_action || return 1
	! grep -Fqi 'apt/package freshness: unchecked' "$output" || return 1
	! grep -Fqi 'repository freshness: unchecked' "$output" || return 1
	[[ ! -s "$TEST_COMMAND_LOG" && ! -s "$TEST_URL_LOG" ]]
)

test_root_status_rollup_has_one_blank_line() (
	local output="$TEST_HARNESS_ROOT/root-status-rollup.output"
	export DOTFILES_STATUS_OUTPUT="$output"
	COMP_KEYS=(sample)
	COMP_LABELS=('Sample')
	menu_tty_cols() { printf '80\n'; }
	ui_clear() { :; }
	ui_print_header() { printf 'header:%s|%s\n' "$1" "$2"; }
	ui_print_report_table_columns() { rt_print_table_columns; }
	_install_summary_probe() { printf 'installed|present\n'; }
	_install_short_label() { printf '%s\n' "$1"; }
	ui_print_report_table_row() { rt_print_table_row "$@"; }
	ui_print_report_rollup() { rt_print_rollup "$@"; }
	NO_COLOR=1 run_status_action || return 1

	awk '
	/All 1 component\(s\) look good\./ {
		if (previous != "" || before_previous == "") exit 1
		found=1
	}
	{ before_previous=previous; previous=$0 }
	END { exit(found ? 0 : 1) }
	' "$output"
)

test_retained_capability_coverage() {
	declare -F cmd_status >/dev/null 2>&1 || return 1
	declare -F cmd_update >/dev/null 2>&1 || return 1
	declare -F cmd_restow >/dev/null 2>&1
}

test_removed_commands_have_guidance() {
	local cmd output rc
	for cmd in summary upgrade self; do
		set +e; output="$("$REPO_DIR/bin/bin/dotfiles" "$cmd" 2>&1)"; rc=$?; set -e
		[[ "$rc" -ne 0 ]] || return 1
		case "$cmd" in summary) [[ "$output" == *'use dotfiles status'* ]] ;; upgrade) [[ "$output" == *'use dotfiles update [--all]'* ]] ;; self) [[ "$output" == *'use dotfiles update'* && "$output" == *restow* ]] ;; esac || return 1
	done
}

test_exact_command_set_parity() {
	source "$REPO_DIR/scripts/lib/command_metadata.sh"
	local expected=(menu update status commands packages restow help) i
	[[ "${#DOTFILES_COMMAND_KEYS[@]}" -eq 7 ]] || return 1
	for i in "${!expected[@]}"; do [[ "${DOTFILES_COMMAND_KEYS[$i]}" == "${expected[$i]}" ]] || return 1; done
	dotfiles_command_metadata_validate_dispatch "$REPO_DIR/bin/bin/dotfiles"
}

test_harness_safety_and_no_real_mutation() {
	[[ "$(command -v git)" == "$TEST_FAKE_BIN/git" && ! -e "$TEST_FAKE_BIN/exec" ]] || return 1
	[[ "$HOME" == "$TEST_HARNESS_ROOT/home" && ! -s "$TEST_URL_LOG" ]]
}

install_state_git_fake
[[ -f "$REPO_DIR/scripts/lib/repo_update.sh" ]] && source "$REPO_DIR/scripts/lib/repo_update.sh"
DOTFILES_SOURCE_ONLY=1 source "$REPO_DIR/bin/bin/dotfiles" >/dev/null
source "$REPO_DIR/scripts/lib/menu_runner.sh"
source "$REPO_DIR/scripts/menus/initial_setup.sh"
source "$REPO_DIR/scripts/menus/update.sh"
REPO_UPDATE_OUTCOME="${REPO_UPDATE_OUTCOME:-missing}"
declare -F repo_update_gate >/dev/null || repo_update_gate() { REPO_UPDATE_OUTCOME=missing; return 1; }
declare -F repo_update_relaunch >/dev/null || repo_update_relaunch() { return 1; }
expect_success 'repository state table returns stable outcomes' test_state_table_outcomes
expect_success 'dirty current ahead behind and diverged states fetch classify and stop' test_dirty_history_matrix_fetches_classifies_and_stops
expect_success 'dirty fetch failure preserves paths and marks freshness unknown' test_dirty_fetch_failure_preserves_changes_and_unknown_freshness
expect_success 'failed local status probe stops before fetch' test_status_failure_stops_before_fetch
expect_success 'repository checks run status before fetch before classification' test_git_sequence_captures_changes_before_fetch_and_classification
expect_success 'only clean strictly-behind confirmed state pulls ff-only once' test_only_confirmed_behind_pulls
expect_success 'blocked declined and failed states never reach downstream' test_blocked_states_never_pull
expect_success 'non-origin upstream stops before fetch or pull' test_non_origin_upstream_stops_before_fetch
expect_success 'ahead never pulls and requires explicit continue confirmation' test_ahead_requires_continue
expect_success 'successful pull requires relaunch and stops old-process work' test_success_requires_relaunch_without_old_work
expect_success 'relaunch wrapper is injectable without a fake exec command' test_relaunch_is_injectable
expect_success 'cmd_update executes stopped current ahead and relaunch outcomes' test_cmd_update_executes_outcome_contract
expect_success 'cmd_update reports dirty paths and verified remote state before stopping' test_cmd_update_reports_dirty_paths_and_remote_state_before_stopping
expect_success 'dirty path report is bounded and includes a copyable full-list command' test_dirty_change_report_is_bounded_and_copyable
expect_success 'downstream execution runs apt refresh first and honors --all' test_downstream_executes_apt_first_and_all_matrix
expect_success 'Node.js probe follows nvm default instead of a stale shell PATH' test_node_probe_uses_nvm_default_when_shell_path_is_stale
expect_success 'npm probe reports upgrade current and missing states' test_npm_probe_reports_upgrade_current_and_missing_states
expect_success 'npm version verification accepts only safe equal or newer versions' test_npm_version_reached_requires_a_safe_equal_or_newer_version
expect_success 'npm upgrade accepts a verified NVM result' test_npm_upgrade_accepts_verified_nvm_result
expect_success 'npm upgrade uses the exact fallback after false NVM success' test_npm_upgrade_falls_back_after_false_nvm_success
expect_success 'npm fallback can recover from NVM failure' test_npm_upgrade_fallback_can_recover_from_nvm_failure
expect_success 'npm upgrade fails when the fallback command fails' test_npm_upgrade_fails_when_fallback_command_fails
expect_success 'npm upgrade fails when fallback leaves the old version installed' test_npm_upgrade_fails_when_fallback_leaves_old_version
expect_success 'npm upgrade skips NVM and npm install when already current' test_npm_upgrade_skips_commands_when_already_current
expect_success 'npm failed post-check records a copyable failed step' test_npm_failed_postcheck_sets_retryable_failed_step
expect_success 'unverifiable CLI probes label latest freshness unchecked' test_unverifiable_cli_probes_label_latest_unchecked
expect_success 'Graphify update probe distinguishes uv-owned and external installs' test_graphify_probe_reports_uv_owned_and_external_states
expect_success 'Graphify update probe skips an absent CLI' test_graphify_probe_skips_when_not_installed
expect_success 'Graphify update uses uv tool upgrade' test_graphify_upgrade_uses_uv_tool_upgrade
expect_success 'Graphify update failures include a copyable retry command' test_graphify_upgrade_failure_has_copyable_retry_command
expect_success 'upgrade step marks failures in red with retry command' test_upgrade_step_marks_failures_in_red_with_retry_command
expect_success 'upgrade step omits failure marker after success' test_upgrade_step_omits_failure_marker_after_success
expect_success 'Node.js upgrade stops when nvm install fails' test_node_upgrade_stops_when_nvm_install_fails
expect_success 'Go upgrade stops when asdf install fails' test_go_upgrade_stops_when_asdf_install_fails
expect_success 'Cursor update falls back to the official installer after agent update failure' test_cursor_update_falls_back_to_official_installer
expect_success 'pre-confirmation apt report probing never invokes sudo' test_apt_report_probe_uses_cached_indices_without_sudo
expect_success 'update report title spacing and action separator are stable' test_update_report_uses_clear_title_spacing_and_aligned_action_rule
expect_success 'update and upgrade rows preserve the fixed final column width' test_update_and_upgrade_rows_keep_the_last_column_width
expect_success 'update rows align a Unicode em-dash available cell' test_update_rows_align_unicode_available_cells
expect_success 'repository update preview uses semantic colors' test_repository_update_preview_uses_semantic_colors
expect_success 'update subtopics use the report yellow palette' test_update_topics_use_submenu_yellow
expect_success 'repository fetch notices use cyan' test_repository_fetch_notice_uses_cyan
expect_success 'repository fetch notices color each line independently' test_repository_fetch_notice_colors_each_line
expect_success 'update apply uses a high-level Upgrade heading without opt-in plan noise' test_update_apply_uses_high_level_upgrade_heading_without_opt_in_plan
expect_success 'upgrade summary marks the repo gate as handled' test_upgrade_summary_marks_repo_gate_as_handled
expect_success 'TUI runs shared update directly without a submenu' test_tui_runs_shared_update_without_submenu
expect_success 'TUI detects when the update child relaunched the installer' test_tui_detects_a_relaunched_update_child
expect_success 'stopped paths perform no apt tool network or stow work' test_stopped_paths_have_no_downstream
expect_success 'dotfiles status is strictly local and labels freshness unchecked' test_status_is_strictly_local
expect_success 'root TUI status omits unchecked apt and repository freshness locally' test_root_tui_status_omits_unchecked_freshness_without_network
expect_success 'root status rollup has exactly one blank line before the summary' test_root_status_rollup_has_one_blank_line
expect_success 'status update and restow retain removed command capabilities' test_retained_capability_coverage
expect_success 'summary upgrade and self fail with migration guidance' test_removed_commands_have_guidance
expect_success 'metadata help Command Lib and dispatch share seven keys' test_exact_command_set_parity
expect_success 'harness fakes prevent real repo network apt home and stow mutation' test_harness_safety_and_no_real_mutation

printf '%d test(s) passed; %d failed\n' "$passed" "$failed"
((failed == 0))
