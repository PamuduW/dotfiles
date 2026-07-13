# shellcheck shell=bash
# Local GitHub token storage for agent_bootstrap commands.

github_token_file() {
	printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agent_bootstrap/github.env"
}

github_token_is_valid() {
	local token="$1"
	[[ ${#token} -ge 20 && "$token" =~ ^[A-Za-z0-9_]+$ ]]
}

github_token_write() {
	local token="$1" file dir temp_file
	github_token_is_valid "$token" || return 1

	file="$(github_token_file)"
	dir="$(dirname "$file")"
	umask 077
	mkdir -p "$dir"
	chmod 700 "$dir"
	temp_file="$(mktemp "$dir/.github.env.XXXXXX")" || return 1
	printf 'GITHUB_TOKEN=%s\n' "$token" >"$temp_file"
	chmod 600 "$temp_file"
	mv -f "$temp_file" "$file"
}

github_token_remove() {
	rm -f -- "$(github_token_file)"
}

github_token_load() {
	local file line token mode
	[[ -n "${GITHUB_TOKEN:-}" ]] && return 0

	file="$(github_token_file)"
	[[ -f "$file" ]] || return 0
	mode="$(stat -c %a "$file" 2>/dev/null || true)"
	if [[ "$mode" != "600" ]]; then
		echo "Error: GitHub token file must have mode 600: $file" >&2
		return 1
	fi
	IFS= read -r line <"$file" || true
	[[ "$line" == GITHUB_TOKEN=* ]] || {
		echo "Error: invalid GitHub token file: $file" >&2
		return 1
	}
	token="${line#GITHUB_TOKEN=}"
	github_token_is_valid "$token" || {
		echo "Error: invalid GitHub token in $file" >&2
		return 1
	}
	export GITHUB_TOKEN="$token"
}
