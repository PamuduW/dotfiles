# shellcheck shell=bash
# Shared menu paging helpers (cursor position, page ranges, visible counts).

menu_page_size() {
	local rows="$1"
	local fixed_rows="${2:-7}"
	local page_size=$((rows - fixed_rows))

	((page_size < 1)) && page_size=1
	printf '%s\n' "$page_size"
}

menu_page_for_cursor() {
	local cursor="$1"
	local page_size="$2"

	printf '%s\n' $((cursor / page_size))
}

menu_page_count() {
	local count="$1"
	local page_size="$2"

	printf '%s\n' $(((count + page_size - 1) / page_size))
}

menu_page_range() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local start=$((page * page_size))
	local end=$((start + page_size - 1))

	((end >= count)) && end=$((count - 1))
	printf '%s %s\n' "$start" "$end"
}

menu_page_visible_count() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local start end

	read -r start end < <(menu_page_range "$count" "$page_size" "$page")
	printf '%s\n' $((end - start + 1))
}

menu_page_render_lines() {
	local count="$1"
	local page_size="$2"
	local page="$3"
	local fixed_rows="${4:-7}"
	local visible_count

	visible_count="$(menu_page_visible_count "$count" "$page_size" "$page")"
	printf '%s\n' $((visible_count + fixed_rows))
}
