# shellcheck shell=bash
# GitHub Releases API helpers (User-Agent + optional GITHUB_TOKEN).

_github_curl_redact_stderr() {
	local token="$1" stderr_file="$2" content=''
	IFS= read -r -d '' content <"$stderr_file" || true
	printf '%s' "${content//"$token"/[redacted]}" >&2
}

# Keep token discovery and curl authentication inside a child shell. The token
# is supplied through curl's private standard-input config, never its argv.
github_curl() (
	local token='' rc stderr_file old_umask
	if declare -F github_token_export_if_valid >/dev/null; then
		github_token_export_if_valid
		token="${GITHUB_TOKEN:-}"
	fi
	unset GITHUB_TOKEN

	if [[ -z "$token" ]]; then
		curl "$@"
		return
	fi

	old_umask="$(umask)"
	umask 077
	stderr_file="$(mktemp "${TMPDIR:-/tmp}/github-curl.stderr.XXXXXX")" || {
		umask "$old_umask"
		return 1
	}
	umask "$old_umask"
	trap 'rm -f -- "$stderr_file"' EXIT

	if curl --config - "$@" \
		2>"$stderr_file" <<EOF
header = "Authorization: Bearer ${token}"
EOF
	then
		rc=0
	else
		rc=$?
	fi
	_github_curl_redact_stderr "$token" "$stderr_file"
	rm -f -- "$stderr_file"
	trap - EXIT
	return "$rc"
)

github_api_release_json() {
	local repo="$1" tmp_file curl_error

	tmp_file="$(mktemp)" || return 1

	if ! curl_error="$(github_curl -fsSL \
		--connect-timeout 10 \
		--max-time 30 \
		--retry 2 \
		--retry-delay 1 \
		-H "Accept: application/vnd.github+json" \
		-H "User-Agent: dotfiles-bootstrap" \
		"https://api.github.com/repos/${repo}/releases/latest" -o "$tmp_file" 2>&1)"; then
		rm -f "$tmp_file"
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
