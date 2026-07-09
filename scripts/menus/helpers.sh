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

_ext_pick_target_desc_fn() {
	case "$1" in
	0)
		echo "Target VS Code extensions running inside WSL."
		echo "Uses the WSL extension store path."
		;;
	1)
		echo "Target Cursor extensions running inside WSL."
		echo "Uses the WSL Cursor extension store path."
		;;
	2)
		echo "Target VS Code extensions on the Windows host."
		echo "Uses the Windows-side VS Code extension store."
		;;
	3)
		echo "Target Cursor extensions on the Windows host."
		echo "Uses the Windows-side Cursor extension store."
		;;
	4)
		echo "Cancel target selection and return to the caller."
		;;
	esac
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
	MENU_SIMPLE_DESC_FN=_ext_pick_target_desc_fn

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

	MENU_CB_DESC_FN=_menu_cb_row_desc_fn
	((${#MENU_CB_IDS[@]} > 0))
}

_menu_cb_row_desc_fn() {
	local idx="$1"
	local label="${MENU_CB_LABELS[$idx]:-}"
	local status="${MENU_CB_STATUS[$idx]:-}"

	printf '%s\n' "${MENU_CB_IDS[$idx]:-$label}"
	printf '%s\n' "$status"
}

_menu_mx_row_desc_fn() {
	local idx="$1"
	local ext_id="${MENU_MX_ROWS[$idx]:-}"
	local label="${MENU_MX_LABELS[$idx]:-}"
	local mode="${MENU_MX_MODE:-edit}"
	local c idx2 m i store_ok target
	local -a parts=()
	local joined

	printf '%s\n' "$ext_id"
	for c in 0 1 2 3; do
		idx2=$((idx * 4 + c))
		m="${MENU_MX_MANIFEST[$idx2]:-0}"
		i="${MENU_MX_INSTALLED[$idx2]:-0}"
		store_ok="${MENU_MX_STORE_OK[$idx2]:-1}"
		[[ "$store_ok" -eq 0 ]] && continue
		target="${MENU_MX_COL_KEYS[$c]}"
		case "$mode" in
		edit)
			if [[ "$m" -eq 1 || "$i" -eq 1 ]]; then
				parts+=("${target}: m=${m} i=${i}")
			fi
			;;
		restore)
			if [[ "$m" -eq 1 && "$i" -eq 0 ]]; then
				parts+=("${target}: missing")
			elif [[ "$m" -eq 1 && "$i" -eq 1 ]]; then
				parts+=("${target}: installed")
			fi
			;;
		remove)
			if [[ "$m" -eq 0 && "$i" -eq 1 ]]; then
				parts+=("${target}: extra")
			fi
			;;
		esac
	done

	if ((${#parts[@]} > 0)); then
		joined="$(IFS=' · '; echo "${parts[*]}")"
		printf '%s\n' "$joined"
	elif [[ -n "$label" && "$label" != "$ext_id" ]]; then
		printf '%s\n' "$label"
	else
		printf '%s\n' "Tab switches column; Space toggles the highlighted cell."
	fi
}

ext_matrix_from_tsv() {
	local dotfiles_cmd="$1"
	local subcmd="$2"
	local mode line ext_id display
	local -a lines=()
	local c idx m i cell_line store_ok col_key

	case "$subcmd" in
	list-edit-all) mode=edit ;;
	list-missing-all) mode=restore ;;
	list-extra-all) mode=remove ;;
	*) return 1 ;;
	esac

	mapfile -t lines < <("$dotfiles_cmd" ext "$subcmd")

	MENU_MX_MODE="$mode"
	MENU_MX_ROWS=()
	MENU_MX_LABELS=()
	MENU_MX_LINES=()
	MENU_MX_MANIFEST=()
	MENU_MX_INSTALLED=()
	MENU_MX_CHECKED=()
	MENU_MX_TOGGLEABLE=()
	MENU_MX_STORE_OK=()
	MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
	MENU_MX_COL_LABELS=(vscode-wsl vscode-win cursor-wsl cursor-win)

	for line in "${lines[@]}"; do
		[[ -z "$line" ]] && continue
		IFS='|' read -r ext_id display \
			c0l c0m c0i c1l c1m c1i c2l c2m c2i c3l c3m c3i \
			c0a c1a c2a c3a <<<"$line"
		[[ -z "${c0a:-}" ]] && c0a=1 c1a=1 c2a=1 c3a=1
		MENU_MX_ROWS+=("$ext_id")
		MENU_MX_LABELS+=("$display")
		for c in 0 1 2 3; do
			case "$c" in
			0) cell_line="$c0l"; m="$c0m"; i="$c0i"; store_ok="$c0a" ;;
			1) cell_line="$c1l"; m="$c1m"; i="$c1i"; store_ok="$c1a" ;;
			2) cell_line="$c2l"; m="$c2m"; i="$c2i"; store_ok="$c2a" ;;
			3) cell_line="$c3l"; m="$c3m"; i="$c3i"; store_ok="$c3a" ;;
			esac
			idx=$(( (${#MENU_MX_ROWS[@]} - 1) * 4 + c ))
			MENU_MX_LINES[$idx]="$cell_line"
			MENU_MX_MANIFEST[$idx]="$m"
			MENU_MX_INSTALLED[$idx]="$i"
			MENU_MX_STORE_OK[$idx]="${store_ok:-1}"
			col_key="${MENU_MX_COL_KEYS[$c]}"
			if [[ "${MENU_MX_STORE_OK[$idx]}" -eq 0 ]]; then
				MENU_MX_CHECKED[$idx]=0
				MENU_MX_TOGGLEABLE[$idx]=0
				continue
			fi
			case "$mode" in
			edit)
				MENU_MX_CHECKED[$idx]="$m"
				if [[ "$m" -eq 1 || "$i" -eq 1 ]]; then
					MENU_MX_TOGGLEABLE[$idx]=1
				else
					MENU_MX_CHECKED[$idx]=0
					MENU_MX_TOGGLEABLE[$idx]=1
				fi
				;;
			restore)
				if [[ "$m" -eq 1 && "$i" -eq 0 ]]; then
					MENU_MX_CHECKED[$idx]=1
					MENU_MX_TOGGLEABLE[$idx]=1
				else
					MENU_MX_CHECKED[$idx]=0
					MENU_MX_TOGGLEABLE[$idx]=0
				fi
				;;
			remove)
				MENU_MX_CHECKED[$idx]=0
				if [[ "$i" -eq 1 && "$m" -eq 0 ]]; then
					MENU_MX_TOGGLEABLE[$idx]=1
				else
					MENU_MX_TOGGLEABLE[$idx]=0
				fi
				;;
			esac
		done
	done

	MENU_MX_DESC_FN=_menu_mx_row_desc_fn
	((${#MENU_MX_ROWS[@]} > 0))
}

ext_matrix_toggle_cell() {
	local row="$1" col="$2"
	local idx c other line ext_id

	idx=$((row * 4 + col))
	ext_id="${MENU_MX_ROWS[$row]}"

	if [[ "${MENU_MX_TOGGLEABLE[$idx]:-0}" -ne 1 ]]; then
		return 1
	fi

	if [[ "${MENU_MX_CHECKED[$idx]:-0}" -eq 1 ]]; then
		MENU_MX_CHECKED[$idx]=0
		if [[ "${MENU_MX_MANIFEST[$idx]:-0}" -eq 0 ]]; then
			MENU_MX_LINES[$idx]=''
		fi
		return 0
	fi

	MENU_MX_CHECKED[$idx]=1
	line="${MENU_MX_LINES[$idx]:-}"
	if [[ -z "$line" ]]; then
		for c in 0 1 2 3; do
			other=$((row * 4 + c))
			[[ -n "${MENU_MX_LINES[$other]:-}" ]] && line="${MENU_MX_LINES[$other]}"
		done
		[[ -z "$line" ]] && line="$ext_id"
		MENU_MX_LINES[$idx]="$line"
	fi
	return 0
}

ext_matrix_is_risky() {
	local idx="$1" mode="$2"
	local m i store_ok line

	[[ "${MENU_MX_CHECKED[$idx]:-0}" -eq 0 ]] && return 1
	m="${MENU_MX_MANIFEST[$idx]:-0}"
	i="${MENU_MX_INSTALLED[$idx]:-0}"
	store_ok="${MENU_MX_STORE_OK[$idx]:-1}"
	line="${MENU_MX_LINES[$idx]:-}"

	[[ "$store_ok" -eq 0 ]] && return 0

	case "$mode" in
	edit)
		[[ "$m" -eq 0 && "$i" -eq 0 ]] && return 0
		[[ -z "$line" ]] && return 0
		;;
	restore)
		[[ "$line" != *@* ]] && return 0
		;;
	esac
	return 1
}

ext_matrix_count_risky() {
	local mode="$1" count=0 idx

	for idx in "${!MENU_MX_CHECKED[@]}"; do
		ext_matrix_is_risky "$idx" "$mode" && count=$((count + 1))
	done
	printf '%s\n' "$count"
}

ext_matrix_format_risky_lines() {
	local mode="$1" max="${2:-8}"
	local idx row col target ext_id line n=0

	for idx in "${!MENU_MX_CHECKED[@]}"; do
		ext_matrix_is_risky "$idx" "$mode" || continue
		row=$((idx / 4))
		col=$((idx % 4))
		target="${MENU_MX_COL_KEYS[$col]}"
		ext_id="${MENU_MX_ROWS[$row]}"
		line="${MENU_MX_LINES[$idx]:-$ext_id}"
		printf '  - %s @ %s (%s)\n' "$ext_id" "$target" "$line"
		n=$((n + 1))
		[[ "$n" -ge "$max" ]] && break
	done
}

ext_matrix_count_checked() {
	local count=0 idx

	for idx in "${!MENU_MX_CHECKED[@]}"; do
		[[ "${MENU_MX_CHECKED[$idx]:-0}" -eq 1 ]] && count=$((count + 1))
	done
	printf '%s\n' "$count"
}

ext_matrix_apply_edit() {
	local dotfiles_cmd="$1"
	local risky_count target col tmpfile row idx line

	risky_count="$(ext_matrix_count_risky edit)"
	if [[ "$risky_count" -gt 0 ]]; then
		printf '\n' >/dev/tty
		printf '  %s%s%s\n' "$C_YELLOW" \
			"Warning: ${risky_count} checked cell(s) add manifest entries without a local install." \
			"$C_RESET" >/dev/tty
		ext_matrix_format_risky_lines edit 12 >/dev/tty
		printf '\n' >/dev/tty
		if ! ui_confirm_yes_no "Save manifest anyway?"; then
			return 1
		fi
	fi

	for col in 0 1 2 3; do
		target="${MENU_MX_COL_KEYS[$col]}"
		tmpfile="$(mktemp)"
		for row in "${!MENU_MX_ROWS[@]}"; do
			idx=$((row * 4 + col))
			[[ "${MENU_MX_STORE_OK[$idx]:-0}" -eq 0 ]] && continue
			[[ "${MENU_MX_CHECKED[$idx]:-0}" -eq 1 ]] || continue
			line="${MENU_MX_LINES[$idx]:-}"
			[[ -n "$line" ]] && printf '%s\n' "$line"
		done | sort -u >"$tmpfile"
		"$dotfiles_cmd" ext sync-manifest "$target" <"$tmpfile"
		rm -f "$tmpfile"
	done
}

ext_matrix_apply_restore() {
	local dotfiles_cmd="$1"
	local risky_count target col tmpfile row idx line skipped=0

	risky_count="$(ext_matrix_count_risky restore)"
	if [[ "$risky_count" -gt 0 ]]; then
		printf '\n' >/dev/tty
		printf '  %s%s%s\n' "$C_YELLOW" \
			"Warning: ${risky_count} selected install(s) may fail (wrong IDE store or missing version)." \
			"$C_RESET" >/dev/tty
		ext_matrix_format_risky_lines restore 12 >/dev/tty
		printf '\n' >/dev/tty
		if ! ui_confirm_yes_no "Continue with installs that may fail?"; then
			return 1
		fi
	fi

	for col in 0 1 2 3; do
		target="${MENU_MX_COL_KEYS[$col]}"
		tmpfile="$(mktemp)"
		for row in "${!MENU_MX_ROWS[@]}"; do
			idx=$((row * 4 + col))
			[[ "${MENU_MX_CHECKED[$idx]:-0}" -eq 1 ]] || continue
			if [[ "${MENU_MX_STORE_OK[$idx]:-0}" -eq 0 ]]; then
				skipped=$((skipped + 1))
				continue
			fi
			line="${MENU_MX_LINES[$idx]:-}"
			[[ -n "$line" ]] && printf '%s\n' "$line"
		done >"$tmpfile"
		if [[ -s "$tmpfile" ]]; then
			"$dotfiles_cmd" ext install-lines "$target" <"$tmpfile"
		fi
		rm -f "$tmpfile"
	done
	if [[ "$skipped" -gt 0 ]]; then
		printf '  %sSkipped %d incompatible cell(s) (wrong IDE store).%s\n' \
			"$C_YELLOW" "$skipped" "$C_RESET" >/dev/tty
	fi
}

ext_matrix_apply_remove() {
	local dotfiles_cmd="$1"
	local target col tmpfile row idx line

	for col in 0 1 2 3; do
		target="${MENU_MX_COL_KEYS[$col]}"
		tmpfile="$(mktemp)"
		for row in "${!MENU_MX_ROWS[@]}"; do
			idx=$((row * 4 + col))
			[[ "${MENU_MX_CHECKED[$idx]:-0}" -eq 1 ]] || continue
			line="${MENU_MX_LINES[$idx]:-}"
			[[ -n "$line" ]] && printf '%s\n' "$line"
		done >"$tmpfile"
		if [[ -s "$tmpfile" ]]; then
			"$dotfiles_cmd" ext remove-lines "$target" <"$tmpfile"
		fi
		rm -f "$tmpfile"
	done
}
