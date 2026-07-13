# shellcheck shell=bash
# Submenu loop: simple menu → dispatch → pause (unless Back).
# Depends on: menu_simple.sh, ui.sh, tty.sh

# shellcheck disable=SC2034  # MENU_SIMPLE_* consumed by menu_simple_run
menu_submenu_loop() {
	local title="$1"
	local breadcrumb="$2"
	local labels_name="$3"
	local keys_name="$4"
	local dispatch_fn="$5"
	local -n _msl_labels="$labels_name"
	local -n _msl_keys="$keys_name"
	local choice=''

	while true; do
		MENU_SIMPLE_TITLE="$title"
		MENU_SIMPLE_BREADCRUMB="$breadcrumb"
		MENU_SIMPLE_HINT="${MENU_SUBMENU_HINT:-Up/Down navigate   Enter confirm}"
		MENU_SIMPLE_LABELS=("${_msl_labels[@]}")
		MENU_SIMPLE_KEYS=("${_msl_keys[@]}")

		if [[ -v MENU_SUBMENU_TYPES ]]; then
			MENU_SIMPLE_TYPES=("${MENU_SUBMENU_TYPES[@]}")
		else
			MENU_SIMPLE_TYPES=()
		fi

		if [[ -v MENU_SUBMENU_DESCS ]]; then
			MENU_SIMPLE_DESCS=("${MENU_SUBMENU_DESCS[@]}")
		else
			unset MENU_SIMPLE_DESCS
		fi
		if [[ -n "${MENU_SUBMENU_DESC_FN:-}" ]]; then
			MENU_SIMPLE_DESC_FN="$MENU_SUBMENU_DESC_FN"
		else
			unset MENU_SIMPLE_DESC_FN
		fi

		if ! choice="$(menu_simple_run)"; then
			return 0
		fi
		MENU_SIMPLE_RESULT="$choice"

		if [[ "$choice" == "back" ]]; then
			return 0
		fi

		ui_clear
		local dispatch_rc=0
		"$dispatch_fn" "$choice" || dispatch_rc=$?
		ui_pause
	done
}
