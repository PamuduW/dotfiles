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
		2>"$stderr_file" <<EOF; then
header = "Authorization: Bearer ${token}"
EOF
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
# Memoised for the life of the process. One update run asked GitHub for the
# same release two or three times per component -- the report's check, the
# upgrade's own comparison, and the installer again when it actually installs
# -- at roughly 700ms each, against an unauthenticated budget of 60 calls an
# hour. A release does not change mid-run, so every repeat was the first
# answer bought again, and the report and the apply could not disagree about
# what "latest" was even if the release moved between them.
#
# On disk rather than in a variable: every caller reads this function through
# `$(...)`, and the probe phase runs its checks in background subshells, so a
# cache held in memory would be written in a child and lost on the way out.
# The directory is named for the shell that owns it; entries for shells that
# are gone are swept on the way in, because nothing here runs a trap.
_github_release_cache_dir() {
	local base="${TMPDIR:-/tmp}/dotfiles-release-cache" dir peer pid
	dir="$base/$$"
	mkdir -p -- "$dir" 2>/dev/null || return 1
	for peer in "$base"/*; do
		[[ -d "$peer" ]] || continue
		pid="${peer##*/}"
		[[ "$pid" == "$$" ]] && continue
		[[ "$pid" =~ ^[0-9]+$ ]] || continue
		kill -0 "$pid" 2>/dev/null || rm -rf -- "$peer"
	done
	printf '%s\n' "$dir"
}

github_latest_release_version() {
	local repo="$1"
	local json tag dir entry

	# One path segment: the repo slug carries a slash.
	if dir="$(_github_release_cache_dir)"; then
		entry="$dir/${repo//\//__}"
		if [[ -s "$entry" ]]; then
			cat -- "$entry"
			return 0
		fi
	else
		entry=''
	fi

	json="$(github_api_release_json "$repo")" || return 1
	tag="$(printf '%s' "$json" | grep -Po '"tag_name":\s*"\K[^"]+' | head -n1)" || return 1
	[[ -n "$tag" ]] || return 1
	# Only successes are cached: a transient failure must not persuade the rest
	# of the run that the version is unknowable.
	[[ -z "$entry" ]] || printf '%s\n' "${tag#v}" >"$entry" 2>/dev/null || true
	printf '%s\n' "${tag#v}"
}
