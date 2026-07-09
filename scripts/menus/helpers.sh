# shellcheck shell=bash

resolve_dotfiles_cmd() {
	if [[ -x "$DOTFILES_DIR/bin/bin/dotfiles" ]]; then
		printf '%s\n' "$DOTFILES_DIR/bin/bin/dotfiles"
		return 0
	fi
	local cmd
	cmd="$(command -v dotfiles 2>/dev/null || true)"
	if [[ -n "$cmd" ]]; then
		printf '%s\n' "$cmd"
		return 0
	fi
	return 1
}

ext_pick_target() {
	local -a _ext_pick_labels=(
		"VS Code (WSL)"
		"Cursor (WSL)"
		"VS Code (Windows)"
		"Cursor (Windows)"
		"Back"
	)
	local -a _ext_pick_keys=(vscode-wsl cursor-wsl vscode-win cursor-win back)
	local choice=''

	MENU_SIMPLE_TITLE="Select environment"
	MENU_SIMPLE_BREADCRUMB="Dotfiles › Extensions"
	MENU_SIMPLE_HINT="Up/Down navigate   Enter confirm"
	MENU_SIMPLE_LABELS=("${_ext_pick_labels[@]}")
	MENU_SIMPLE_KEYS=("${_ext_pick_keys[@]}")
	MENU_SIMPLE_TYPES=()

	if ! choice="$(menu_simple_run)"; then
		return 1
	fi
	[[ "$choice" == "back" ]] && return 1
	printf '%s\n' "$choice"
}

ext_checkbox_from_tsv() {
	local dotfiles_cmd="$1"
	local subcmd="$2"
	local target="$3"
	local -a lines=()
	local line checked ext_line status

	mapfile -t lines < <("$dotfiles_cmd" ext "$subcmd" "$target")

	MENU_CB_IDS=()
	MENU_CB_LABELS=()
	MENU_CB_CHECKED=()
	MENU_CB_STATUS=()

	for line in "${lines[@]}"; do
		[[ -z "$line" ]] && continue
		case "$subcmd" in
		list-edit)
			IFS='|' read -r checked ext_line status <<<"$line"
			MENU_CB_IDS+=("$ext_line")
			MENU_CB_LABELS+=("$ext_line")
			MENU_CB_CHECKED+=("$([[ "$checked" == "1" ]] && echo 1 || echo 0)")
			MENU_CB_STATUS+=("$status")
			;;
		list-missing | list-extra)
			IFS='|' read -r ext_line _ _ <<<"$line"
			MENU_CB_IDS+=("$ext_line")
			MENU_CB_LABELS+=("$ext_line")
			if [[ "$subcmd" == "list-missing" ]]; then
				MENU_CB_CHECKED+=(1)
				MENU_CB_STATUS+=("not installed")
			else
				MENU_CB_CHECKED+=(0)
				MENU_CB_STATUS+=("not in manifest")
			fi
			;;
		esac
	done

	((${#MENU_CB_IDS[@]} > 0))
}
