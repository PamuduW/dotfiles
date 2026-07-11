# shellcheck shell=bash
# GitHub Releases API helpers (User-Agent + optional GITHUB_TOKEN).

github_api_release_json() {
	local repo="$1" tmp_file curl_error token="${GITHUB_TOKEN:-}"
	local -a auth_header=()

	[[ -n "$token" ]] && auth_header=(-H "Authorization: Bearer ${token}")
	tmp_file="$(mktemp)" || return 1

	if ! curl_error="$(curl -fsSL \
		--connect-timeout 10 \
		--max-time 30 \
		--retry 2 \
		--retry-delay 1 \
		-H "Accept: application/vnd.github+json" \
		-H "User-Agent: dotfiles-bootstrap" \
		"${auth_header[@]}" \
		"https://api.github.com/repos/${repo}/releases/latest" -o "$tmp_file" 2>&1)"; then
		rm -f "$tmp_file"
		[[ -n "$token" ]] && curl_error="${curl_error//"$token"/[redacted]}"
		echo "GitHub Releases API request failed for ${repo}." >&2
		if [[ "$curl_error" == *"403"* || "$curl_error" == *"429"* ]]; then
			echo "  GitHub denied or rate-limited the request; wait for the limit reset or set GITHUB_TOKEN." >&2
		else
			echo "  Check network/TLS access to api.github.com, then retry." >&2
		fi
		[[ -n "$curl_error" ]] && echo "  curl: ${curl_error}" >&2
		return 1
	fi
	cat "$tmp_file"
	rm -f "$tmp_file"
}

# Prints the SHA-256 digest published by GitHub for a named release asset.
# GitHub exposes this as "sha256:<hex>" in the releases API.  Callers must
# fail closed when no digest is available rather than trusting an unchecked
# binary download.
github_release_asset_sha256() {
	local repo="$1" asset_name="$2" json

	command -v python3 >/dev/null 2>&1 || return 1
	json="$(github_api_release_json "$repo")" || return 1
	python3 -c '
import json
import sys

asset_name = sys.argv[1]
for asset in json.load(sys.stdin).get("assets", []):
    if asset.get("name") == asset_name:
        digest = asset.get("digest", "")
        if digest.startswith("sha256:") and len(digest) == 71:
            print(digest[len("sha256:"):])
            raise SystemExit(0)
raise SystemExit(1)
' "$asset_name" <<<"$json"
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
