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

# Turn a raw tee'd terminal capture into a readable log: carriage returns become
# newlines, CSI and OSC escape sequences are dropped, trailing blanks trimmed.
# GNU sed only (Debian/Ubuntu target) so the installer needs no perl.
_clean_log_stream() {
	sed -u \
		-e 's/\r/\n/g' \
		-e 's/\x1b\[[0-9;?]*[ -/]*[@-~]//g' \
		-e 's/\x1b\][^\x07]*\(\x07\|\x1b\\\)//g' \
		-e 's/[[:space:]]*$//'
}

finalize_log_file() {
	[[ -n "$RAW_LOG_FILE" && -f "$RAW_LOG_FILE" ]] || return 0
	_clean_log_stream <"$RAW_LOG_FILE" >"$LOG_FILE"
	rm -f "$RAW_LOG_FILE"
}

# Drop orphaned .raw captures from runs that never finalized, then trim the
# finished logs down to the retention limit.
_prune_action_logs() {
	local -a existing=()
	local file keep="$DOTFILES_LOG_RETAIN"
	[[ -d "$LOG_DIR" ]] || return 0
	[[ "$keep" =~ ^[0-9]+$ ]] || return 0

	for file in "$LOG_DIR"/*.log.raw; do
		[[ -f "$file" && "$file" != "$RAW_LOG_FILE" ]] && rm -f -- "$file"
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
	LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d_%H-%M-%S').log"
	RAW_LOG_FILE="${LOG_FILE}.raw"
	DOTFILES_LOG_ACTIVE=true
	_prune_action_logs
	trap finalize_log_file EXIT
	exec > >(tee -a "$RAW_LOG_FILE") 2>&1
}
