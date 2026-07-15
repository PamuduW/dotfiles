# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_SIMPLE_* globals are consumed by menu_simple_run.

PACKAGE_LIB_NAMES=()
PACKAGE_LIB_TAGS=()
PACKAGE_LIB_DESCRIPTIONS=()

_package_lib_trim() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

_package_lib_fit() {
	local value="$1" width="$2"
	if declare -F menu_fit_line >/dev/null; then
		menu_fit_line "$value" "$width"
	else
		_rt_fit_line "$value" "$width"
	fi
}

_package_lib_header() {
	local title="$1" breadcrumb="$2" cols="$3"
	if declare -F ui_print_header >/dev/null; then
		ui_print_header "$title" "$breadcrumb" "$cols"
	else
		rt_print_header "$title" "$breadcrumb"
	fi
}

package_metadata_load() {
	local file="${1:-${PKG_FILE:-}}"
	local line current_tag='' package_part description name
	local -A seen=()

	[[ -f "$file" ]] || {
		printf 'Package metadata file not found: %s\n' "$file" >&2
		return 1
	}
	PACKAGE_LIB_NAMES=()
	PACKAGE_LIB_TAGS=()
	PACKAGE_LIB_DESCRIPTIONS=()

	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^#[[:space:]]*@([a-zA-Z_]+) ]]; then
			current_tag="${BASH_REMATCH[1]}"
			continue
		fi
		[[ -z "$line" || "$line" == \#* ]] && continue
		[[ -n "$current_tag" && "$line" == *'#'* ]] || {
			printf 'Malformed package metadata line: %s\n' "$line" >&2
			return 1
		}
		package_part="${line%%#*}"
		description="${line#*#}"
		name="$(_package_lib_trim "$package_part")"
		description="$(_package_lib_trim "$description")"
		[[ -n "$name" && -n "$description" && -z "${seen[$name]+x}" ]] || {
			printf 'Invalid or duplicate package metadata: %s\n' "$name" >&2
			return 1
		}
		seen["$name"]=1
		PACKAGE_LIB_NAMES+=("$name")
		PACKAGE_LIB_TAGS+=("$current_tag")
		PACKAGE_LIB_DESCRIPTIONS+=("$description")
	done <"$file"

	[[ "${#PACKAGE_LIB_NAMES[@]}" -eq 28 ]] || {
		printf 'Expected 28 packages, found %d\n' "${#PACKAGE_LIB_NAMES[@]}" >&2
		return 1
	}
}

package_lib_render_components() {
	local cols="${1:-$(menu_tty_cols)}"
	local i key label description row

	_package_lib_header "Package Lib" "Dotfiles › Package Lib" "$cols"
	printf '  %s\n' "$(_package_lib_fit "component            label and description" "$((cols - 2))")"
	for i in "${!COMP_KEYS[@]}"; do
		key="${COMP_KEYS[$i]}"
		label="${COMP_LABELS[$i]}"
		description="$(comp_description "$key" | sed -n '1p')"
		row="$(printf '%-20s %s — %s' "$key" "$label" "$description")"
		printf '  %s\n' "$(_package_lib_fit "$row" "$((cols - 2))")"
	done
}

package_lib_render_packages_page() {
	local page="$1" page_size="$2" cols="${3:-$(menu_tty_cols)}"
	local page_count start end i row

	if ((${#PACKAGE_LIB_NAMES[@]} == 0)); then
		package_metadata_load "${PKG_FILE:-}" || return 1
	fi
	page_count="$(menu_page_count "${#PACKAGE_LIB_NAMES[@]}" "$page_size")"
	((page >= 0 && page < page_count)) || return 1
	read -r start end < <(menu_page_range "${#PACKAGE_LIB_NAMES[@]}" "$page_size" "$page")

	_package_lib_header "System packages" "Dotfiles › Package Lib › System packages" "$cols"
	printf '  Page %d/%d   Showing %d-%d of %d\n\n' \
		"$((page + 1))" "$page_count" "$((start + 1))" "$((end + 1))" "${#PACKAGE_LIB_NAMES[@]}"
	for ((i = start; i <= end; i++)); do
		row="$(printf '%-20s [%s] %s' \
			"${PACKAGE_LIB_NAMES[$i]}" "${PACKAGE_LIB_TAGS[$i]}" "${PACKAGE_LIB_DESCRIPTIONS[$i]}")"
		printf '  %s\n' "$(_package_lib_fit "$row" "$((cols - 2))")"
	done
}

package_lib_packages_menu() {
	local rows cols page_size page=0 page_count action

	package_metadata_load "${PKG_FILE:-}" || {
		ui_pause
		return 1
	}
	rows="$(menu_tty_rows)"
	cols="$(menu_tty_cols)"
	page_size="$(menu_page_size "$rows" 8)"
	page_count="$(menu_page_count "${#PACKAGE_LIB_NAMES[@]}" "$page_size")"

	while true; do
		{
			ui_clear
			package_lib_render_packages_page "$page" "$page_size" "$cols"
			printf '\n  Up/Down page   q back\n'
		} >/dev/tty
		action="$(menu_read_key)"
		case "$action" in
		cancel) return 0 ;;
		down | right | page_down)
			((page + 1 < page_count)) && page=$((page + 1))
			;;
		up | left | page_up)
			((page > 0)) && page=$((page - 1))
			;;
		esac
	done
}

_package_lib_desc_fn() {
	comp_description "${COMP_KEYS[$1]}"
}

package_lib_menu() {
	local choice i

	while true; do
		MENU_SIMPLE_TITLE="Package Lib"
		MENU_SIMPLE_BREADCRUMB="Dotfiles › Package Lib"
		MENU_SIMPLE_HINT="Up/Down navigate   Enter details   q back"
		MENU_SIMPLE_LABELS=()
		MENU_SIMPLE_KEYS=("${COMP_KEYS[@]}")
		MENU_SIMPLE_TYPES=()
		MENU_SIMPLE_DESC_FN=_package_lib_desc_fn
		for i in "${!COMP_KEYS[@]}"; do
			MENU_SIMPLE_LABELS+=("${COMP_KEYS[$i]} — ${COMP_LABELS[$i]}")
		done

		if ! choice="$(menu_simple_run)"; then
			return 0
		fi
		if [[ "$choice" == system_packages ]]; then
			package_lib_packages_menu || return $?
			continue
		fi
		{
			ui_clear
			_package_lib_header "${COMP_LABELS[$(comp_key_index "$choice")]}" \
				"Dotfiles › Package Lib › ${choice}" "$(menu_tty_cols)"
			comp_description "$choice"
		} >/dev/tty
		ui_pause
	done
}
