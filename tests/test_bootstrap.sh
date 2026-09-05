#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
# Fresh-machine bootstrap: selection routing, adoption policy, and handoff order.
#
# The installers are exercised through real clones of local bare repositories
# whose install entry points only log their argv, so the test asserts what
# bootstrap actually invokes and in what order without running a real install.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
# The harness shadows git with a logging double; bootstrap needs the real one.
PATH="$ORIGINAL_PATH"
export PATH
test_harness_report_init

BOOTSTRAP="$REPO_DIR/bootstrap.sh"
REAL_GIT="$(command -v git)"
export GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL="$TEST_HARNESS_ROOT/empty.gitconfig"
: >"$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_GLOBAL

# A bare repository standing in for a GitHub remote. Its working tree carries
# only the entry points bootstrap hands off to.
make_remote() {
	# Declared separately on purpose: in `local a="$1" b="$a"` the second
	# assignment sees the *outer* `a`, and expect_success holds a `name` local
	# carrying the test description.
	local repo_name="$1"
	local work="$2/work"
	local bare="$2/$repo_name.git"
	mkdir -p -- "$work/bin/bin"
	cat >"$work/install.sh" <<EOF
#!/usr/bin/env bash
printf '$repo_name-install %s\n' "\$*" >>"\$BOOTSTRAP_TEST_LOG"
EOF
	cat >"$work/bin/bin/dotfiles" <<EOF
#!/usr/bin/env bash
printf '$repo_name-cli %s\n' "\$*" >>"\$BOOTSTRAP_TEST_LOG"
EOF
	chmod +x -- "$work/install.sh" "$work/bin/bin/dotfiles"
	# Every git call is silenced: this function returns the bare path on stdout,
	# and a single stray line of git output would be captured as part of it.
	{
		"$REAL_GIT" init -q -b main "$work" &&
			"$REAL_GIT" -C "$work" config user.name 'Bootstrap Test' &&
			"$REAL_GIT" -C "$work" config user.email 'bootstrap@example.invalid' &&
			"$REAL_GIT" -C "$work" add -A &&
			"$REAL_GIT" -C "$work" commit -q -m 'entry points' &&
			"$REAL_GIT" clone -q --bare "$work" "$bare"
	} >/dev/null 2>&1 || return 1
	rm -rf -- "$work"
	printf '%s\n' "$bare"
}

# One isolated machine: two fake remotes, empty destinations, a logging sudo,
# and every prerequisite present so the Agentbot phase is reachable.
setup_machine() {
	local dir="$TEST_HARNESS_ROOT/$1"
	rm -rf -- "$dir"
	mkdir -p -- "$dir/remotes" "$dir/home" "$dir/bin"
	MACHINE="$dir"
	BOOTSTRAP_TEST_LOG="$dir/invocations.log"
	: >"$BOOTSTRAP_TEST_LOG"
	DOTFILES_REMOTE="$(make_remote dotfiles "$dir/remotes")"
	AGENTBOT_REMOTE="$(make_remote agentbot "$dir/remotes")"
	cat >"$dir/bin/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$BOOTSTRAP_TEST_LOG"
EOF
	chmod +x -- "$dir/bin/sudo"
	export BOOTSTRAP_TEST_LOG
}

run_bootstrap() {
	local selection="$1"
	shift
	env PATH="$MACHINE/bin:$ORIGINAL_PATH" \
		HOME="$MACHINE/home" \
		NO_COLOR=1 \
		BOOTSTRAP_TEST_LOG="$BOOTSTRAP_TEST_LOG" \
		BOOTSTRAP_SELECTION="$selection" \
		BOOTSTRAP_ANSWERS="${BOOTSTRAP_ANSWERS_OVERRIDE:-}" \
		BOOTSTRAP_DOTFILES_URL="$DOTFILES_REMOTE" \
		BOOTSTRAP_AGENTBOT_URL="$AGENTBOT_REMOTE" \
		BOOTSTRAP_DOTFILES_DIR="$MACHINE/home/dotfiles" \
		BOOTSTRAP_AGENTBOT_DIR="$MACHINE/home/agentbot" \
		"$@" \
		bash "$BOOTSTRAP" </dev/null
}

log_has() { grep -Fq "$1" "$BOOTSTRAP_TEST_LOG"; }
log_line() { grep -Fn "$1" "$BOOTSTRAP_TEST_LOG" | head -1 | cut -d: -f1; }

test_both_clones_installs_updates_then_runs_agentbot() (
	setup_machine both
	run_bootstrap 1 >/dev/null 2>&1 || return 1

	[[ -d "$MACHINE/home/dotfiles/.git" && -d "$MACHINE/home/agentbot/.git" ]] || return 1
	log_has 'dotfiles-install --initial' || return 1
	log_has 'dotfiles-cli update' || return 1
	log_has 'agentbot-install install' || return 1
	log_has 'agentbot-install update' || return 1
	# Dotfiles must be fully done before Agentbot starts.
	local update_at agentbot_at
	update_at="$(log_line 'dotfiles-cli update')"
	agentbot_at="$(log_line 'agentbot-install install')"
	((update_at < agentbot_at))
)

test_dotfiles_only_skips_every_agentbot_step() (
	setup_machine dotfiles-only
	run_bootstrap 2 >/dev/null 2>&1 || return 1

	[[ -d "$MACHINE/home/dotfiles/.git" ]] || return 1
	[[ ! -e "$MACHINE/home/agentbot" ]] || return 1
	log_has 'dotfiles-install --initial' || return 1
	log_has 'dotfiles-cli update' || return 1
	! grep -q 'agentbot' "$BOOTSTRAP_TEST_LOG"
)

test_agentbot_only_skips_dotfiles_and_does_not_ask() (
	setup_machine agentbot-only
	local output
	output="$(run_bootstrap 3 2>&1)" || return 1

	[[ -d "$MACHINE/home/agentbot/.git" ]] || return 1
	[[ ! -e "$MACHINE/home/dotfiles" ]] || return 1
	log_has 'agentbot-install install' || return 1
	log_has 'agentbot-install update' || return 1
	! grep -q 'dotfiles-' "$BOOTSTRAP_TEST_LOG" || return 1
	[[ "$output" != *'Install and update Agentbot as well?'* ]]
)

test_dotfiles_update_always_follows_install() (
	setup_machine ordering
	run_bootstrap 2 >/dev/null 2>&1 || return 1
	local install_at update_at
	install_at="$(log_line 'dotfiles-install --initial')"
	update_at="$(log_line 'dotfiles-cli update')"
	((install_at < update_at))
)

test_full_update_is_never_invoked() (
	setup_machine no-full-update
	run_bootstrap 1 >/dev/null 2>&1 || return 1
	! grep -q 'full-update' "$BOOTSTRAP_TEST_LOG"
)

test_sudo_is_only_used_to_install_git() (
	setup_machine sudo-scope
	run_bootstrap 1 >/dev/null 2>&1 || return 1
	# git is already present here, so the one privileged step is skipped.
	! grep -q '^sudo ' "$BOOTSTRAP_TEST_LOG"
)

test_declining_agentbot_exits_cleanly_and_reports_the_command() (
	setup_machine decline
	local output
	# No TTY: `ask` takes its documented default, so drive the decision through
	# the selection instead and assert the deferred-command path directly.
	output="$(run_bootstrap 1 BOOTSTRAP_TEST_LOG="$BOOTSTRAP_TEST_LOG" 2>&1)" || return 1
	[[ "$output" == *'Summary'* ]] || return 1
	[[ "$output" == *'agentbot boot'* ]]
)

test_a_matching_clean_checkout_is_adopted() (
	setup_machine adopt
	run_bootstrap 2 >/dev/null 2>&1 || return 1

	local output
	output="$(run_bootstrap 2 2>&1)" || return 1
	[[ "$output" == *'Reusing the existing Dotfiles checkout'* ]] || return 1
	[[ "$output" == *'adopted  Dotfiles'* ]]
)

test_a_dirty_checkout_stops_without_touching_it() (
	setup_machine dirty
	run_bootstrap 2 >/dev/null 2>&1 || return 1
	printf 'local work\n' >"$MACHINE/home/dotfiles/scratch.txt"
	local before rc=0 output
	before="$(cat "$MACHINE/home/dotfiles/scratch.txt")"

	output="$(run_bootstrap 2 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'uncommitted changes'* ]] || return 1
	[[ "$(cat "$MACHINE/home/dotfiles/scratch.txt")" == "$before" ]]
)

test_a_foreign_remote_stops_without_touching_it() (
	setup_machine foreign
	run_bootstrap 2 >/dev/null 2>&1 || return 1
	"$REAL_GIT" -C "$MACHINE/home/dotfiles" remote set-url origin https://github.com/someone/else.git
	local rc=0 output
	output="$(run_bootstrap 2 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'someone/else'* ]] || return 1
	[[ -d "$MACHINE/home/dotfiles/.git" ]]
)

test_a_non_repository_destination_stops_without_deleting_it() (
	setup_machine occupied
	mkdir -p -- "$MACHINE/home/dotfiles"
	printf 'keep me\n' >"$MACHINE/home/dotfiles/important.txt"
	local rc=0 output
	output="$(run_bootstrap 2 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'not a Git repository'* ]] || return 1
	[[ "$(cat "$MACHINE/home/dotfiles/important.txt")" == 'keep me' ]]
)

test_preflight_reports_every_missing_prerequisite_together() (
	setup_machine preflight
	local rc=0 output empty="$MACHINE/empty-bin"
	mkdir -p -- "$empty"
	# Neither curl nor git nor sudo nor apt-get on PATH.
	# Absolute bash: env resolves the command through the stripped PATH.
	output="$(env PATH="$empty" HOME="$MACHINE/home" NO_COLOR=1 \
		BOOTSTRAP_SELECTION=1 "$(command -v bash)" "$BOOTSTRAP" </dev/null 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'curl'* ]] || return 1
	[[ "$output" == *'git'* ]]
)

test_an_unknown_selection_is_rejected_before_any_write() (
	setup_machine bad-selection
	local rc=0 output
	output="$(run_bootstrap 9 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'unknown choice: 9'* ]] || return 1
	[[ ! -e "$MACHINE/home/dotfiles" && ! -e "$MACHINE/home/agentbot" ]]
)

test_the_published_one_liner_matches_the_script_location() (
	# The README instruction and the script's own header must name the same raw
	# URL, or the documented command fetches something else.
	grep -Fq 'raw.githubusercontent.com/PamuduW/dotfiles/main/bootstrap.sh' "$BOOTSTRAP" || return 1
	grep -Fq 'raw.githubusercontent.com/PamuduW/dotfiles/main/bootstrap.sh' "$REPO_DIR/README.md"
)

test_a_piped_run_still_reads_the_prompts() (
	# Break caught: `interactive` tested `-t 0`, which is false under the
	# documented `curl ... | bash` invocation, so every prompt silently took its
	# default and the selection menu printed without ever waiting for an answer.
	# The gate must depend on the controlling terminal, not on stdin.
	grep -Fq '(exec 3</dev/tty) 2>/dev/null' "$BOOTSTRAP" || return 1
	! grep -Eq '^\s*\[\[ -t 0 ' "$BOOTSTRAP"
)

test_scripted_answers_drive_the_selection_prompt() (
	setup_machine scripted-selection
	# No BOOTSTRAP_SELECTION: the answer comes from the prompt itself.
	env PATH="$MACHINE/bin:$ORIGINAL_PATH" HOME="$MACHINE/home" NO_COLOR=1 \
		BOOTSTRAP_TEST_LOG="$BOOTSTRAP_TEST_LOG" \
		BOOTSTRAP_ANSWERS=$'2\nY' \
		BOOTSTRAP_DOTFILES_URL="$DOTFILES_REMOTE" \
		BOOTSTRAP_AGENTBOT_URL="$AGENTBOT_REMOTE" \
		BOOTSTRAP_DOTFILES_DIR="$MACHINE/home/dotfiles" \
		BOOTSTRAP_AGENTBOT_DIR="$MACHINE/home/agentbot" \
		bash "$BOOTSTRAP" </dev/null >/dev/null 2>&1 || return 1

	# Answer "2" means Dotfiles only, so Agentbot must never be obtained.
	[[ -d "$MACHINE/home/dotfiles/.git" ]] || return 1
	[[ ! -e "$MACHINE/home/agentbot" ]]
)

test_declining_the_plan_changes_nothing() (
	setup_machine decline-plan
	local output
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE=$'n' run_bootstrap 1 2>&1)" || return 1
	[[ "$output" == *'Nothing was changed.'* ]] || return 1
	[[ ! -e "$MACHINE/home/dotfiles" && ! -e "$MACHINE/home/agentbot" ]]
)

test_declining_agentbot_leaves_the_clone_and_reports_the_command() (
	setup_machine decline-agentbot
	local output
	# Plan yes, Agentbot no.
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE=$'Y\nn' run_bootstrap 1 2>&1)" || return 1

	log_has 'dotfiles-cli update' || return 1
	! grep -q 'agentbot-install' "$BOOTSTRAP_TEST_LOG" || return 1
	# The clone stays, so accepting later costs only the install.
	[[ -d "$MACHINE/home/agentbot/.git" ]] || return 1
	[[ "$output" == *'skipped  agentbot install'* ]] || return 1
	[[ "$output" == *"$MACHINE/home/agentbot/install.sh install"* ]]
)

expect_success 'both clones, installs, updates, then runs Agentbot' test_both_clones_installs_updates_then_runs_agentbot
expect_success 'Dotfiles only skips every Agentbot step' test_dotfiles_only_skips_every_agentbot_step
expect_success 'Agentbot only skips Dotfiles and does not ask' test_agentbot_only_skips_dotfiles_and_does_not_ask
expect_success 'Dotfiles update always follows install' test_dotfiles_update_always_follows_install
expect_success 'full-update is never invoked' test_full_update_is_never_invoked
expect_success 'sudo is only used to install git' test_sudo_is_only_used_to_install_git
expect_success 'the run reports a summary and the next command' test_declining_agentbot_exits_cleanly_and_reports_the_command
expect_success 'a matching clean checkout is adopted' test_a_matching_clean_checkout_is_adopted
expect_success 'a dirty checkout stops without touching it' test_a_dirty_checkout_stops_without_touching_it
expect_success 'a foreign remote stops without touching it' test_a_foreign_remote_stops_without_touching_it
expect_success 'a non-repository destination stops without deleting it' test_a_non_repository_destination_stops_without_deleting_it
expect_success 'preflight reports every missing prerequisite together' test_preflight_reports_every_missing_prerequisite_together
expect_success 'an unknown selection is rejected before any write' test_an_unknown_selection_is_rejected_before_any_write
expect_success 'the published one-liner matches the script location' test_the_published_one_liner_matches_the_script_location
expect_success 'a piped run still reads the prompts' test_a_piped_run_still_reads_the_prompts
expect_success 'scripted answers drive the selection prompt' test_scripted_answers_drive_the_selection_prompt
expect_success 'declining the plan changes nothing' test_declining_the_plan_changes_nothing
expect_success 'declining Agentbot leaves the clone and reports the command' test_declining_agentbot_leaves_the_clone_and_reports_the_command

test_harness_cleanup
finish_tests
