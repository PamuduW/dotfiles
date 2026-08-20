# shellcheck shell=bash

_dotfiles_approve_repo_update() {
	return 0
}

full_update_restart_dotfiles() {
	exec "$DOTFILES_DIR/bin/bin/dotfiles" full-update "$1"
}

_full_update_run_agentbot_stage() {
	local stage="$1" rc=0
	case "$stage" in
	install) AGENTBOT_INSTALL_CONFIRM=yes agentbot install || rc=$? ;;
	update) agentbot update --yes || rc=$? ;;
	*) return 64 ;;
	esac
	return "$rc"
}

full_update_run_agentbot() {
	local stage rc agentbot_restarts=0
	command -v agentbot >/dev/null 2>&1 || {
		_err "Agentbot is not installed or is not available on PATH."
		return 127
	}
	for stage in install update; do
		while true; do
			printf '\n%s%s=== Agentbot %s ===%s\n' "${C_BOLD:-}" "${C_ORANGE:-}" "$stage" "${C_RESET:-}"
			rc=0
			_full_update_run_agentbot_stage "$stage" || rc=$?
			case "$rc" in
			0) break ;;
			2)
				if ((agentbot_restarts >= 1)); then
					_err 'Agentbot repository changed more than once; full update stopped.'
					return 1
				fi
				agentbot_restarts=$((agentbot_restarts + 1))
				_msg 'Restarting Agentbot from the updated checkout.'
				;;
			*) return "$rc" ;;
			esac
		done
	done
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

	printf '%s%s=== Dotfiles full update ===%s\n' "${C_BOLD:-}" "${C_ORANGE:-}" "${C_RESET:-}"
	_dotfiles_run_update true _dotfiles_approve_repo_update true || dotfiles_rc=$?
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
