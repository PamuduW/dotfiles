# shellcheck shell=bash

_dotfiles_approve_repo_update() {
	return 0
}

full_update_print_identity() {
	local dotfiles_launcher agentbot_launcher agentbot_resolved agentbot_home expected_home
	dotfiles_launcher="$(readlink -f "$DOTFILES_DIR/bin/bin/dotfiles")" || return 1
	agentbot_launcher="$(command -v agentbot 2>/dev/null)" || {
		_err 'Agentbot is not installed or is not available on PATH.'
		return 127
	}
	expected_home="${FULL_UPDATE_EXPECTED_AGENTBOT_HOME:-$(dirname -- "$DOTFILES_DIR")/agentbot}"
	expected_home="$(realpath -m -- "$expected_home")"
	if [[ "$agentbot_launcher" == */* ]]; then
		agentbot_resolved="$(readlink -f "$agentbot_launcher")" || return 1
		agentbot_home="$(dirname -- "$(dirname -- "$agentbot_resolved")")"
	else
		agentbot_resolved="$agentbot_launcher (shell function)"
		agentbot_home="$expected_home"
	fi

	printf '%s%s=== Resolved maintenance targets ===%s\n' "${C_BOLD:-}" "${C_ORANGE:-}" "${C_RESET:-}"
	printf 'Dotfiles launcher: %s\nDotfiles checkout: %s\n' "$dotfiles_launcher" "$DOTFILES_DIR"
	printf 'Agentbot launcher: %s\nAgentbot checkout: %s\n' "$agentbot_resolved" "$agentbot_home"
	if [[ "$agentbot_home" != "$expected_home" ]]; then
		_err "Refusing unexpected Agentbot checkout: expected $expected_home, resolved $agentbot_home"
		return 1
	fi
}

full_update_restart_dotfiles() {
	exec "$DOTFILES_DIR/bin/bin/dotfiles" full-update "$1"
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
	printf '\n%s%s=== Agentbot full ===%s\n' "${C_BOLD:-}" "${C_ORANGE:-}" "${C_RESET:-}"
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
	printf '\n%s%s=== Postflight health ===%s\n' "${C_BOLD:-}" "${C_ORANGE:-}" "${C_RESET:-}"
	full_update_dotfiles_doctor || dotfiles_rc=$?
	full_update_agentbot_doctor || agentbot_rc=$?

	if [[ $dotfiles_rc -ne 0 || ($agentbot_rc -ne 0 && $agentbot_rc -ne 10) ]]; then
		printf '\n%sUpdates succeeded; system needs attention.%s\n' "${C_RED:-}" "${C_RESET:-}"
		return 1
	fi
	if [[ $agentbot_rc -eq 10 ]]; then
		printf '\n%sFull system update completed with warnings.%s\n' "${C_YELLOW:-}" "${C_RESET:-}"
		return 0
	fi
	printf '\n%sFull system update completed.%s\n' "${C_GREEN:-}" "${C_RESET:-}"
}

cmd_full_update() {
	local resumed=false arg dotfiles_rc=0
	for arg in "$@"; do
		case "$arg" in
		--resume-after-dotfiles-repo) resumed=true ;;
		*)
			_err "Unknown full-update option: $arg"
			return 64
			;;
		esac
	done

	# The longest and most mutating command in the product: capture it, so an
	# unattended failure leaves something to read.
	declare -F start_action_log >/dev/null 2>&1 && start_action_log

	printf '%s%s=== Dotfiles full update ===%s\n' "${C_BOLD:-}" "${C_ORANGE:-}" "${C_RESET:-}"
	_dotfiles_run_update _dotfiles_approve_repo_update true || dotfiles_rc=$?
	case "$dotfiles_rc" in
	0) ;;
	2)
		if [[ "$resumed" == true ]]; then
			_err 'Dotfiles repository changed more than once; full update stopped.'
			return 1
		fi
		_msg 'Restarting Dotfiles from the updated checkout.'
		full_update_restart_dotfiles --resume-after-dotfiles-repo
		return $?
		;;
	*) return "$dotfiles_rc" ;;
	esac

	full_update_print_identity || return $?
	full_update_run_agentbot || return $?
	full_update_postflight
}
