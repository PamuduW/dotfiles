# shellcheck shell=bash

# The vendor one-liner (antigravity.google/cli/install.sh) reads this manifest,
# then runs `agy install`, which appends a PATH export to ~/.bashrc and
# ~/.profile. ~/.bashrc is a Stow link into this repository, so that write
# lands in the checkout. The installer below does the download and digest
# check itself and never runs `agy install`.
ANTIGRAVITY_MANIFEST_BASE_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"
ANTIGRAVITY_DOWNLOAD_PREFIX="https://storage.googleapis.com/antigravity-public/"

if ! declare -F tool_resolve >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/tool_resolve.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tool_resolve.sh"
fi

antigravity_curl() {
	# --compressed: the host gzip-encodes responses even when not asked to.
	curl -fsSL --compressed --proto '=https' --tlsv1.2 --connect-timeout 10 "$@"
}

antigravity_install_path() {
	printf '%s\n' "$HOME/.local/bin/agy"
}

antigravity_platform() {
	local arch
	[[ "$(uname -s)" == Linux ]] || return 1
	case "$(uname -m)" in
	x86_64 | amd64) arch=amd64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*) return 1 ;;
	esac
	if [[ -f /lib/libc.musl-x86_64.so.1 || -f /lib/libc.musl-aarch64.so.1 ]] ||
		ldd /bin/ls 2>&1 | grep -q musl; then
		printf 'linux_%s_musl\n' "$arch"
	else
		printf 'linux_%s\n' "$arch"
	fi
}

antigravity_installed_version() {
	local binary raw
	binary="$(tool_resolve agy)" || {
		echo 'not installed'
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$raw" | head -n1 || echo installed
}

# Print version, url and sha512 on three lines, or return 1 when the manifest
# cannot be read or does not look like a release we would install.
antigravity_manifest_metadata() {
	local platform="$1" json
	# Bounded like the GitHub lookups: the update report waits on this. The
	# archive download is not, because it is a few hundred megabytes.
	json="$(antigravity_curl --max-time 30 "${ANTIGRAVITY_MANIFEST_BASE_URL}/${platform}.json")" || return 1
	python3 -c '
import json
import re
import sys

prefix = sys.argv[1]
try:
    manifest = json.load(sys.stdin)
except ValueError:
    raise SystemExit(1)
version = manifest.get("version", "")
url = manifest.get("url", "")
sha512 = manifest.get("sha512", "")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit(1)
if not url.startswith(prefix) or not url.endswith(".tar.gz"):
    raise SystemExit(1)
if not re.fullmatch(r"[0-9a-fA-F]{128}", sha512):
    raise SystemExit(1)
print(version)
print(url)
print(sha512.lower())
' "$ANTIGRAVITY_DOWNLOAD_PREFIX" <<<"$json"
}

antigravity_install_release() {
	local version="$1" url="$2" expected="$3"
	local tmp archive actual install_path candidate command_name
	install_path="$(antigravity_install_path)"

	for command_name in curl tar sha512sum install; do
		command -v "$command_name" >/dev/null 2>&1 || {
			echo "  ${command_name} is required to install the Antigravity CLI." >&2
			return 1
		}
	done

	tmp="$(mktemp -d)" || return 1
	trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
	archive="$tmp/agy.tar.gz"
	log_step "Install Antigravity CLI ${version}"
	if ! antigravity_curl -o "$archive" "$url"; then
		echo '  Failed to download the Antigravity CLI archive.' >&2
		return 1
	fi
	actual="$(sha512sum "$archive" | awk '{print $1}')"
	if [[ "$actual" != "$expected" ]]; then
		echo '  Antigravity CLI SHA-512 verification failed; refusing to install the downloaded binary.' >&2
		return 1
	fi

	# Same escape check as Boost: only `antigravity` is extracted, so extra
	# members are inert, but none may point outside the extraction directory.
	local -a members=()
	local member has_binary=0
	mapfile -t members < <(tar -tzf "$archive")
	if [[ "${#members[@]}" -eq 0 ]]; then
		echo '  Antigravity CLI archive could not be listed; refusing extraction.' >&2
		return 1
	fi
	for member in "${members[@]}"; do
		case "$member" in
		antigravity) has_binary=1 ;;
		/* | ../* | */../* | */..)
			echo "  Antigravity CLI archive member '${member}' escapes the extraction directory; refusing extraction." >&2
			return 1
			;;
		esac
	done
	if [[ "$has_binary" -ne 1 ]]; then
		echo '  Antigravity CLI archive does not contain a top-level antigravity binary; refusing extraction.' >&2
		return 1
	fi
	tar -xzf "$archive" -C "$tmp" antigravity || return $?
	[[ -f "$tmp/antigravity" && ! -L "$tmp/antigravity" ]] || {
		echo '  Antigravity CLI archive did not contain a regular antigravity binary.' >&2
		return 1
	}

	install -d -m 0755 "$(dirname -- "$install_path")"
	candidate="$(dirname -- "$install_path")/.agy.candidate.$$"
	install -m 0755 "$tmp/antigravity" "$candidate" || return $?
	if [[ "$("$candidate" --version 2>/dev/null | head -n1 || true)" != *"$version"* ]]; then
		rm -f -- "$candidate"
		echo "  Downloaded Antigravity CLI did not report ${version}." >&2
		return 1
	fi
	mv -f -- "$candidate" "$install_path" || return $?
	rm -rf -- "$tmp"
	trap - RETURN
	log_ok "Antigravity CLI ${version} installed at ${install_path}"
}

install_antigravity_cli() {
	local platform
	local -a metadata=()
	if tool_resolve agy >/dev/null 2>&1 &&
		skip_unless_forced 'Antigravity CLI already installed'; then
		return 0
	fi
	platform="$(antigravity_platform)" || {
		echo '  The Antigravity CLI installer supports only Linux amd64/arm64.' >&2
		return 1
	}
	mapfile -t metadata < <(antigravity_manifest_metadata "$platform")
	[[ "${#metadata[@]}" -eq 3 ]] || {
		echo '  Could not read a valid Antigravity CLI release manifest.' >&2
		return 1
	}
	antigravity_install_release "${metadata[0]}" "${metadata[1]}" "${metadata[2]}"
}

antigravity_available_version() {
	local platform
	local -a metadata=()
	platform="$(antigravity_platform)" || return 1
	mapfile -t metadata < <(antigravity_manifest_metadata "$platform")
	[[ "${#metadata[@]}" -eq 3 ]] || return 1
	printf '%s\n' "${metadata[0]}"
}

check_antigravity_cli() {
	local installed available action upgradable=0
	installed="$(antigravity_installed_version)"
	if [[ "$installed" == 'not installed' ]]; then
		available='—'
		action=skip
	else
		available="$(antigravity_available_version || true)"
		if [[ -z "$available" || ! "$installed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			available="${available:-—}"
			action=unknown
		elif [[ "$installed" != "$available" &&
			"$(printf '%s\n%s\n' "$installed" "$available" | sort -V | tail -n1)" == "$available" ]]; then
			action=upgrade
			upgradable=1
		else
			action=current
		fi
	fi
	printf 'Antigravity CLI|%s|%s|%s\n' "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

# The CLI also updates itself in the background; `agy update` is the same
# updater run on demand.
upgrade_antigravity_cli() {
	local executable before
	executable="$(tool_resolve agy)" || executable=''
	if [[ -z "$executable" ]]; then
		log_skip 'Antigravity CLI not installed'
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	before="$(antigravity_installed_version)"
	_run_quiet_command 'agy update' "$executable" update || return $?
	_upgrade_report_version_change 'Antigravity CLI' "$before" "$(antigravity_installed_version)"
}
