# shellcheck shell=bash
# Read package names from tagged sections in packages/packages.txt.

read_packages_by_tags() {
	# Usage: read_packages_by_tags tag1 tag2 ...
	# Outputs package names under matching @tag sections.
	[[ -f "$PKG_FILE" ]] || {
		echo "Error: $PKG_FILE not found" >&2
		return 1
	}

	local -A wanted
	local tag
	for tag in "$@"; do wanted["$tag"]=1; done

	local current_tag="" active=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^#[[:space:]]*@([a-zA-Z_]+) ]]; then
			current_tag="${BASH_REMATCH[1]}"
			[[ -n "${wanted[$current_tag]+_}" ]] && active=1 || active=0
			continue
		fi
		[[ "$active" -eq 0 ]] && continue
		local pkg="${line%%#*}"
		pkg="${pkg#"${pkg%%[![:space:]]*}"}"
		pkg="${pkg%"${pkg##*[![:space:]]}"}"
		[[ -n "$pkg" ]] && echo "$pkg"
	done <"$PKG_FILE"
}
