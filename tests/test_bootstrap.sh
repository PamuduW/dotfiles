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
# The stowed wrapper shadows git on a provisioned machine and guards `commit`,
# so fixtures must talk to the real binary the way test_git_wrapper.sh does.
REAL_GIT="${DOTFILES_REAL_GIT:-/usr/bin/git}"
export GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL="$TEST_HARNESS_ROOT/empty.gitconfig"
: >"$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_GLOBAL

# The two installer generations this script has to cope with: one that predates
# --install and one that offers it.
_write_installer() {
	local path="$1" generation="$2"
	if [[ "$generation" == legacy ]]; then
		cat >"$path" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
	printf 'Options:\n  --initial\n  --update\n'
	exit 0
fi
printf 'legacy-install %s\n' "$*" >>"$BOOTSTRAP_TEST_LOG"
EOF
	else
		cat >"$path" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
	printf 'Options:\n  --initial\n  --install\n  --update\n'
	exit 0
fi
printf 'dotfiles-install %s\n' "$*" >>"$BOOTSTRAP_TEST_LOG"
EOF
	fi
	chmod +x -- "$path"
}

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
# A real checkout advertises its modes; bootstrap asks before using one.
if [[ "\${1:-}" == --help ]]; then
	printf 'Options:\n  --initial\n  --install\n  --update\n'
	exit 0
fi
printf '$repo_name-install %s\n' "\$*" >>"\$BOOTSTRAP_TEST_LOG"
# Seam for the restart and failure tests: exit with the code in the file, then
# reset it so the next invocation succeeds. Each repository may have its own
# file, so a test can ask both of them for a restart independently.
rc_file="\${BOOTSTRAP_TEST_RC_FILE_$repo_name:-\${BOOTSTRAP_TEST_RC_FILE:-}}"
if [[ -n "\$rc_file" && -f "\$rc_file" ]]; then
	rc="\$(cat "\$rc_file")"
	printf '0\n' >"\$rc_file"
	exit "\$rc"
fi
EOF
	# The real script, so the restart path has something to exec.
	cp -- "$REPO_DIR/bootstrap.sh" "$work/bootstrap.sh"
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
	log_has 'dotfiles-install --install' || return 1
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
	log_has 'dotfiles-install --install' || return 1
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
	install_at="$(log_line 'dotfiles-install --install')"
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

test_the_plan_is_shown_not_asked() (
	# The selection is the decision. A destination that cannot be used safely
	# stops the run with a report, so a second confirmation would only stand
	# between the operator and the setup they asked for.
	setup_machine plan-not-asked
	local output
	output="$(run_bootstrap 1 2>&1)" || return 1
	[[ "$output" == *'Proceeding.'* ]] || return 1
	[[ "$output" != *'Continue?'* ]] || return 1
	log_has 'dotfiles-install --install'
)

test_agentbot_runs_without_a_second_question() (
	# Choosing "Dotfiles and Agentbot" is the answer; asking again after the
	# Dotfiles phase was a prompt for a decision already made.
	setup_machine agentbot-no-question
	local output
	output="$(run_bootstrap 1 2>&1)" || return 1
	[[ "$output" != *'Install and update Agentbot as well?'* ]] || return 1
	log_has 'agentbot-install install' || return 1
	log_has 'agentbot-install update'
)

test_only_the_selection_is_asked() (
	# One command, one question. Anything else is a prompt for something the
	# operator has already answered.
	setup_machine one-question
	local output
	output="$(run_bootstrap 1 2>&1)" || return 1
	[[ "$(printf '%s\n' "$output" | grep -c '\[Y/n\]')" -eq 0 ]]
)

test_a_repository_update_restarts_instead_of_failing() (
	# Break caught: both installers return 2 to mean "the checkout moved
	# forward, rerun from the new state". Bootstrap treated that as a failure,
	# died before the update phase, and printed no summary at all.
	setup_machine restart
	local rc_file="$MACHINE/install-rc"
	printf '2\n' >"$rc_file"

	local output
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE=$'Y\nY' \
		run_bootstrap 1 BOOTSTRAP_TEST_RC_FILE="$rc_file" 2>&1)" || return 1

	[[ "$output" == *'updated its checkout. Restarting'* ]] || return 1
	[[ "$(grep -c 'dotfiles-install --install' "$BOOTSTRAP_TEST_LOG")" -eq 2 ]] || return 1
	log_has 'dotfiles-cli update' || return 1
	log_has 'agentbot-install install' || return 1
	[[ "$output" != *'FAILED'* ]]
)

test_a_failed_step_still_prints_a_summary() (
	setup_machine failed-step
	local rc_file="$MACHINE/install-rc"
	printf '9\n' >"$rc_file"

	local rc=0 output
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE=$'Y' \
		run_bootstrap 2 BOOTSTRAP_TEST_RC_FILE="$rc_file" 2>&1)" || rc=$?

	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'Summary'* ]] || return 1
	[[ "$output" == *'FAILED   dotfiles install'* ]] || return 1
	# The total is reported so the run answers "how long did that take".
	[[ "$output" == *'Total '* ]] || return 1
	[[ "$output" == *'cloned   Dotfiles'* ]]
)

test_component_failures_do_not_abandon_the_remaining_phases() (
	# Break caught: any non-zero installer status ended the run, so one failed
	# component meant no Dotfiles update and no Agentbot at all. Status 4 means
	# "finished, some components need attention" and must not stop the rest.
	setup_machine partial
	local rc_file="$MACHINE/install-rc"
	printf '4\n' >"$rc_file"

	local output
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE=$'Y\nY' \
		run_bootstrap 1 BOOTSTRAP_TEST_RC_FILE="$rc_file" 2>&1)" || return 1

	log_has 'dotfiles-cli update' || return 1
	log_has 'agentbot-install install' || return 1
	[[ "$output" == *'dotfiles install (some components need attention)'* ]] || return 1
	[[ "$output" != *'FAILED'* ]]
)

test_the_checkout_update_is_pre_authorized() (
	# The plan was already confirmed, so the installer must not ask again.
	grep -Fq 'DOTFILES_REPO_UPDATE_ASSUME_YES=1' "$BOOTSTRAP"
)

test_agentbot_phase_sees_tools_dotfiles_just_installed() (
	# Break caught: Dotfiles installs Node through nvm and drops tools in
	# ~/.local/bin, but the shell running bootstrap predates both. The Agentbot
	# phase refused to run for a missing `node` moments after Dotfiles reported
	# installing it.
	local root="$TEST_HARNESS_ROOT/late-path"
	rm -rf -- "$root"
	mkdir -p -- "$root/.nvm/bin" "$root/.local/bin"
	printf '#!/usr/bin/env bash\nprintf "v24\\n"\n' >"$root/.nvm/bin/node"
	chmod +x -- "$root/.nvm/bin/node"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.local/bin/late-tool"
	chmod +x -- "$root/.local/bin/late-tool"
	# nvm publishes its own PATH entry only when the script is sourced.
	printf 'PATH="%s:$PATH"\nexport PATH\n' "$root/.nvm/bin" >"$root/.nvm/nvm.sh"

	# PATH is emptied for the assertions so the harness's own node cannot mask
	# the point: only the loader may make these reachable. Everything used here
	# is a shell builtin.
	HOME="$root" NVM_DIR="$root/.nvm" BOOTSTRAP_SOURCE_ONLY=1 bash -c '
		source "$1"
		PATH=""
		command -v node >/dev/null 2>&1 && exit 10
		command -v late-tool >/dev/null 2>&1 && exit 11
		load_dotfiles_environment
		command -v node >/dev/null 2>&1 || exit 12
		command -v late-tool >/dev/null 2>&1 || exit 13
	' _ "$BOOTSTRAP"
)

test_the_summary_prints_exactly_once_before_the_shell_offer() (
	# start_new_shell execs, and exec does not run EXIT traps, so the summary is
	# printed explicitly at the end of main. It must not also come from the
	# trap, or a successful run reports itself twice.
	setup_machine summary-once
	local output count
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE=$'Y\nY' run_bootstrap 1 2>&1)" || return 1
	count="$(printf '%s\n' "$output" | grep -c '==> Summary')"
	[[ "$count" -eq 1 ]]
)

test_a_non_interactive_run_does_not_exec_a_shell() (
	# With no terminal the reload is skipped entirely; execing there would
	# replace the run with a shell reading an exhausted pipe.
	setup_machine no-shell-offer
	local output
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE=$'Y\nY' run_bootstrap 1 2>&1)" || return 1
	[[ "$output" != *'Reloading the shell'* ]] || return 1
	[[ "$output" == *'exec bash -l'* ]]
)

test_an_older_checkout_falls_back_to_the_mode_it_has() (
	# Break caught: this script is always fetched fresh but drives a checkout of
	# any age. It invoked --install on a checkout that predated the flag, whose
	# argument parser rejected it before reaching the repository gate that would
	# have updated it -- so the run could never recover on its own.
	setup_machine legacy-mode
	# A checkout that only knows --initial.
	local legacy="$MACHINE/home/dotfiles"
	run_bootstrap 2 >/dev/null 2>&1 || return 1
	cat >"$legacy/install.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
	printf 'Options:\n  --initial\n  --update\n'
	exit 0
fi
case "${1:-}" in
--initial) printf 'dotfiles-install %s\n' "$*" >>"$BOOTSTRAP_TEST_LOG" ;;
*)
	printf 'Unknown option: %s\n' "$1" >&2
	exit 1
	;;
esac
EOF
	chmod +x -- "$legacy/install.sh"
	# Commit it: the adoption policy refuses a dirty checkout, and rightly so.
	"$REAL_GIT" -C "$legacy" add -A >/dev/null 2>&1
	"$REAL_GIT" -C "$legacy" -c user.name=T -c user.email=t@e.invalid \
		commit -qm 'legacy installer' >/dev/null 2>&1
	: >"$BOOTSTRAP_TEST_LOG"

	local output
	output="$(run_bootstrap 2 2>&1)" || return 1
	[[ "$output" == *'predates direct component selection'* ]] || return 1
	log_has 'dotfiles-install --initial' || return 1
	! grep -q -- '--install' "$BOOTSTRAP_TEST_LOG"
)

test_a_checkout_behind_the_remote_advances_itself() (
	# Break caught: the legacy fallback handed --initial to an old checkout on
	# the assumption its repository gate would pull. On a real terminal that
	# gate sits behind a menu, so the run parked there instead of recovering.
	setup_machine behind-remote
	local work="$MACHINE/legacy-work" remote="$MACHINE/remotes/legacy.git"
	local checkout="$MACHINE/home/dotfiles"
	rm -rf -- "$checkout"

	# First commit knows only --initial; the second adds --install.
	mkdir -p -- "$work/bin/bin"
	printf '#!/usr/bin/env bash\nprintf "dotfiles-cli %%s\\n" "$*" >>"$BOOTSTRAP_TEST_LOG"\n' \
		>"$work/bin/bin/dotfiles"
	_write_installer "$work/install.sh" legacy
	# The checkout must carry this script: a restart execs the copy in it.
	cp -- "$REPO_DIR/bootstrap.sh" "$work/bootstrap.sh"
	chmod +x -- "$work/install.sh" "$work/bin/bin/dotfiles" "$work/bootstrap.sh"
	{
		"$REAL_GIT" init -q -b main "$work" &&
			"$REAL_GIT" -C "$work" config user.name T &&
			"$REAL_GIT" -C "$work" config user.email t@e.invalid &&
			"$REAL_GIT" -C "$work" add -A &&
			"$REAL_GIT" -C "$work" commit -qm 'legacy installer' &&
			"$REAL_GIT" clone -q --bare "$work" "$remote" &&
			"$REAL_GIT" clone -q "$remote" "$checkout"
	} >/dev/null 2>&1 || return 1

	_write_installer "$work/install.sh" modern
	{
		"$REAL_GIT" -C "$work" commit -qam 'modern installer' &&
			"$REAL_GIT" -C "$work" push -q "$remote" main
	} >/dev/null 2>&1 || return 1

	: >"$BOOTSTRAP_TEST_LOG"
	DOTFILES_REMOTE="$remote"
	local output
	output="$(run_bootstrap 2 2>&1)" || return 1

	[[ "$output" == *'predates direct component selection'* ]] || return 1
	[[ "$output" == *'Restarting'* ]] || return 1
	# It recovered on its own and then used the mode the newer checkout has.
	log_has 'dotfiles-install --install' || return 1
	! grep -q 'legacy-install' "$BOOTSTRAP_TEST_LOG"
)

test_each_repository_may_restart_once() (
	# Break caught: one flag covered both repositories, so a Dotfiles restart
	# made a legitimate Agentbot restart look like a loop and stopped the setup
	# one step from finishing.
	setup_machine two-restarts
	local dotfiles_rc="$MACHINE/dotfiles-rc" agentbot_rc="$MACHINE/agentbot-rc"
	printf '2\n' >"$dotfiles_rc"
	printf '2\n' >"$agentbot_rc"

	# Each fake installer reads its own status file, so both ask for a restart.
	local output
	output="$(BOOTSTRAP_ANSWERS_OVERRIDE='' run_bootstrap 1 \
		BOOTSTRAP_TEST_RC_FILE_dotfiles="$dotfiles_rc" \
		BOOTSTRAP_TEST_RC_FILE_agentbot="$agentbot_rc" 2>&1)" || return 1

	[[ "$output" != *'stopping to avoid a loop'* ]] || return 1
	[[ "$(printf '%s\n' "$output" | grep -c 'Restarting from the updated script')" -eq 2 ]] || return 1
	log_has 'dotfiles-cli update' || return 1
	log_has 'agentbot-install install'
)

test_one_repository_restarting_twice_is_still_a_loop() (
	setup_machine loop-guard
	local rc_file="$MACHINE/always-2"
	printf '2\n' >"$rc_file"
	# Never resets: the checkout claims to move forward every single time.
	local checkout="$MACHINE/home/dotfiles"
	run_bootstrap 2 >/dev/null 2>&1 || true
	cat >"$checkout/install.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
	printf 'Options:\n  --initial\n  --install\n  --update\n'
	exit 0
fi
printf 'dotfiles-install %s\n' "$*" >>"$BOOTSTRAP_TEST_LOG"
exit 2
EOF
	chmod +x -- "$checkout/install.sh"
	"$REAL_GIT" -C "$checkout" add -A >/dev/null 2>&1
	"$REAL_GIT" -C "$checkout" -c user.name=T -c user.email=t@e.invalid \
		commit -qm 'always moving' >/dev/null 2>&1

	local rc=0 output
	output="$(run_bootstrap 2 2>&1)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" == *'stopping to avoid a loop'* ]]
)

test_the_run_reports_a_duration_per_phase_and_a_total() (
	setup_machine durations
	local output
	output="$(run_bootstrap 1 2>&1)" || return 1
	# Each phase carries its own wall-clock, and the run carries the sum.
	printf '%s\n' "$output" | grep -Eq '^ +[0-9]+m [0-9]{2}s +dotfiles install$' || return 1
	printf '%s\n' "$output" | grep -Eq '^ +[0-9]+m [0-9]{2}s +agentbot update$' || return 1
	printf '%s\n' "$output" | grep -Eq '^ +Total [0-9]+m [0-9]{2}s\.$'
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
expect_success 'the plan is shown, not asked' test_the_plan_is_shown_not_asked
expect_success 'Agentbot runs without a second question' test_agentbot_runs_without_a_second_question
expect_success 'only the selection is asked' test_only_the_selection_is_asked
expect_success 'the run reports a duration per phase and a total' test_the_run_reports_a_duration_per_phase_and_a_total
expect_success 'a repository update restarts instead of failing' test_a_repository_update_restarts_instead_of_failing
expect_success 'a failed step still prints a summary' test_a_failed_step_still_prints_a_summary
expect_success 'component failures do not abandon the remaining phases' test_component_failures_do_not_abandon_the_remaining_phases
expect_success 'the checkout update is pre-authorized' test_the_checkout_update_is_pre_authorized
expect_success 'an older checkout falls back to the mode it has' test_an_older_checkout_falls_back_to_the_mode_it_has
expect_success 'a checkout behind the remote advances itself' test_a_checkout_behind_the_remote_advances_itself
expect_success 'each repository may restart once' test_each_repository_may_restart_once
expect_success 'one repository restarting twice is still a loop' test_one_repository_restarting_twice_is_still_a_loop
expect_success 'the Agentbot phase sees tools Dotfiles just installed' test_agentbot_phase_sees_tools_dotfiles_just_installed
expect_success 'the summary prints exactly once before the shell offer' test_the_summary_prints_exactly_once_before_the_shell_offer
expect_success 'a non-interactive run does not exec a shell' test_a_non_interactive_run_does_not_exec_a_shell

test_harness_cleanup
finish_tests
