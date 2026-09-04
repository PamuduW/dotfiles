# shellcheck shell=bash
# Action logging for mutating workflows. Sourced by scripts/install.sh (menu
# paths) and bin/bin/dotfiles (direct commands) so both log the same way.

if [[ "${_DOTFILES_ACTION_LOG_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_ACTION_LOG_LOADED=1

# Keep the newest N logs so an unattended machine cannot grow the directory
# without bound.
DOTFILES_LOG_RETAIN="${DOTFILES_LOG_RETAIN:-20}"

LOG_DIR="${DOTFILES_DIR}/log"
LOG_FILE=''
RAW_LOG_FILE=''
DOTFILES_LOG_ACTIVE=false
_ACTION_LOG_LOCK_PID=''
_ACTION_LOG_SAVED_OUT=''
_ACTION_LOG_SAVED_ERR=''
_ACTION_LOG_TEE_PID=''

# Turn a raw tee'd terminal capture into a readable log: carriage returns become
# newlines, CSI and OSC escape sequences are dropped, trailing blanks trimmed.
# GNU sed only (Debian/Ubuntu target).
_clean_log_stream() {
	sed -u \
		-e 's/\r/\n/g' \
		-e 's/\x1b\[[0-9;?]*[ -/]*[@-~]//g' \
		-e 's/\x1b\][^\x07]*\(\x07\|\x1b\\\)//g' \
		-e 's/[[:space:]]*$//'
}

# A child cannot set FD_CLOEXEC on the logger's fds, and those fds are
# inherited by tee/sleep/apt. Hold the exclusive lock in a dedicated process
# that dies with the logger (setpriv --pdeathsig) and never execs a child.
_action_log_start_lock() {
	local status=''
	command -v setpriv >/dev/null 2>&1 || return 1
	command -v perl >/dev/null 2>&1 || return 1
	# The perl program is passed as a literal; $ARGV is perl, not bash.
	# shellcheck disable=SC2016
	exec {_ACTION_LOG_LOCK_RD}< <(
		exec setpriv --pdeathsig KILL perl -e '
			use Fcntl qw(LOCK_EX O_RDWR);
			sysopen(my $fh, $ARGV[0], O_RDWR) or exit 1;
			flock($fh, LOCK_EX) or exit 1;
			select STDOUT;
			$| = 1;
			print "locked\n";
			sleep;
		' -- "$RAW_LOG_FILE"
	)
	_ACTION_LOG_LOCK_PID=$!
	IFS= read -r -t 5 status <&"${_ACTION_LOG_LOCK_RD}" || status=''
	exec {_ACTION_LOG_LOCK_RD}>&-
	if [[ "$status" != locked ]]; then
		_action_log_release_lock
		return 1
	fi
}

_action_log_release_lock() {
	if [[ -n "${_ACTION_LOG_LOCK_PID:-}" ]]; then
		kill "$_ACTION_LOG_LOCK_PID" 2>/dev/null || true
		wait "$_ACTION_LOG_LOCK_PID" 2>/dev/null || true
		_ACTION_LOG_LOCK_PID=''
	fi
}

_action_log_raw_is_idle() {
	local file="$1" fd
	exec {fd}<>"$file" || return 0
	if flock -n "$fd"; then
		exec {fd}>&-
		return 0
	fi
	exec {fd}>&-
	return 1
}

_allocate_action_log_paths() {
	local stem
	for _ in 1 2 3 4 5 6 7 8; do
		stem="$(date '+%Y-%m-%d_%H-%M-%S_%N')_$BASHPID"
		LOG_FILE="$LOG_DIR/${stem}.log"
		RAW_LOG_FILE="${LOG_FILE}.raw"
		if (
			set -o noclobber
			: >"$RAW_LOG_FILE"
		) 2>/dev/null; then
			return 0
		fi
	done
	printf 'Error: could not allocate an exclusive action log.\n' >&2
	return 1
}

finalize_log_file() {
	local tmp
	[[ "$DOTFILES_LOG_ACTIVE" == true ]] || return 0
	DOTFILES_LOG_ACTIVE=false
	if [[ -n "${_ACTION_LOG_SAVED_OUT:-}" ]]; then
		exec >&"${_ACTION_LOG_SAVED_OUT}"
		exec 2>&"${_ACTION_LOG_SAVED_ERR}"
		exec {_ACTION_LOG_SAVED_OUT}>&-
		exec {_ACTION_LOG_SAVED_ERR}>&-
		_ACTION_LOG_SAVED_OUT=''
		_ACTION_LOG_SAVED_ERR=''
	fi
	if [[ -n "${_ACTION_LOG_TEE_PID:-}" ]]; then
		wait "$_ACTION_LOG_TEE_PID" 2>/dev/null || true
		_ACTION_LOG_TEE_PID=''
	fi
	if [[ -n "$RAW_LOG_FILE" && -f "$RAW_LOG_FILE" ]]; then
		tmp="${LOG_FILE}.tmp.$BASHPID"
		if _clean_log_stream <"$RAW_LOG_FILE" >"$tmp" && mv -f -- "$tmp" "$LOG_FILE"; then
			rm -f -- "$RAW_LOG_FILE"
		else
			rm -f -- "$tmp"
			_action_log_release_lock
			return 1
		fi
	fi
	_action_log_release_lock
}

# Drop idle .raw captures from runs that never finalized, then trim the
# finished logs down to the retention limit. Live captures stay locked.
_prune_action_logs() {
	local -a existing=()
	local file keep="$DOTFILES_LOG_RETAIN"
	[[ -d "$LOG_DIR" ]] || return 0
	[[ "$keep" =~ ^[0-9]+$ ]] || return 0

	for file in "$LOG_DIR"/*.log.raw; do
		[[ -f "$file" ]] || continue
		[[ "$file" == "$RAW_LOG_FILE" ]] && continue
		_action_log_raw_is_idle "$file" || continue
		rm -f -- "$file"
	done

	mapfile -t existing < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -print | sort -r)
	((${#existing[@]} > keep)) || return 0
	for file in "${existing[@]:$keep}"; do
		rm -f -- "$file"
	done
}

start_action_log() {
	[[ "$DOTFILES_LOG_ACTIVE" == true ]] && return 0
	mkdir -p "$LOG_DIR"
	_allocate_action_log_paths || return 1
	if ! _action_log_start_lock; then
		rm -f -- "$RAW_LOG_FILE"
		RAW_LOG_FILE=''
		LOG_FILE=''
		printf 'Error: could not lock action log.\n' >&2
		return 1
	fi
	DOTFILES_LOG_ACTIVE=true
	_prune_action_logs
	trap finalize_log_file EXIT
	exec {_ACTION_LOG_SAVED_OUT}>&1
	exec {_ACTION_LOG_SAVED_ERR}>&2
	exec > >(tee -a "$RAW_LOG_FILE") 2>&1
	_ACTION_LOG_TEE_PID=$!
}
