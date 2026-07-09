# shellcheck shell=bash

_ext_menu_dispatch() {
	local action="$1"
	local dotfiles_cmd target tmpfile

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	case "$action" in
	status)
		ui_clear
		printf '\n' >/dev/tty
		ui_print_header "Extensions status" "Dotfiles › Extensions" "$(menu_tty_cols)" >/dev/tty
		"$dotfiles_cmd" ext compare all
		;;
	edit)
		target="$(ext_pick_target)" || return 0
		ui_clear
		if ! ext_checkbox_from_tsv "$dotfiles_cmd" list-edit "$target"; then
			echo "No installed extensions for ${target}."
			return 0
		fi
		MENU_CB_TITLE="Edit manifest"
		MENU_CB_BREADCRUMB="Dotfiles › Extensions › ${target}"
		MENU_CB_HINT="Up/Down navigate   Space toggle   a all   n none   Enter confirm   q back"
		if ! menu_checkbox_run; then
			return 0
		fi
		tmpfile="$(mktemp)"
		local i
		for i in "${!MENU_CB_IDS[@]}"; do
			[[ "${MENU_CB_CHECKED[$i]}" -eq 1 ]] && printf '%s\n' "${MENU_CB_IDS[$i]}"
		done >"$tmpfile"
		"$dotfiles_cmd" ext sync-manifest "$target" <"$tmpfile"
		rm -f "$tmpfile"
		;;
	restore)
		target="$(ext_pick_target)" || return 0
		ui_clear
		if ! ext_checkbox_from_tsv "$dotfiles_cmd" list-missing "$target"; then
			echo "Nothing to restore — all manifest extensions are installed."
			return 0
		fi
		MENU_CB_TITLE="Restore missing"
		MENU_CB_BREADCRUMB="Dotfiles › Extensions › ${target}"
		MENU_CB_HINT="Up/Down navigate   Space toggle   a all   n none   Enter confirm   q back"
		if ! menu_checkbox_run; then
			return 0
		fi
		tmpfile="$(mktemp)"
		for i in "${!MENU_CB_IDS[@]}"; do
			[[ "${MENU_CB_CHECKED[$i]}" -eq 1 ]] && printf '%s\n' "${MENU_CB_IDS[$i]}"
		done >"$tmpfile"
		if ui_confirm_yes_no "Install selected extensions for ${target}?"; then
			"$dotfiles_cmd" ext install-lines "$target" <"$tmpfile"
		fi
		rm -f "$tmpfile"
		;;
	remove)
		target="$(ext_pick_target)" || return 0
		ui_clear
		if ! ext_checkbox_from_tsv "$dotfiles_cmd" list-extra "$target"; then
			echo "Nothing to remove — no extras outside manifest."
			return 0
		fi
		MENU_CB_TITLE="Remove extras"
		MENU_CB_BREADCRUMB="Dotfiles › Extensions › ${target}"
		MENU_CB_HINT="Up/Down navigate   Space toggle   a all   n none   Enter confirm   q back"
		if ! menu_checkbox_run; then
			return 0
		fi
		local count=0
		for i in "${!MENU_CB_CHECKED[@]}"; do
			[[ "${MENU_CB_CHECKED[$i]}" -eq 1 ]] && count=$((count + 1))
		done
		if [[ "$count" -eq 0 ]]; then
			echo "No extensions selected."
			return 0
		fi
		tmpfile="$(mktemp)"
		for i in "${!MENU_CB_IDS[@]}"; do
			[[ "${MENU_CB_CHECKED[$i]}" -eq 1 ]] && printf '%s\n' "${MENU_CB_IDS[$i]}"
		done >"$tmpfile"
		if ui_confirm_destructive "Uninstall ${count} extension(s) from ${target}?"; then
			"$dotfiles_cmd" ext remove-lines "$target" <"$tmpfile"
		fi
		rm -f "$tmpfile"
		;;
	esac
}

_ext_menu_labels=(
	"Check status"
	"Edit manifest"
	"Restore"
	"Remove"
	"Back"
)
_ext_menu_keys=(status edit restore remove back)

extensions_menu() {
	menu_submenu_loop "IDE Extensions" "Dotfiles › Extensions" \
		_ext_menu_labels _ext_menu_keys _ext_menu_dispatch
}
