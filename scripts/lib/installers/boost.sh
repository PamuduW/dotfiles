# shellcheck shell=bash

BOOST_RELEASE_REPOSITORY="jfrog/boost"

boost_install_path() {
	printf '%s\n' "$HOME/.local/bin/boost"
}

boost_management_stamp() {
	printf '%s\n' "$HOME/.local/share/dotfiles/boost-cli.version"
}

boost_command() {
	if command -v boost >/dev/null 2>&1; then
		command -v boost
	elif [[ -x "$HOME/.local/bin/boost" ]]; then
		printf '%s\n' "$HOME/.local/bin/boost"
	else
		return 1
	fi
}

boost_installed_version() {
	local boost_cmd version
	boost_cmd="$(boost_command 2>/dev/null)" || {
		printf '%s\n' 'not installed'
		return 0
	}
	version="$("$boost_cmd" version 2>/dev/null | head -n1 || true)"
	printf '%s\n' "${version:-installed}"
}

boost_cli_is_dotfiles_owned() {
	local command_path install_path stamp
	command_path="$(boost_command 2>/dev/null)" || return 1
	install_path="$(boost_install_path)"
	stamp="$(boost_management_stamp)"
	[[ "$command_path" == "$install_path" ]] || return 1
	[[ -f "$stamp" && ! -L "$stamp" ]] || return 1
	[[ "$(<"$stamp")" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]
}

boost_installed_tag() {
	local version
	version="$(boost_installed_version)"
	version="$(grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?' <<<"$version" | head -n1)"
	[[ -n "$version" ]] || return 1
	[[ "$version" == v* ]] || version="v$version"
	printf '%s\n' "$version"
}

boost_platform_arch() {
	[[ "$(uname -s)" == Linux ]] || return 1
	case "$(uname -m)" in
	x86_64 | amd64) printf '%s\n' amd64 ;;
	aarch64 | arm64) printf '%s\n' arm64 ;;
	*) return 1 ;;
	esac
}

check_boost_cli() {
	local installed action
	installed="$(boost_installed_version)"
	if [[ "$installed" == 'not installed' ]]; then
		action=skip
	elif boost_cli_is_dotfiles_owned; then
		action=unknown
	else
		action=external
	fi
	printf 'Boost CLI|%s|—|%s\n' "$installed" "$action"
}

boost_install_release() {
	local release_tag="$1" expected="$2"
	local arch asset archive_url tmp archive actual install_path stamp candidate
	install_path="$(boost_install_path)"
	stamp="$(boost_management_stamp)"

	arch="$(boost_platform_arch)" || {
		echo "  Boost ${release_tag} supports only Linux amd64/arm64 in this installer." >&2
		return 1
	}
	asset="boost-linux-${arch}.tar.gz"
	archive_url="https://github.com/${BOOST_RELEASE_REPOSITORY}/releases/download/${release_tag}/${asset}"

	for command_name in curl tar sha256sum install; do
		command -v "$command_name" >/dev/null 2>&1 || {
			echo "  ${command_name} is required to install Boost." >&2
			return 1
		}
	done

	tmp="$(mktemp -d)" || return 1
	trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
	archive="$tmp/$asset"
	log_step "Install Boost CLI ${release_tag}"
	if ! github_curl -fsSL -o "$archive" "$archive_url"; then
		echo "  Failed to download ${asset}." >&2
		return 1
	fi
	actual="$(sha256sum "$archive" | awk '{print $1}')"
	if [[ "$actual" != "$expected" ]]; then
		echo "  Boost SHA-256 verification failed; refusing to install the downloaded binary." >&2
		return 1
	fi

	# Inspect the member list before extracting anything. The check is on
	# escape, not on an exact manifest: upstream ships a release every day or
	# two, so demanding an exact ordered member list would turn one added
	# LICENSE file into a hard install failure. Only `boost` is extracted
	# below, so extra members are inert.
	local -a members=()
	mapfile -t members < <(tar -tzf "$archive")
	if [[ "${#members[@]}" -eq 0 ]]; then
		echo "  Boost archive could not be listed; refusing extraction." >&2
		return 1
	fi
	local member has_boost=0
	for member in "${members[@]}"; do
		case "$member" in
		boost) has_boost=1 ;;
		/* | ../* | */../* | */..)
			echo "  Boost archive member '${member}' escapes the extraction directory; refusing extraction." >&2
			return 1
			;;
		esac
	done
	if [[ "$has_boost" -ne 1 ]]; then
		echo "  Boost archive does not contain a top-level boost binary; refusing extraction." >&2
		return 1
	fi
	tar -xzf "$archive" -C "$tmp" boost || return $?
	[[ -f "$tmp/boost" && ! -L "$tmp/boost" ]] || {
		echo "  Boost archive did not contain a regular boost binary." >&2
		return 1
	}

	install -d -m 0755 "$(dirname -- "$install_path")"
	candidate="$(dirname -- "$install_path")/.boost.candidate.$$"
	install -m 0755 "$tmp/boost" "$candidate" || return $?
	if [[ "$("$candidate" version 2>/dev/null | head -n1 || true)" != *"${release_tag#v}"* ]]; then
		rm -f -- "$candidate"
		echo "  Downloaded Boost binary did not report ${release_tag}." >&2
		return 1
	fi
	mv -f -- "$candidate" "$install_path" || return $?
	install -d -m 0755 "$(dirname -- "$stamp")"
	printf '%s\n' "$release_tag" >"$tmp/boost-cli.version"
	install -m 0644 "$tmp/boost-cli.version" "$stamp" || return $?
	rm -rf -- "$tmp"
	trap - RETURN
	log_ok "Boost CLI ${release_tag} installed at ${install_path}"
}

install_boost_cli() {
	local existing
	if existing="$(boost_command 2>/dev/null)" && ! boost_cli_is_dotfiles_owned; then
		log_warn "Boost CLI already exists outside Dotfiles ownership at ${existing}; preserving it"
		return 0
	fi
	boost_sync_latest_release
}

boost_latest_release_metadata() {
	local arch="$1" json asset
	asset="boost-linux-${arch}.tar.gz"
	json="$(github_api_release_json "$BOOST_RELEASE_REPOSITORY")" || return 1
	python3 -c '
import json
import re
import sys

asset_name = sys.argv[1]
release = json.load(sys.stdin)
tag = release.get("tag_name", "")
if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:[+-][0-9A-Za-z.-]+)?", tag):
    raise SystemExit(1)
for asset in release.get("assets", []):
    if asset.get("name") != asset_name:
        continue
    digest = asset.get("digest", "")
    if re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
        print(tag)
        print(digest.removeprefix("sha256:").lower())
        raise SystemExit(0)
raise SystemExit(1)
' "$asset" <<<"$json"
}

boost_sync_latest_release() {
	local arch installed_tag latest_tag latest_digest
	local -a metadata=()
	arch="$(boost_platform_arch)" || {
		echo '  Boost supports only Linux amd64/arm64 in this installer.' >&2
		return 1
	}
	mapfile -t metadata < <(boost_latest_release_metadata "$arch")
	[[ "${#metadata[@]}" -eq 2 ]] || {
		echo '  Could not verify the latest Boost release and published digest; preserving the installed binary.' >&2
		return 1
	}
	latest_tag="${metadata[0]}"
	latest_digest="${metadata[1]}"
	installed_tag="$(boost_installed_tag 2>/dev/null || true)"
	if [[ -n "$installed_tag" ]] && [[ "$(printf '%s\n%s\n' "${installed_tag#v}" "${latest_tag#v}" | sort -V | tail -n1)" == "${installed_tag#v}" ]]; then
		printf '  Boost CLI is already current at %s\n' "$installed_tag"
		return 0
	fi
	boost_install_release "$latest_tag" "$latest_digest"
}

upgrade_boost_cli() {
	if ! boost_command >/dev/null 2>&1; then
		printf '%s\n' '  Boost CLI not installed, skipping'
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	if ! boost_cli_is_dotfiles_owned; then
		printf '%s\n' '  Boost CLI is externally managed, preserving it'
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	boost_sync_latest_release || return $?
	if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set checked-no-change; fi
}
