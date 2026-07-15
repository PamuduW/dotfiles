# shellcheck shell=bash

github_token_file() {
	printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/github.env"
}

github_token_legacy_file() {
	printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agent_bootstrap/github.env"
}

github_token_is_valid() {
	local token="$1"
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
			_github_token_warn "token directory is unsafe"
			return 1
		fi
	else
		old_umask="$(umask)"
		umask 077
		if ! mkdir -p -- "$dir"; then
			umask "$old_umask"
			_github_token_warn "token directory could not be created"
			return 1
		fi
		chmod 700 -- "$dir"
		umask "$old_umask"
	fi
	if [[ -e "$file" || -L "$file" ]]; then
		if [[ ! -f "$file" || -L "$file" || "$(stat -c %a -- "$file" 2>/dev/null || true)" != 600 ]]; then
			_github_token_warn "token destination is unsafe"
			return 1
		fi
	fi
	old_umask="$(umask)"
	umask 077
	temp_file="$(mktemp "$dir/.github.env.XXXXXX")" || {
		umask "$old_umask"
		_github_token_warn "private temporary token file could not be created"
		return 1
	}
	if ! printf 'GITHUB_TOKEN=%s\n' "$token" >"$temp_file" || \
		! chmod 600 -- "$temp_file" || ! mv -f -- "$temp_file" "$file"; then
		rm -f -- "$temp_file"
		umask "$old_umask"
		_github_token_warn "token could not be saved atomically"
		return 1
	fi
	umask "$old_umask"
}

github_token_remove() {
	local file dir
	file="$(github_token_file)"
	dir="$(dirname -- "$file")"
	[[ -e "$file" || -L "$file" ]] || return 0
	if ! _github_token_private_dir "$dir" || [[ ! -f "$file" || -L "$file" ]]; then
		_github_token_warn "token destination is unsafe to remove"
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

# Compatibility for existing callers; optional failures no longer block them.
github_token_load() {
	github_token_export_if_valid
}
