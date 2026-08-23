# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_CB_* globals are consumed by menu_checkbox_run.
# Component selection adapter over the shared checkbox menu.

_COMP_DESC_LINES=2

_comp_menu_desc_fn() {
	comp_description "${COMP_KEYS[$1]}"
}

_component_menu_sync_checked() {
	local i key
	for i in "${!COMP_KEYS[@]}"; do
		key="${COMP_KEYS[$i]}"
		MENU_CB_CHECKED[i]="${COMP_ON[$key]}"
	done
}

_component_menu_toggle() {
	toggle_component "$1"
	_component_menu_sync_checked
	MENU_CB_STATUS_MESSAGE="$TOGGLE_MSG"
}

_component_menu_all() {
	local key
	for key in "${COMP_KEYS[@]}"; do COMP_ON["$key"]=1; done
	_component_menu_sync_checked
}

_component_menu_none() {
	local key
	for key in "${COMP_KEYS[@]}"; do COMP_ON["$key"]=0; done
	_component_menu_sync_checked
}

component_menu() {
	local i key dependency
	declare -g -a MENU_CB_LABELS=() MENU_CB_STATUS=() MENU_CB_CHECKED=()
	for i in "${!COMP_KEYS[@]}"; do
		key="${COMP_KEYS[$i]}"
		dependency="$(comp_dependency "$key")"
		MENU_CB_LABELS[i]="${COMP_LABELS[i]}"
		[[ -n "$dependency" ]] && MENU_CB_LABELS[i]+="  (requires $dependency)"
		MENU_CB_STATUS[i]=''
	done
	_component_menu_sync_checked

	MENU_CB_TITLE='Install Dotfiles'
	MENU_CB_BREADCRUMB='Dotfiles › Install Dotfiles'
	MENU_CB_HINT='Up/Down navigate   Space toggle   a all   n none   Enter confirm   q back'
	MENU_CB_DESC_FN=_comp_menu_desc_fn
	MENU_CB_COMPACT=true
	MENU_CB_TOGGLE_FN=_component_menu_toggle
	MENU_CB_ALL_FN=_component_menu_all
	MENU_CB_NONE_FN=_component_menu_none
	MENU_CB_ALL_MESSAGE='All components enabled'
	MENU_CB_NONE_MESSAGE='All components disabled'
	menu_checkbox_run
}
