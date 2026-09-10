# shellcheck shell=bash

# The update workflow lives in the `dotfiles` CLI, which owns its own library
# set (update_workflow.sh, full_update.sh). The menu process does not load
# those, so both menu actions delegate to the CLI through one helper.
_run_dotfiles_subcommand() {
	local dotfiles_cmd rc=0
	declare -F start_action_log >/dev/null 2>&1 && start_action_log

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	"$dotfiles_cmd" "$@" || rc=$?
	return "$rc"
}

run_update_flow() {
	_run_dotfiles_subcommand update
}

# Typing `dotfiles full-update` is the authorization on the CLI, so the menu
# asks once before starting the unattended flow.
#
# c/x rather than y/n: the execution plan already spends those two keys on
# "confirm" and "confirm forced", and a forced full update is the same request
# as a forced install. One key, one meaning, in both places.
run_full_update_flow() {
	local answer='' notice=''
	while true; do
		ui_print_header 'Full Update' 'Dotfiles › Full Update'
		printf '  Updates Dotfiles, then installs and updates Agentbot.\n'
		printf '  Application prompts are auto-approved.\n'
		printf '  Replaceable local Git state in both repositories may be backed up and replaced.\n\n'
		printf '  x reinstalls components that are already present.\n\n'
		if [[ -n "$notice" ]]; then
			printf '%s\n\n' "$notice"
			notice=''
		fi
		# A failed read is EOF or a closed terminal, not an answer. Without
		# this the loop redraws and asks again forever, printing "Invalid
		# choice." at whatever speed the terminal can take it.
		if ! read_tty_line answer "$(ui_full_update_confirm_prompt)"; then
			printf '\n  Full update cancelled.\n'
			return 0
		fi
		printf '%s' "${C_RESET:-}"
		case "$answer" in
		c | C)
			return_full_update_run
			return $?
			;;
		x | X)
			printf '\n  Forced reinstall: already-installed components will be reinstalled.\n'
			return_full_update_run --force
			return $?
			;;
		q | Q)
			printf '\n  Full update cancelled.\n'
			return 0
			;;
		# Carried, not printed: the loop redraws the screen next, and ui_clear
		# would take this with it before it could be read.
		*) notice='  Invalid choice.' ;;
		esac
	done
}

return_full_update_run() {
	_run_dotfiles_subcommand full-update "$@"
}

# The list itself was noise: twenty timestamped filenames and their sizes,
# none of which an operator can act on from a menu. What they actually want is
# to get at the folder, or to clear it. The CLI keeps `dotfiles logs --list`
# and `--last` for reading one.
_logs_dir() { printf '%s\n' "${DOTFILES_DIR}/log"; }

_logs_count() {
	local dir
	dir="$(_logs_dir)"
	[[ -d "$dir" ]] || {
		printf '0\n'
		return 0
	}
	find "$dir" -maxdepth 1 -type f -name '*.log' -print | wc -l
}

# Windows interop, because this is a WSL product and the folder an operator
# wants to open is on the Linux side. wslpath renders the \\wsl.localhost path
# Explorer understands; without interop there is nothing to open and the
# action says so rather than failing silently.
_logs_open_in() {
	local what="$1" dir
	dir="$(_logs_dir)"
	[[ -d "$dir" ]] || {
		printf '  No log folder yet.\n'
		return 0
	}
	case "$what" in
	explorer)
		if ! command -v explorer.exe >/dev/null 2>&1; then
			printf '  explorer.exe is not reachable from this shell.\n'
			printf '  The folder is: %s\n' "$dir"
			return 0
		fi
		# explorer.exe returns 1 even when it opens the window.
		explorer.exe "$(wslpath -w "$dir" 2>/dev/null || printf '%s' "$dir")" >/dev/null 2>&1 || true
		printf '  Opened %s in Explorer.\n' "$dir"
		;;
	vscode)
		if ! command -v code >/dev/null 2>&1; then
			printf '  code is not on PATH.\n'
			printf '  The folder is: %s\n' "$dir"
			return 0
		fi
		code "$dir" >/dev/null 2>&1 || {
			printf '  code could not open %s.\n' "$dir"
			return 0
		}
		printf '  Opened %s in VS Code.\n' "$dir"
		;;
	esac
}

# Deleting the capture the current run is still writing would leave its
# finalizer working on an unlinked inode, so the live one is kept back. It is
# named by LOG_FILE/RAW_LOG_FILE when this menu runs under an action log.
_logs_delete_all() {
	local dir file removed=0 kept=0
	dir="$(_logs_dir)"
	[[ -d "$dir" ]] || {
		printf '  No log folder yet.\n'
		return 0
	}
	while IFS= read -r file; do
		if [[ "$file" == "${LOG_FILE:-}" || "$file" == "${RAW_LOG_FILE:-}" ]]; then
			kept=$((kept + 1))
			continue
		fi
		rm -f -- "$file" && removed=$((removed + 1))
	done < <(find "$dir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.log.raw' \) -print)
	printf '  Deleted %d log(s).\n' "$removed"
	((kept == 0)) || printf '  Kept %d still being written by this run.\n' "$kept"
}

run_logs_flow() {
	local answer='' count
	while true; do
		ui_clear
		ui_print_header 'Logs' 'Dotfiles › Logs'
		count="$(_logs_count)"
		printf '  %s log(s)\n\n' "$count"
		printf '  %s\n' "$(ui_format_shortcuts e open_folder_in_explorer c open_folder_in_vscode)"
		if ! read_tty_line answer "  $(ui_format_shortcuts d delete_all q back_to_menu) : ${C_RESET:-}"; then
			return 0
		fi
		printf '%s' "${C_RESET:-}"
		case "$answer" in
		e | E)
			printf '\n'
			_logs_open_in explorer
			ui_pause
			;;
		c | C)
			printf '\n'
			_logs_open_in vscode
			ui_pause
			;;
		d | D)
			printf '\n'
			if ((count == 0)); then
				printf '  Nothing to delete.\n'
			elif ui_confirm_yes_no "  Delete all ${count} log(s)?"; then
				printf '\n'
				_logs_delete_all
			else
				printf '  Kept.\n'
			fi
			ui_pause
			;;
		q | Q) return 0 ;;
		*)
			printf '\n  Invalid choice.\n'
			ui_pause
			;;
		esac
	done
}

# Mutating, and it rewrites links in the operator's home directory, so it asks
# first -- typing `dotfiles restow` is the authorization on the CLI side.
run_restow_flow() {
	ui_print_header 'Restow' 'Dotfiles › Restow'
	printf '  Re-applies the bash, bin, and readline stow packages.\n'
	printf '  Replaces the matching links in %s; installs nothing.\n\n' "$HOME"
	if ! ui_confirm_yes_no '  Re-apply the stow links?'; then
		printf '  Restow cancelled.\n'
		return 0
	fi
	printf '\n'
	_run_dotfiles_subcommand restow
}
