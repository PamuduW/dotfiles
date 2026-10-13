# shellcheck shell=bash
# Chrome for Testing's headless shell, the latest Stable build: the browser
# Archify's browser gate drives (Agentbot installs the Archify skill; the
# stowed .bashrc points ARCHIFY_CHROME here when the shell exists).
#
# Chrome for Testing publishes no checksum, so unlike the release CLIs this
# download is trusted on HTTPS from Google's own bucket alone. What is checked:
# the archive's URL and version come from Google's version list, every member
# stays inside the build directory, and the unpacked shell reports that
# version before it replaces anything.

if ! declare -F chrome_headless_command >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi

CHROME_HEADLESS_VERSIONS_URL='https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json'
CHROME_HEADLESS_LABEL='Chrome headless shell'

chrome_headless_platform() {
	[[ "$(uname -s)" == Linux ]] || return 1
	case "$(uname -m)" in
	x86_64 | amd64) printf '%s\n' linux64 ;;
	aarch64 | arm64) printf '%s\n' linux-arm64 ;;
	*) return 1 ;;
	esac
}

chrome_headless_versions_json() {
	curl -fsSL --max-time 30 "$CHROME_HEADLESS_VERSIONS_URL"
}

# Prints the latest Stable version and its download URL, one per line. Fails
# when the list has no build for this platform, or names one anywhere but
# Chrome for Testing's own bucket.
chrome_headless_latest_metadata() {
	local platform json
	platform="$(chrome_headless_platform)" || return 1
	json="$(chrome_headless_versions_json)" || return 1
	python3 -c '
import json
import re
import sys

platform = sys.argv[1]
stable = json.load(sys.stdin).get("channels", {}).get("Stable", {})
version = stable.get("version", "")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit(1)
expected = (
    "https://storage.googleapis.com/chrome-for-testing-public/"
    f"{version}/{platform}/chrome-headless-shell-{platform}.zip"
)
for download in stable.get("downloads", {}).get("chrome-headless-shell", []):
    if download.get("platform") == platform and download.get("url") == expected:
        print(version)
        print(expected)
        raise SystemExit(0)
raise SystemExit(1)
' "$platform" <<<"$json"
}

chrome_headless_install_release() {
	local version="$1" url="$2"
	local platform top tmp archive member build root link stamp previous command_name
	local -a members=()
	platform="$(chrome_headless_platform)" || {
		echo "  ${CHROME_HEADLESS_LABEL} supports only Linux amd64/arm64 in this installer." >&2
		return 1
	}
	top="chrome-headless-shell-${platform}"
	root="$(chrome_headless_root)"
	link="$(chrome_headless_install_path)"
	stamp="$(chrome_headless_management_stamp)"

	for command_name in curl unzip install; do
		command -v "$command_name" >/dev/null 2>&1 || {
			echo "  ${command_name} is required to install ${CHROME_HEADLESS_LABEL}." >&2
			return 1
		}
	done

	tmp="$(mktemp -d)" || return 1
	trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
	archive="$tmp/${top}.zip"
	log_step "Install ${CHROME_HEADLESS_LABEL} ${version}"
	if ! curl -fsSL -o "$archive" "$url"; then
		echo "  Failed to download ${top}.zip." >&2
		return 1
	fi

	mapfile -t members < <(unzip -Z1 "$archive" 2>/dev/null)
	if [[ "${#members[@]}" -eq 0 ]]; then
		echo "  ${CHROME_HEADLESS_LABEL} archive could not be listed; refusing extraction." >&2
		return 1
	fi
	for member in "${members[@]}"; do
		case "$member" in
		/* | ../* | */../* | */..)
			echo "  ${CHROME_HEADLESS_LABEL} archive member '${member}' escapes the extraction directory; refusing extraction." >&2
			return 1
			;;
		"$top"/*) ;;
		*)
			echo "  ${CHROME_HEADLESS_LABEL} archive member '${member}' is outside ${top}/; refusing extraction." >&2
			return 1
			;;
		esac
	done
	unzip -q "$archive" -d "$tmp/unpacked" >/dev/null || return $?
	build="$tmp/unpacked/$top"
	[[ -f "$build/chrome-headless-shell" && ! -L "$build/chrome-headless-shell" ]] || {
		echo "  ${CHROME_HEADLESS_LABEL} archive did not contain a regular chrome-headless-shell." >&2
		return 1
	}
	chmod 0755 "$build/chrome-headless-shell"
	if [[ "$("$build/chrome-headless-shell" --version 2>/dev/null | head -n1 || true)" != *"$version"* ]]; then
		echo "  Downloaded ${CHROME_HEADLESS_LABEL} did not report ${version}." >&2
		if command -v ldd >/dev/null 2>&1; then
			ldd "$build/chrome-headless-shell" 2>/dev/null | awk '/not found/ {print "  missing library: " $1}' >&2
		fi
		return 1
	fi

	install -d -m 0755 "$(dirname -- "$root")" "$(dirname -- "$link")" "$(dirname -- "$stamp")"
	previous="${root}.previous.$$"
	if [[ -e "$root" ]]; then
		mv -- "$root" "$previous" || return $?
	fi
	if ! mv -- "$build" "$root"; then
		[[ -e "$previous" ]] && mv -- "$previous" "$root"
		return 1
	fi
	ln -sfn -- "$root/chrome-headless-shell" "$link" || return $?
	printf '%s\n' "$version" >"$tmp/stamp"
	install -m 0644 "$tmp/stamp" "$stamp" || return $?
	[[ -e "$previous" ]] && rm -rf -- "$previous"
	rm -rf -- "$tmp"
	trap - RETURN
	log_ok "${CHROME_HEADLESS_LABEL} ${version} installed at ${link}"
}

# Installs the latest Stable build unless the one installed is already as new.
# With force, reinstalls it even then.
chrome_headless_sync_latest() {
	local force="${1:-0}" installed latest
	local -a metadata=()
	mapfile -t metadata < <(chrome_headless_latest_metadata)
	[[ "${#metadata[@]}" -eq 2 ]] || {
		echo "  Could not read the latest ${CHROME_HEADLESS_LABEL} build; preserving the installed one." >&2
		return 1
	}
	latest="${metadata[0]}"
	installed="$(chrome_headless_installed_tag 2>/dev/null || true)"
	if [[ "$force" != 1 && -n "$installed" ]] &&
		[[ "$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -n1)" == "$installed" ]]; then
		log_skip "${CHROME_HEADLESS_LABEL} already current at ${installed}"
		return 0
	fi
	chrome_headless_install_release "$latest" "${metadata[1]}"
}

install_chrome_headless() {
	local existing
	if existing="$(chrome_headless_command 2>/dev/null)"; then
		# An installation Dotfiles does not own is never touched, forced or not.
		if ! chrome_headless_is_dotfiles_owned; then
			log_warn "${CHROME_HEADLESS_LABEL} already exists outside Dotfiles ownership at ${existing}; preserving it"
			return 0
		fi
		if skip_unless_forced "${CHROME_HEADLESS_LABEL} already installed"; then
			return 0
		fi
		chrome_headless_sync_latest 1
		return
	fi
	chrome_headless_sync_latest
}

check_chrome_headless() {
	local installed latest action available='—' upgradable=0
	local -a metadata=()
	installed="$(chrome_headless_installed_version)"
	if [[ "$installed" == 'not installed' ]]; then
		action=skip
	elif ! chrome_headless_is_dotfiles_owned; then
		action=external
	else
		mapfile -t metadata < <(chrome_headless_latest_metadata 2>/dev/null)
		if [[ "${#metadata[@]}" -eq 2 ]]; then
			latest="${metadata[0]}"
			available="$latest"
			if [[ "$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -n1)" != "$installed" ]]; then
				action=upgrade
				upgradable=1
			else
				action=current
			fi
		else
			action=unknown
		fi
	fi
	printf '%s|%s|%s|%s\n' "$CHROME_HEADLESS_LABEL" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_chrome_headless() {
	local before after
	if ! chrome_headless_command >/dev/null 2>&1; then
		log_skip "${CHROME_HEADLESS_LABEL} not installed"
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	if ! chrome_headless_is_dotfiles_owned; then
		log_skip "${CHROME_HEADLESS_LABEL} is externally managed; preserving it"
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	before="$(chrome_headless_installed_tag 2>/dev/null || true)"
	chrome_headless_sync_latest || return $?
	after="$(chrome_headless_installed_tag 2>/dev/null || true)"
	if declare -F upgrade_result_set >/dev/null 2>&1; then
		if [[ "$after" != "$before" ]]; then
			upgrade_result_set updated
		else
			upgrade_result_set already-current
		fi
	fi
}
