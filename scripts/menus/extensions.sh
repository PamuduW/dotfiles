# shellcheck shell=bash

_ext_menu_dispatch() {
	local action="$1"
	local dotfiles_cmd checked_count

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
		ui_clear
		if ! ext_matrix_from_tsv "$dotfiles_cmd" list-edit-all; then
			echo "No extensions found across any target."
			return 0
		fi
		MENU_MX_TITLE="Edit manifest"
		MENU_MX_BREADCRUMB="Dotfiles › Extensions"
		MENU_MX_HINT="↑↓ row   Tab column   Space toggle   Enter save manifest   q back"
		MENU_MX_LEGEND="Y in manifest   N installed only   ? add to manifest (may fail on restore)   × wrong IDE store"
		if ! menu_matrix_run; then
			return 0
		fi
		ext_matrix_apply_edit "$dotfiles_cmd" || echo "Manifest save cancelled."
		;;
	restore)
		ui_clear
		if ! ext_matrix_from_tsv "$dotfiles_cmd" list-missing-all; then
			echo "Nothing to restore — all manifest extensions are installed on every target."
			return 0
		fi
		MENU_MX_TITLE="Restore missing"
		MENU_MX_BREADCRUMB="Dotfiles › Extensions"
		MENU_MX_HINT="↑↓ row   Tab column   Space toggle   Enter install   q back"
		MENU_MX_LEGEND="N missing   × wrong IDE store (skipped on install)"
		if ! menu_matrix_run; then
			return 0
		fi
		checked_count="$(ext_matrix_count_checked)"
		if [[ "$checked_count" -eq 0 ]]; then
			echo "No extensions selected."
			return 0
		fi
		if ui_confirm_yes_no "Install ${checked_count} extension cell(s) across targets?"; then
			ext_matrix_apply_restore "$dotfiles_cmd"
		fi
		;;
	remove)
		ui_clear
		if ! ext_matrix_from_tsv "$dotfiles_cmd" list-extra-all; then
			echo "Nothing to remove — no extras outside manifests on any target."
			return 0
		fi
		MENU_MX_TITLE="Remove extras"
		MENU_MX_BREADCRUMB="Dotfiles › Extensions"
		MENU_MX_HINT="↑↓ row   Tab column   Space toggle   Enter confirm   q back"
		MENU_MX_LEGEND=""
		if ! menu_matrix_run; then
			return 0
		fi
		checked_count="$(ext_matrix_count_checked)"
		if [[ "$checked_count" -eq 0 ]]; then
			echo "No extensions selected."
			return 0
		fi
		if ui_confirm_destructive "Uninstall ${checked_count} extension cell(s) across targets?"; then
			ext_matrix_apply_remove "$dotfiles_cmd"
		fi
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
