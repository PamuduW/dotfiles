# shellcheck shell=bash
# shellcheck disable=SC2034  # COMP_ON is the registry's selection state, read by is_on.

_dotfiles_approve_repo_update() {
	return 0
}

# Roadmap item 2: full-update is install + update, so install-time work (bashrc
# hooks, stow links, config writes) stops drifting on a machine that was set up
# once and only ever updated since.
#
# The selection is derived from probes, never from a stored answer: a full
# update must not silently add a component the operator did not choose.
# Components whose installer needs an answer only the operator can give. A full
# update has nobody to ask: selecting git_identity crashed the run outright on
# an unbound SETUP_GIT_NAME. That is initial-setup work.
FULL_UPDATE_NEVER_INSTALL=(git_identity)

_full_update_needs_operator_input() {
	local key="$1" excluded
	for excluded in "${FULL_UPDATE_NEVER_INSTALL[@]}"; do
		[[ "$key" == "$excluded" ]] && return 0
	done
	return 1
}

full_update_select_applied_components() {
	local -A probe_results=()
	local key result
	local -a unverified=()

	collect_component_probe_results probe_results || return 1
	for key in "${COMP_KEYS[@]}"; do
		if _full_update_needs_operator_input "$key"; then
			COMP_ON["$key"]=0
			continue
		fi
		result="${probe_results[$key]:-missing}"
		case "$result" in
		installed | configured) COMP_ON["$key"]=1 ;;
		# `check` means the probe could not reach a verdict, not that the
		# component is absent -- Portainer reads that way in any session that
		# predates the docker group. Reinstalling is the safe direction, since
		# installers are idempotent and skipping means silent drift, but the run
		# says which components it is guessing about.
		check)
			COMP_ON["$key"]=1
			unverified+=("$key")
			;;
		*) COMP_ON["$key"]=0 ;;
		esac
	done

	if ((${#unverified[@]} > 0)); then
		_msg "  Probe could not verify, reinstalling anyway: ${unverified[*]}"
	fi
}

full_update_install_applied_components() {
	local rc=0
	full_update_select_applied_components || return 1
	run_install || rc=$?
	# The installer returns a distinct status for "finished, but components need
	# attention". The update phases after this are independent, so report it and
	# carry on rather than abandoning the rest of the machine.
	if ((rc == ${DOTFILES_INSTALL_PARTIAL_RC:-4})); then
		return 0
	fi
	return "$rc"
}

# Wall clock per section of a full update.
#
# The longest command in the product, and the only one that said nothing about
# where its time went -- while both halves it drives now close on their own
# summary. Declared at module scope: an associative array declared only inside
# the run is an indexed one everywhere else, and bash evaluates an indexed
# subscript as arithmetic.
declare -gA FULL_UPDATE_SECTION_SECONDS=()

_full_update_section() {
	local label="$1" started rc=0
	shift
	started="$(timing_now_seconds)"
	"$@" || rc=$?
	FULL_UPDATE_SECTION_SECONDS["$label"]=$(($(timing_now_seconds) - started))
	return "$rc"
}

# The Dotfiles install, timed as its own section.
#
# It runs as _dotfiles_run_update's post_repo_fn, between the repository gate
# and the downstream upgrade, so wrapping it here is what separates "Dotfiles
# install" from "Dotfiles update" -- the run reported them as one section while
# printing two summaries of its own.
_full_update_dotfiles_install() {
	local rc=0 started
	started="$(timing_now_seconds)"
	DOTFILES_INSTALL_SECONDS=''
	full_update_install_applied_components || rc=$?
	# The install's own figure when it published one. Wrapping it with a clock
	# here starts before the sudo prompt, so the section disagreed with the
	# "Install took" line printed a few rows above it -- by however long the
	# operator spent typing their password.
	if [[ "${DOTFILES_INSTALL_SECONDS:-}" =~ ^[0-9]+$ ]]; then
		FULL_UPDATE_SECTION_SECONDS['Dotfiles install']="$DOTFILES_INSTALL_SECONDS"
	else
		FULL_UPDATE_SECTION_SECONDS['Dotfiles install']=$(($(timing_now_seconds) - started))
	fi
	return "$rc"
}

# Agentbot's two halves, as Agentbot reports them.
#
# `agentbot full` is one command from here, so its install and its update could
# only be timed together. It writes a line per stage to the file named below
# when asked. An Agentbot that does not know how to -- an older checkout, mid
# upgrade -- writes nothing, and the whole run is recorded as one section, which
# is what this did before.
_full_update_run_agentbot_timed() {
	local file rc=0 label seconds recorded=false
	file="$(mktemp)" || return 1
	local started
	started="$(timing_now_seconds)"
	# Quiet: the [info] lines are for an operator running Agentbot directly,
	# and this run has its own headings saying where it is.
	AGENTBOT_QUIET=1 AGENTBOT_TIMING_FILE="$file" full_update_run_agentbot || rc=$?
	while read -r label seconds; do
		[[ -n "$label" && "$seconds" =~ ^[0-9]+$ ]] || continue
		FULL_UPDATE_SECTION_SECONDS["Agentbot ${label}"]="$seconds"
		recorded=true
	done <"$file"
	rm -f -- "$file"
	[[ "$recorded" == true ]] ||
		FULL_UPDATE_SECTION_SECONDS[Agentbot]=$(($(timing_now_seconds) - started))
	return "$rc"
}

_full_update_print_timing() {
	# Every section, not the slowest handful: there are five, and naming five
	# of five "the slowest" says nothing about any of them.
	TIMING_SUMMARY_NOUN=sections TIMING_SUMMARY_LIMIT=0 \
		print_timing_summary 'Full update' FULL_UPDATE_SECTION_SECONDS \
		"$(($(timing_now_seconds) - FULL_UPDATE_STARTED))"
}

full_update_expected_agentbot_home() {
	local expected="${FULL_UPDATE_EXPECTED_AGENTBOT_HOME:-$(dirname -- "$DOTFILES_DIR")/agentbot}"
	realpath -m -- "$expected"
}

# Not installed at all, as opposed to installed and unreachable.
#
# A Dotfiles-only machine is a supported state: the bootstrap script offers
# "Dotfiles only" as one of its two choices and closes by saying how to add
# Agentbot later. Ending that machine's full update on "Action failed (exit
# 127)" reported the run as broken when it had done everything there was to
# do. A checkout that exists but whose launcher is not on PATH is a different
# thing -- that one is broken, and still fails.
full_update_agentbot_is_absent() {
	command -v agentbot >/dev/null 2>&1 && return 1
	[[ -d "$(full_update_expected_agentbot_home)" ]] && return 1
	return 0
}

full_update_without_agentbot() {
	local expected rc=0
	expected="$(full_update_expected_agentbot_home)"
	rt_print_header 'Dotfiles updated' 'Dotfiles › Full Update › Summary'
	printf '  Agentbot is not installed, so this run updated Dotfiles only.\n'
	printf '  Add it by cloning it to %s, or rerun the bootstrap script and\n' "$expected"
	printf '  choose Agentbot.\n'
	# The Dotfiles half still gets its health check; only Agentbot's is absent.
	printf '\n'
	full_update_dotfiles_doctor || rc=$?
	if ((rc != 0)); then
		printf '\n  %sDotfiles updated; the machine needs attention.%s\n' "${C_RED:-}" "${C_RESET:-}"
		return 1
	fi
	printf '\n  %sDotfiles update completed.%s\n' "${C_GREEN:-}" "${C_RESET:-}"
}

full_update_print_identity() {
	local dotfiles_launcher agentbot_launcher agentbot_resolved agentbot_home expected_home
	dotfiles_launcher="$(readlink -f "$DOTFILES_DIR/bin/bin/dotfiles")" || return 1
	agentbot_launcher="$(command -v agentbot 2>/dev/null)" || {
		_err 'Agentbot is not installed or is not available on PATH.'
		return 127
	}
	expected_home="$(full_update_expected_agentbot_home)"
	if [[ "$agentbot_launcher" == */* ]]; then
		agentbot_resolved="$(readlink -f "$agentbot_launcher")" || return 1
		agentbot_home="$(dirname -- "$(dirname -- "$agentbot_resolved")")"
	else
		agentbot_resolved="$agentbot_launcher (shell function)"
		agentbot_home="$expected_home"
	fi

	rt_print_header 'Resolved maintenance targets' 'Dotfiles › Full Update › Targets'
	printf '  Dotfiles launcher: %s\n  Dotfiles checkout: %s\n' "$dotfiles_launcher" "$DOTFILES_DIR"
	printf '  Agentbot launcher: %s\n  Agentbot checkout: %s\n' "$agentbot_resolved" "$agentbot_home"
	if [[ "$agentbot_home" != "$expected_home" ]]; then
		_err "Refusing unexpected Agentbot checkout: expected $expected_home, resolved $agentbot_home"
		return 1
	fi
}

full_update_restart_dotfiles() {
	exec "$DOTFILES_DIR/bin/bin/dotfiles" full-update "$@"
}

# Agentbot owns its install-then-update sequencing and restart budget via
# `agentbot full`. Older checkouts need one legacy install run so their own
# repository gate can introduce that command before Dotfiles delegates to it.
full_update_run_agentbot() {
	local rc=0 capability_rc=0
	command -v agentbot >/dev/null 2>&1 || {
		_err "Agentbot is not installed or is not available on PATH."
		return 127
	}
	rt_print_header 'Agentbot full' 'Dotfiles › Full Update › Agentbot'
	agentbot help full >/dev/null 2>&1 || capability_rc=$?
	case "$capability_rc" in
	0) ;;
	2)
		_msg 'Agentbot checkout is missing agentbot full; updating it once for compatibility.'
		AGENTBOT_INSTALL_CONFIRM=yes agentbot install || rc=$?
		case "$rc" in
		0 | 2) ;;
		*) return "$rc" ;;
		esac

		capability_rc=0
		agentbot help full >/dev/null 2>&1 || capability_rc=$?
		case "$capability_rc" in
		0) ;;
		2)
			_err 'Agentbot still does not support agentbot full after its compatibility update.'
			return 1
			;;
		*) return "$capability_rc" ;;
		esac
		;;
	*) return "$capability_rc" ;;
	esac

	rc=0
	AGENTBOT_INSTALL_CONFIRM=yes agentbot full || rc=$?
	case "$rc" in
	0) return 0 ;;
	2)
		_err 'Agentbot repository changed; rerun dotfiles full-update to finish.'
		return 1
		;;
	*) return "$rc" ;;
	esac
}

full_update_dotfiles_doctor() {
	declare -F cmd_doctor >/dev/null 2>&1 || return 0
	cmd_doctor
}

full_update_agentbot_doctor() {
	local output rc=0
	output="$(agentbot doctor 2>&1)" || rc=$?
	printf '%s\n' "$output"
	[[ $rc -eq 0 ]] || return 1
	grep -Eq '(^|[^0-9])[1-9][0-9]* warning\(s\)' <<<"$output" && return 10
	return 0
}

full_update_postflight() {
	local dotfiles_rc=0 agentbot_rc=0
	rt_print_header 'Postflight health' 'Dotfiles › Full Update › Postflight'
	full_update_dotfiles_doctor || dotfiles_rc=$?
	full_update_agentbot_doctor || agentbot_rc=$?

	if [[ $dotfiles_rc -ne 0 || ($agentbot_rc -ne 0 && $agentbot_rc -ne 10) ]]; then
		printf '\n  %sUpdates succeeded; system needs attention.%s\n' "${C_RED:-}" "${C_RESET:-}"
		return 1
	fi
	if [[ $agentbot_rc -eq 10 ]]; then
		printf '\n  %sFull system update completed with warnings.%s\n' "${C_YELLOW:-}" "${C_RESET:-}"
		return 0
	fi
	printf '\n  %sFull system update completed.%s\n' "${C_GREEN:-}" "${C_RESET:-}"
}

cmd_full_update() {
	local resumed=false arg dotfiles_rc=0
	# Reset, then set from the flag alone. Inheriting an ambient
	# DOTFILES_FORCE_REINSTALL would let an exported shell variable silently
	# force every run; the restart below carries the flag explicitly instead.
	export DOTFILES_FORCE_REINSTALL=0
	for arg in "$@"; do
		case "$arg" in
		--resume-after-dotfiles-repo) resumed=true ;;
		# Reinstall components that are already present, the unattended
		# equivalent of the execution plan's `x`. Git identity is unaffected,
		# and full-update never installs it anyway.
		--force) DOTFILES_FORCE_REINSTALL=1 ;;
		*)
			_err "Unknown full-update option: $arg"
			_msg 'Usage: dotfiles full-update [--force]'
			return 64
			;;
		esac
	done
	if [[ "$DOTFILES_FORCE_REINSTALL" == 1 ]]; then
		# The blank line the plan screen's own notice carries. It was supplied
		# by the menu until that duplicate copy was removed, and the notice
		# then sat directly under the answer the operator had just typed.
		printf '\n'
		_msg 'Forced reinstall: already-installed components will be reinstalled.'
	fi

	# The longest and most mutating command in the product: capture it, so an
	# unattended failure leaves something to read.
	declare -F start_action_log >/dev/null 2>&1 && start_action_log

	# This run restarts itself when a checkout moves, in both repositories, so
	# neither should tell the operator to run setup again. Exported, because
	# the Agentbot half is a child process making the same decision.
	export REPO_UPDATE_CALLER_RESTARTS=1
	FULL_UPDATE_SECTION_SECONDS=()
	declare -g FULL_UPDATE_STARTED
	FULL_UPDATE_STARTED="$(timing_now_seconds)"

	# No header of its own. It announced a section with no body -- the install
	# phase prints "=== Installing ===" as its very next line -- and repeated
	# the menu's own "Dotfiles › Full Update" breadcrumb verbatim two lines
	# after it. The three section headers this run does print say where it is.
	# repo update -> component install -> downstream updates, the order
	# bootstrap uses, so the first run and every run after it converge.
	# Timed as two sections, not one. The install records itself from inside
	# (it is the post_repo_fn below); what is left of the elapsed total is the
	# repository gate and the downstream upgrade, which is the update half.
	local dotfiles_started
	dotfiles_started="$(timing_now_seconds)"
	_dotfiles_run_update _dotfiles_approve_repo_update true false \
		_full_update_dotfiles_install || dotfiles_rc=$?
	FULL_UPDATE_SECTION_SECONDS['Dotfiles update']=$(( \
		$(timing_now_seconds) - dotfiles_started - \
		${FULL_UPDATE_SECTION_SECONDS['Dotfiles install']:-0}))
	case "$dotfiles_rc" in
	0) ;;
	2)
		if [[ "$resumed" == true ]]; then
			_err 'Dotfiles repository changed more than once; full update stopped.'
			return 1
		fi
		_msg 'Restarting Dotfiles from the updated checkout.'
		local -a restart_args=(--resume-after-dotfiles-repo)
		if [[ "$DOTFILES_FORCE_REINSTALL" == 1 ]]; then
			restart_args+=(--force)
		fi
		full_update_restart_dotfiles "${restart_args[@]}"
		return $?
		;;
	*) return "$dotfiles_rc" ;;
	esac

	if full_update_agentbot_is_absent; then
		local absent_rc=0
		_full_update_section 'Dotfiles health check' full_update_without_agentbot || absent_rc=$?
		_full_update_print_timing
		return "$absent_rc"
	fi

	full_update_print_identity || return $?
	_full_update_run_agentbot_timed || return $?
	local postflight_rc=0
	_full_update_section Postflight full_update_postflight || postflight_rc=$?
	_full_update_print_timing
	return "$postflight_rc"
}
