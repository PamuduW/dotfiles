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

	[[ "${#PACKAGE_LIB_NAMES[@]}" -eq 31 ]] || {
		printf 'Expected 31 packages, found %d\n' "${#PACKAGE_LIB_NAMES[@]}" >&2
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

package_lib_render_packages_all() {
	local cols="${1:-$(menu_tty_cols)}"
	local package_w=18 tag_w=10 description_w available
	local package_rule tag_rule description_rule package_fit tag_fit description_fit
	local i

	if ((${#PACKAGE_LIB_NAMES[@]} == 0)); then
		package_metadata_load "${PKG_FILE:-}" || return 1
	fi
	_package_lib_header "Package Lib" "Dotfiles › Package Lib" "$cols"
	_rt_ensure_colors
	available=$((cols - 2 - 6))
	description_w=$((available - package_w - tag_w))
	if ((description_w < 18)); then
		package_w=17
		tag_w=9
		description_w=$((available - package_w - tag_w))
	fi
	((description_w < 1)) && description_w=1

	package_fit="$(_package_lib_fit package "$package_w")"
	tag_fit="$(_package_lib_fit category "$tag_w")"
	description_fit="$(_package_lib_fit description "$description_w")"
	printf '  %s%-*s | %-*s | %-*s%s\n' \
		"$C_BOLD" "$package_w" "$package_fit" \
		"$tag_w" "$tag_fit" "$description_w" "$description_fit" "$C_RESET"
	package_rule="$(printf '%*s' "$package_w" '')"
	package_rule="${package_rule// /-}"
	tag_rule="$(printf '%*s' "$tag_w" '')"
	tag_rule="${tag_rule// /-}"
	description_rule="$(printf '%*s' "$description_w" '')"
	description_rule="${description_rule// /-}"
	printf '  %s-+-%s-+-%s\n' "$package_rule" "$tag_rule" "$description_rule"
	for i in "${!PACKAGE_LIB_NAMES[@]}"; do
		package_fit="$(_package_lib_fit "${PACKAGE_LIB_NAMES[$i]}" "$package_w")"
		tag_fit="$(_package_lib_fit "${PACKAGE_LIB_TAGS[$i]}" "$tag_w")"
		description_fit="$(_package_lib_fit "${PACKAGE_LIB_DESCRIPTIONS[$i]}" "$description_w")"
		printf '  %-*s | ' "$package_w" "$package_fit"
		case "${PACKAGE_LIB_TAGS[$i]}" in
		core) printf '%s%s%s' "$C_CYAN" "$tag_fit" "$C_RESET" ;;
		python) printf '%s%s%s' "$C_GREEN" "$tag_fit" "$C_RESET" ;;
		cli) printf '%s%s%s' "$C_YELLOW" "$tag_fit" "$C_RESET" ;;
		system) printf '%s%s%s' "$C_DIM" "$tag_fit" "$C_RESET" ;;
		*) printf '%s' "$tag_fit" ;;
		esac
		if ((tag_w > ${#tag_fit})); then printf '%*s' "$((tag_w - ${#tag_fit}))" ''; fi
		printf ' | %-*s\n' "$description_w" "$description_fit"
	done
}

package_lib_packages_menu() {
	local cols tty_out

	package_metadata_load "${PKG_FILE:-}" || {
		ui_pause
		return 1
	}
	cols="$(menu_tty_cols)"
	tty_out="$(tty_output_path)"
	ui_clear
	package_lib_render_packages_all "$cols" >"$tty_out"
	ui_wait_back
}

package_lib_menu() {
	package_lib_packages_menu
}
