# shellcheck shell=bash

github_token_file() {
	printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/github.env"
}

github_token_legacy_file() {
	printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agent_bootstrap/github.env"
}

# Whether GitHub itself accepts the credential, as opposed to whether it looks
# like one. github_token_is_valid checks shape -- length and character class --
# so a mistyped, expired or revoked token passed it and was saved, and the
# operator found out later when a rate-limited call failed instead.
#
# /user answers exactly the question being asked: 200 means GitHub accepts this
# credential, 401 means it does not. It needs no scopes -- a classic token with
# none set still reads it -- and no body is parsed, so nothing sensitive is
# read back or logged.
#
# The token goes in through curl's private stdin config, never its argv, the
# same discipline github_curl uses: an argv is world-readable in /proc.
#
#   0  accepted by GitHub
#   1  refused by GitHub
#   2  could not ask -- no curl, no network, or an answer that decides nothing
GITHUB_TOKEN_VERIFY_TIMEOUT="${GITHUB_TOKEN_VERIFY_TIMEOUT:-10}"

# curl carrying an explicit token, with the token in its private stdin config
# and never in its argv, where /proc would publish it to every user on the
# machine. github_curl wraps this with the saved token; verification needs the
# same guarantee for a token that is not saved yet, so the discipline lives
# here, once, in the tree both products share.
#
# Stderr is filtered rather than discarded: curl names the URL it failed on,
# which is worth keeping, and a redirect or a verbose run can echo the header.
github_token_curl() (
	local token="$1"
	shift
	local rc=0 stderr_file old_umask content=''
	old_umask="$(umask)"
	umask 077
	stderr_file="$(mktemp "${TMPDIR:-/tmp}/github-token-curl.stderr.XXXXXX")" || {
		umask "$old_umask"
		return 1
	}
	umask "$old_umask"
	trap 'rm -f -- "$stderr_file"' EXIT

	curl --config - "$@" 2>"$stderr_file" <<EOF || rc=$?
header = "Authorization: Bearer ${token}"
EOF
	IFS= read -r -d '' content <"$stderr_file" || true
	[[ -z "$content" ]] || printf '%s' "${content//"$token"/[redacted]}" >&2
	rm -f -- "$stderr_file"
	trap - EXIT
	return "$rc"
)

github_token_verify() (
	local token="$1" status='' rc=0 url
	# Inside the function that uses it: a sensitive URL at file scope sits
	# outside any boundary, which is exactly what the consumer scanner reads it
	# as, and it is right to.
	url="${GITHUB_TOKEN_VERIFY_URL:-https://api.github.com/user}"
	command -v curl >/dev/null 2>&1 || return 2
	status="$(
		github_token_curl "$token" \
			--silent --output /dev/null --write-out '%{http_code}' \
			--max-time "$GITHUB_TOKEN_VERIFY_TIMEOUT" --proto '=https' --tlsv1.2 \
			--header 'Accept: application/vnd.github+json' \
			--header 'User-Agent: dotfiles-token-check' \
			"$url" 2>/dev/null
	)" || rc=$?
	((rc == 0)) || return 2
	case "$status" in
	200) return 0 ;;
	401) return 1 ;;
	# 403 is a secondary rate limit or a blocked agent, not a verdict on the
	# credential; anything else is GitHub having a bad day. Neither is grounds
	# for refusing a token the operator may well have typed correctly.
	*) return 2 ;;
	esac
)

github_token_is_valid() {
	local token="$1"
	if [[ "$token" == ghs_* ]]; then
		[[ "$token" =~ ^ghs_[A-Za-z0-9._-]{36,}$ ]]
		return
	fi
	[[ ${#token} -ge 20 && "$token" =~ ^[A-Za-z0-9_]+$ ]]
}

_GITHUB_TOKEN_WARNING_SCOPE_DEPTH=0
declare -gA _GITHUB_TOKEN_WARNED_KEYS=()

_github_token_warning_scope_begin() {
	if ((_GITHUB_TOKEN_WARNING_SCOPE_DEPTH == 0)); then
		_GITHUB_TOKEN_WARNED_KEYS=()
	fi
	_GITHUB_TOKEN_WARNING_SCOPE_DEPTH=$((_GITHUB_TOKEN_WARNING_SCOPE_DEPTH + 1))
}

_github_token_warning_scope_end() {
	if ((_GITHUB_TOKEN_WARNING_SCOPE_DEPTH > 0)); then
		_GITHUB_TOKEN_WARNING_SCOPE_DEPTH=$((_GITHUB_TOKEN_WARNING_SCOPE_DEPTH - 1))
	fi
}

_github_token_warn() {
	local message="$1" key="${2:-$1}"
	if ((_GITHUB_TOKEN_WARNING_SCOPE_DEPTH > 0)); then
		[[ -z "${_GITHUB_TOKEN_WARNED_KEYS[$key]+x}" ]] || return 0
		_GITHUB_TOKEN_WARNED_KEYS["$key"]=1
	fi
	printf 'Warning: %s; continuing anonymously.\n' "$message" >&2
}

_github_token_private_dir() {
	local dir="$1" mode
	[[ -d "$dir" && ! -L "$dir" ]] || return 1
	mode="$(stat -c %a -- "$dir" 2>/dev/null || true)"
	[[ "$mode" == 700 ]]
}

_github_token_read_private_file() {
	local file="$1" out_var="$2" label="$3"
	local dir mode line='' extra='' fd
	printf -v "$out_var" '%s' ''
	[[ -e "$file" || -L "$file" ]] || return 0
	dir="$(dirname -- "$file")"
	if ! _github_token_private_dir "$dir" || [[ ! -f "$file" || -L "$file" ]]; then
		_github_token_warn "$label has unsafe path or directory permissions" "$file"
		return 0
	fi
	mode="$(stat -c %a -- "$file" 2>/dev/null || true)"
	if [[ "$mode" != 600 ]]; then
		_github_token_warn "$label must have mode 600" "$file"
		return 0
	fi
	exec {fd}<"$file" || {
		_github_token_warn "$label could not be read" "$file"
		return 0
	}
	if ! IFS= read -r line <&$fd; then
		exec {fd}<&-
		_github_token_warn "$label must contain one newline-terminated assignment" "$file"
		return 0
	fi
	if IFS= read -r extra <&$fd || [[ -n "$extra" ]]; then
		exec {fd}<&-
		_github_token_warn "$label must contain exactly one assignment" "$file"
		return 0
	fi
	exec {fd}<&-
	if [[ "$line" != GITHUB_TOKEN=* ]]; then
		_github_token_warn "$label has an invalid key" "$file"
		return 0
	fi
	line="${line#GITHUB_TOKEN=}"
	if ! github_token_is_valid "$line"; then
		_github_token_warn "$label contains an invalid token" "$file"
		return 0
	fi
	printf -v "$out_var" '%s' "$line"
}

github_token_read() {
	local out_var="${1:?output variable is required}"
	_github_token_read_private_file "$(github_token_file)" "$out_var" "saved GitHub token"
}

github_token_write() {
	local token="$1" file dir temp_file='' old_umask
	if ! github_token_is_valid "$token"; then
		_github_token_warn "token value is invalid"
		return 1
	fi
	file="$(github_token_file)"
	dir="$(dirname -- "$file")"
	if [[ -e "$dir" || -L "$dir" ]]; then
		if ! _github_token_private_dir "$dir"; then
			_github_token_warn "token directory is unsafe" "$file"
			return 1
		fi
	else
		old_umask="$(umask)"
		umask 077
		if ! mkdir -p -- "$dir"; then
			umask "$old_umask"
			_github_token_warn "token directory could not be created" "$file"
			return 1
		fi
		chmod 700 -- "$dir"
		umask "$old_umask"
	fi
	if [[ -e "$file" || -L "$file" ]]; then
		if [[ ! -f "$file" || -L "$file" || "$(stat -c %a -- "$file" 2>/dev/null || true)" != 600 ]]; then
			_github_token_warn "token destination is unsafe" "$file"
			return 1
		fi
	fi
	old_umask="$(umask)"
	umask 077
	temp_file="$(mktemp "$dir/.github.env.XXXXXX")" || {
		umask "$old_umask"
		_github_token_warn "private temporary token file could not be created" "$file"
		return 1
	}
	if ! printf 'GITHUB_TOKEN=%s\n' "$token" >"$temp_file" ||
		! chmod 600 -- "$temp_file" || ! mv -f -- "$temp_file" "$file"; then
		rm -f -- "$temp_file"
		umask "$old_umask"
		_github_token_warn "token could not be saved atomically" "$file"
		return 1
	fi
	umask "$old_umask"
}

github_token_remove() {
	local file dir
	file="$(github_token_file)"
	dir="$(dirname -- "$file")"
	[[ -e "$file" || -L "$file" ]] || return 0
	# A symlink, or a file in a directory anyone else can write, is not ours to
	# delete: following it would remove whatever it points at. Refuse, and say
	# what to look at -- the caller shows this to an operator who otherwise has
	# a dead end where the reason should be.
	if ! _github_token_private_dir "$dir" || [[ ! -f "$file" || -L "$file" ]]; then
		_github_token_warn "token destination is unsafe to remove" "$file"
		# shellcheck disable=SC2034  # Read by the caller that reports the refusal.
		GITHUB_TOKEN_REMOVE_REASON="$file is a symlink or sits in a directory that is not private; remove it yourself"
		return 1
	fi
	rm -f -- "$file"
}

github_token_fingerprint() {
	local token="$1" digest
	github_token_is_valid "$token" || return 1
	digest="$(printf '%s' "$token" | sha256sum | awk '{print substr($1,1,8)}')"
	printf '…%s (sha256:%s)\n' "${token: -4}" "$digest"
}

_github_token_migrate_legacy_impl() {
	local legacy target legacy_token='' target_token=''
	legacy="$(github_token_legacy_file)"
	target="$(github_token_file)"
	[[ -e "$legacy" || -L "$legacy" ]] || return 0
	_github_token_read_private_file "$legacy" legacy_token "legacy GitHub token" || return 0
	[[ -n "$legacy_token" ]] || return 0
	if [[ -e "$target" || -L "$target" ]]; then
		_github_token_read_private_file "$target" target_token "saved GitHub token" || return 0
		if [[ -n "$target_token" && "$target_token" == "$legacy_token" ]]; then
			rm -f -- "$legacy"
			return 0
		fi
		_github_token_warn "legacy and active GitHub token files conflict" "$target"
		return 0
	fi
	if github_token_write "$legacy_token"; then
		rm -f -- "$legacy"
	fi
}

github_token_migrate_legacy() {
	local rc=0
	_github_token_warning_scope_begin
	_github_token_migrate_legacy_impl || rc=$?
	_github_token_warning_scope_end
	return "$rc"
}

github_token_export_if_valid() {
	local token="${GITHUB_TOKEN:-}"
	_github_token_warning_scope_begin
	if [[ -n "$token" ]]; then
		if github_token_is_valid "$token"; then
			export GITHUB_TOKEN
			_github_token_warning_scope_end
			return 0
		fi
		_github_token_warn "GITHUB_TOKEN from the environment is invalid"
		unset GITHUB_TOKEN
	fi
	github_token_migrate_legacy
	github_token_read token
	if [[ -n "$token" ]]; then
		GITHUB_TOKEN="$token"
		export GITHUB_TOKEN
	fi
	_github_token_warning_scope_end
	return 0
}
