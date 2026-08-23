# shellcheck shell=bash

_dotfiles_approve_repo_update() {
	return 0
}

full_update_restart_dotfiles() {
	exec "$DOTFILES_DIR/bin/bin/dotfiles" full-update "$1"
}

# Agentbot owns its own install-then-update sequencing and restart budget via
# `agentbot full`, so this only has to run it and read the exit contract:
# 0 continue, 1 stop, 2 the Agentbot checkout changed.
full_update_run_agentbot() {
	local rc=0
	command -v agentbot >/dev/null 2>&1 || {
		_err "Agentbot is not installed or is not available on PATH."
		return 127
	}
	printf '\n%s%s=== Agentbot full ===%s\n' "${C_BOLD:-}" "${C_ORANGE:-}" "${C_RESET:-}"
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

	full_update_run_agentbot || return $?
	printf '\n%sFull system update completed.%s\n' "${C_GREEN:-}" "${C_RESET:-}"
}
