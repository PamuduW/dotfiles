# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_SIMPLE_* globals are consumed by menu_simple_run.

libraries_menu() {
	local choice rc child_available

	while true; do
		MENU_SIMPLE_TITLE='Libraries'
		MENU_SIMPLE_BREADCRUMB='Dotfiles › Libraries'
		MENU_SIMPLE_LABELS=('Command Lib' 'Package Lib')
		MENU_SIMPLE_KEYS=(command_lib package_lib)
		MENU_SIMPLE_DESCS=(
			$'Show Dotfiles commands and their usage.\nRead-only command and mutation matrix.'
			$'Browse the complete system package catalog.\nRead-only package metadata; no probes or installers run.'
		)

		if ! menu_simple_run; then
			MENU_SIMPLE_TITLE='Dotfiles'
			MENU_SIMPLE_BREADCRUMB='Dotfiles'
			return 0
		fi
		choice="${MENU_SIMPLE_RESULT:-}"
		ui_clear
		rc=0
		child_available=false
		case "$choice" in
		command_lib)
			if declare -F command_lib_menu >/dev/null; then
				child_available=true
				command_lib_menu || rc=$?
			else
				printf 'Command Lib is not available in this phase.\n'
				rc=1
			fi
			;;
		package_lib)
			if declare -F package_lib_menu >/dev/null; then
				child_available=true
				package_lib_menu || rc=$?
			else
				printf 'Package Lib is not available in this phase.\n'
				rc=1
			fi
			;;
		*)
			printf 'Unknown Libraries action: %s\n' "$choice" >&2
			rc=2
			;;
		esac
		if ((rc != 0)); then
			printf '%sAction failed (exit %d).%s\n' "${C_RED:-}" "$rc" "${C_RESET:-}" >&2
		fi
		[[ "$child_available" == true ]] || ui_pause
	done
}
