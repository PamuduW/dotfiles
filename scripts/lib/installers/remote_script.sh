# shellcheck shell=bash

if [[ "${_DOTFILES_REMOTE_SCRIPT_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_REMOTE_SCRIPT_LOADED=1

# Download a vendor installer completely, validate that it is parseable shell,
# then execute the local copy. Environment assignments may follow the label.
run_vendor_shell_installer() {
	local url="$1" label="$2" tmp_dir installer rc=0
	shift 2

	[[ "$url" == https://* ]] || {
		printf '  Refusing non-HTTPS installer URL for %s: %s\n' "$label" "$url" >&2
		return 1
	}
	command -v curl >/dev/null 2>&1 || {
		printf '  curl is required to install %s.\n' "$label" >&2
		return 1
	}

	tmp_dir="$(mktemp -d)" || return 1
	installer="$tmp_dir/installer.sh"
	if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$installer" "$url"; then
		printf '  Failed to download the %s installer.\n' "$label" >&2
		rm -rf -- "$tmp_dir"
		return 1
	fi
	if [[ ! -s "$installer" ]] || ! bash -n "$installer"; then
		printf '  The downloaded %s installer is empty or invalid shell.\n' "$label" >&2
		rm -rf -- "$tmp_dir"
		return 1
	fi

	env "$@" bash "$installer" || rc=$?
	rm -rf -- "$tmp_dir"
	return "$rc"
}
