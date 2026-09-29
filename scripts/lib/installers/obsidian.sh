# shellcheck shell=bash
# Obsidian desktop, installed from the official .deb and shown on the Windows
# desktop through WSLg.
#
# The repository's "latest" release is not always a desktop build (1.13.8 was
# an Android-only .apk), so the newest release that ships the amd64 .deb is
# chosen, and its SHA-256 must match the digest GitHub publishes for it.

OBSIDIAN_RELEASE_REPOSITORY="obsidianmd/obsidian-releases"
OBSIDIAN_DEB_PACKAGE="obsidian"

# The installed .deb version, or nothing.
obsidian_deb_version() {
	dpkg-query -W -f='${Status}\t${Version}\n' "$OBSIDIAN_DEB_PACKAGE" 2>/dev/null |
		awk -F'\t' '$1 == "install ok installed" { print $2 }'
}

# Obsidian that did not come from the .deb (AppImage, Snap, Flatpak, a copy).
obsidian_external_path() {
	[[ -z "$(obsidian_deb_version)" ]] || return 1
	command -v obsidian 2>/dev/null
}

obsidian_installed_version() {
	local version
	version="$(obsidian_deb_version)"
	if [[ -n "$version" ]]; then
		printf '%s\n' "$version"
	elif obsidian_external_path >/dev/null; then
		printf 'external\n'
	else
		printf 'not installed\n'
	fi
}

# WSLg on WSL, or any Linux desktop session.
obsidian_gui_available() {
	[[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" || -d /mnt/wslg ]]
}

obsidian_releases_json() {
	github_curl -fsSL \
		--connect-timeout 10 \
		--max-time 30 \
		--retry 2 \
		--retry-delay 1 \
		-H "Accept: application/vnd.github+json" \
		-H "User-Agent: dotfiles-bootstrap" \
		"https://api.github.com/repos/${OBSIDIAN_RELEASE_REPOSITORY}/releases?per_page=15"
}

# Prints version, asset name, download URL, and SHA-256 of the newest desktop
# release, one per line. Fails when none has a .deb with a published digest.
obsidian_release_metadata() {
	local json
	json="$(obsidian_releases_json)" || return 1
	python3 -c '
import json
import re
import sys

for release in json.load(sys.stdin):
    if release.get("draft") or release.get("prerelease"):
        continue
    tag = release.get("tag_name", "")
    match = re.fullmatch(r"v([0-9]+\.[0-9]+\.[0-9]+)", tag)
    if not match:
        continue
    version = match.group(1)
    name = f"obsidian_{version}_amd64.deb"
    for asset in release.get("assets", []):
        if asset.get("name") != name:
            continue
        digest = asset.get("digest") or ""
        url = asset.get("browser_download_url") or ""
        if re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest) and url.startswith("https://github.com/"):
            print(version, name, url, digest.removeprefix("sha256:").lower(), sep="\n")
            raise SystemExit(0)
        raise SystemExit(1)
raise SystemExit(1)
' <<<"$json"
}

obsidian_install_release() {
	local version="$1" asset="$2" url="$3" expected="$4"
	local tmp deb actual package package_version

	for command_name in curl sha256sum dpkg-deb apt-get; do
		command -v "$command_name" >/dev/null 2>&1 || {
			echo "  ${command_name} is required to install Obsidian." >&2
			return 1
		}
	done

	tmp="$(mktemp -d)" || return 1
	# shellcheck disable=SC2064  # Capture this invocation's temp path now for RETURN cleanup.
	trap "rm -rf -- '$tmp'; trap - RETURN" RETURN
	deb="$tmp/$asset"
	log_step "Install Obsidian ${version}"
	if ! github_curl -fsSL -o "$deb" "$url"; then
		echo "  Failed to download ${asset}." >&2
		return 1
	fi
	actual="$(sha256sum "$deb" | awk '{print $1}')"
	if [[ "$actual" != "$expected" ]]; then
		echo "  Obsidian SHA-256 verification failed; refusing to install the downloaded package." >&2
		return 1
	fi
	package="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"
	package_version="$(dpkg-deb -f "$deb" Version 2>/dev/null || true)"
	if [[ "$package" != "$OBSIDIAN_DEB_PACKAGE" || "$package_version" != "$version" ]]; then
		echo "  ${asset} is package '${package}' ${package_version}, not ${OBSIDIAN_DEB_PACKAGE} ${version}; refusing to install." >&2
		return 1
	fi
	# A path, not a name, so apt installs this verified file and resolves only
	# its dependencies from the archive.
	sudo apt-get -qq -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=600 install -y "$deb" || return $?
	log_ok "Obsidian ${version} installed; open it from the Windows Start menu or run obsidian"
}

# Installs or updates to the newest desktop release. Sets OBSIDIAN_SYNC_RESULT
# to updated or current.
obsidian_sync_release() {
	local installed
	local -a metadata=()
	OBSIDIAN_SYNC_RESULT=''
	[[ "$(uname -m)" == x86_64 ]] || {
		echo '  Obsidian publishes a .deb only for amd64; this installer supports amd64 only.' >&2
		return 1
	}
	mapfile -t metadata < <(obsidian_release_metadata)
	[[ "${#metadata[@]}" -eq 4 ]] || {
		echo '  Could not find an Obsidian desktop release with a published SHA-256 digest.' >&2
		return 1
	}
	installed="$(obsidian_deb_version)"
	if [[ -n "$installed" ]] && [[ "$(printf '%s\n%s\n' "$installed" "${metadata[0]}" | sort -V | tail -n1)" == "$installed" ]]; then
		log_skip "Obsidian already current at ${installed}"
		OBSIDIAN_SYNC_RESULT=current
		return 0
	fi
	obsidian_install_release "${metadata[@]}" || return $?
	OBSIDIAN_SYNC_RESULT=updated
}

install_obsidian() {
	local external
	if external="$(obsidian_external_path)"; then
		log_warn "Obsidian already exists outside Dotfiles at ${external}; preserving it"
		return 0
	fi
	if ! obsidian_gui_available; then
		log_skip 'No GUI display (WSLg) in this session; Obsidian not installed'
		return 0
	fi
	obsidian_sync_release
}

check_obsidian() {
	local installed latest='' available='—' action
	local -a metadata=()
	installed="$(obsidian_installed_version)"
	case "$installed" in
	'not installed') action="$UPDATE_CHECK_SKIP" ;;
	external) action="$UPDATE_CHECK_EXTERNAL" ;;
	*)
		mapfile -t metadata < <(obsidian_release_metadata 2>/dev/null)
		[[ "${#metadata[@]}" -eq 4 ]] && latest="${metadata[0]}"
		available="${latest:-—}"
		if [[ -z "$latest" ]]; then
			action="$UPDATE_CHECK_UNKNOWN"
		elif [[ "$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -n1)" != "$installed" ]]; then
			action="$UPDATE_CHECK_UPGRADE"
		else
			action="$UPDATE_CHECK_CURRENT"
		fi
		;;
	esac
	printf 'Obsidian|%s|%s|%s\n' "$installed" "$available" "$action"
	[[ "$action" == "$UPDATE_CHECK_UPGRADE" ]]
}

upgrade_obsidian() {
	if [[ -z "$(obsidian_deb_version)" ]]; then
		if obsidian_external_path >/dev/null; then
			log_skip 'Obsidian is externally managed; preserving it'
		else
			log_skip 'Obsidian not installed'
		fi
		upgrade_result_set skipped
		return 0
	fi
	obsidian_sync_release || return $?
	if [[ "$OBSIDIAN_SYNC_RESULT" == updated ]]; then
		upgrade_result_set updated
	else
		upgrade_result_set already-current
	fi
}
