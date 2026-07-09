# shellcheck shell=bash
# GitHub Releases API helpers (User-Agent + optional GITHUB_TOKEN).

github_api_release_json() {
	local repo="$1"
	local -a auth_header=()

	[[ -n "${GITHUB_TOKEN:-}" ]] && auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

	curl -fsSL \
		-H "Accept: application/vnd.github+json" \
		-H "User-Agent: dotfiles-bootstrap" \
		"${auth_header[@]}" \
		"https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null
}

# Prints tag without leading "v" (e.g. v1.400 -> 1.400).
github_latest_release_version() {
	local repo="$1"
	local json tag

	json="$(github_api_release_json "$repo")" || return 1
	tag="$(printf '%s' "$json" | grep -Po '"tag_name":\s*"\K[^"]+' | head -n1)" || return 1
	[[ -n "$tag" ]] || return 1
	printf '%s\n' "${tag#v}"
}
