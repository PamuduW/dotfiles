# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"
# Kubeconform, TFLint, zizmor, Vale, yt-dlp, Trivy and Infracost: the latest
# GitHub release of each, verified
# against the SHA-256 digest GitHub publishes for the asset, installed to
# ~/.local/bin. The rows are in RELEASE_CLI_TOOLS (managed_tool_state.sh).
#
# Dotfiles owns the executable and nothing else: no TFLint plugin or
# .tflint.hcl, no zizmor token or configuration, no Kubernetes schema cache, no
# Vale styles or .vale.ini, no yt-dlp configuration, no Trivy plugins or
# server, no Infracost login or `infracost setup`. Those belong to the
# repository or the operator.

if ! declare -F release_cli_command >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi

# release_cli_asset_name <key> [tag]: without a tag, a {version} placeholder
# is left for the release metadata to fill.
release_cli_asset_name() {
	local key="$1" tag="${2:-}" asset arch triple arch_word arch_bits suffix release_arch
	asset="$(release_cli_field "$key" asset)" || return 1
	[[ "$(uname -s)" == Linux ]] || return 1
	case "$(uname -m)" in
	x86_64 | amd64) arch=amd64 release_arch=x86_64 triple=x86_64 arch_word=64-bit arch_bits=64bit suffix='' ;;
	aarch64 | arm64) arch=arm64 release_arch=arm64 triple=aarch64 arch_word=arm64 arch_bits=ARM64 suffix=_aarch64 ;;
	*) return 1 ;;
	esac
	asset="${asset//\{arch\}/$arch}"
	asset="${asset//\{release_arch\}/$release_arch}"
	asset="${asset//\{triple\}/$triple}"
	asset="${asset//\{arch_word\}/$arch_word}"
	asset="${asset//\{arch_bits\}/$arch_bits}"
	asset="${asset//\{aarch64_suffix\}/$suffix}"
	[[ -z "$tag" ]] || asset="${asset//\{version\}/${tag#v}}"
	printf '%s\n' "$asset"
}

# Prints the latest tag and the asset's SHA-256 digest, one per line. Fails when
# the release has no such asset or GitHub published no digest for it: an asset
# that cannot be verified is not installed.
release_cli_latest_release_metadata() {
	local key="$1" repository asset json
	repository="$(release_cli_field "$key" repository)" || return 1
	asset="$(release_cli_asset_name "$key")" || return 1
	json="$(github_api_release_json "$repository")" || return 1
	python3 -c '
import json
import re
import sys

release = json.load(sys.stdin)
tag = release.get("tag_name", "")
if not re.fullmatch(r"v?[0-9]+\.[0-9]+\.[0-9]+(?:[+-][0-9A-Za-z.-]+)?", tag):
    raise SystemExit(1)
asset_name = sys.argv[1].replace("{version}", tag.removeprefix("v"))
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

# Lists the archive's members, one per line.
_release_cli_members() {
	local archive_type="$1" archive="$2"
	case "$archive_type" in
	tar) tar -tzf "$archive" ;;
	zip) unzip -Z1 "$archive" ;;
	raw) printf '%s\n' "$3" ;;
	*) return 1 ;;
	esac
}

_release_cli_extract() {
	local archive_type="$1" archive="$2" destination="$3" member="$4"
	case "$archive_type" in
	tar) tar -xzf "$archive" -C "$destination" "$member" ;;
	zip) unzip -q -o "$archive" "$member" -d "$destination" ;;
	raw) cp -- "$archive" "$destination/$member" ;;
	*) return 1 ;;
	esac
}

release_cli_install_release() {
	local key="$1" release_tag="$2" expected="$3"
	local label repository archive_type binary asset url tmp archive actual
	local install_path stamp candidate member has_binary=0 command_name
	local -a members=() version_argv=()
	label="$(release_cli_field "$key" label)" || return 1
	repository="$(release_cli_field "$key" repository)"
	archive_type="$(release_cli_field "$key" archive)"
	binary="$(release_cli_field "$key" binary)"
	read -r -a version_argv <<<"$(release_cli_field "$key" version-args)"
	install_path="$(release_cli_install_path "$key")"
	stamp="$(release_cli_management_stamp "$key")"
	asset="$(release_cli_asset_name "$key" "$release_tag")" || {
		echo "  ${label} supports only Linux amd64/arm64 in this installer." >&2
		return 1
	}
	url="https://github.com/${repository}/releases/download/${release_tag}/${asset}"

	local extractor=tar
	[[ "$archive_type" == zip ]] && extractor=unzip
	[[ "$archive_type" == raw ]] && extractor='cp'
	for command_name in curl sha256sum install "$extractor"; do
		command -v "$command_name" >/dev/null 2>&1 || {
			echo "  ${command_name} is required to install ${label}." >&2
			return 1
		}
	done

	tmp="$(mktemp -d)" || return 1
	trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
	archive="$tmp/$asset"
	# A raw asset is the binary; it is downloaded beside the extraction target
	# rather than as it, so the listing and extraction steps stay uniform.
	[[ "$archive_type" == raw ]] && archive="$tmp/asset.raw"
	log_step "Install ${label} ${release_tag}"
	if ! github_curl -fsSL -o "$archive" "$url"; then
		echo "  Failed to download ${asset}." >&2
		return 1
	fi
	actual="$(sha256sum "$archive" | awk '{print $1}')"
	if [[ "$actual" != "$expected" ]]; then
		echo "  ${label} SHA-256 verification failed; refusing to install the downloaded binary." >&2
		return 1
	fi

	# Listed before anything is extracted, and only the binary is extracted:
	# an added LICENSE is inert, a member that escapes the directory is not.
	mapfile -t members < <(_release_cli_members "$archive_type" "$archive" "$binary")
	if [[ "${#members[@]}" -eq 0 ]]; then
		echo "  ${label} archive could not be listed; refusing extraction." >&2
		return 1
	fi
	for member in "${members[@]}"; do
		case "$member" in
		"$binary") has_binary=1 ;;
		/* | ../* | */../* | */..)
			echo "  ${label} archive member '${member}' escapes the extraction directory; refusing extraction." >&2
			return 1
			;;
		esac
	done
	if [[ "$has_binary" -ne 1 ]]; then
		echo "  ${label} archive does not contain a top-level ${binary} binary; refusing extraction." >&2
		return 1
	fi
	_release_cli_extract "$archive_type" "$archive" "$tmp" "$binary" >/dev/null || return $?
	[[ -f "$tmp/$binary" && ! -L "$tmp/$binary" ]] || {
		echo "  ${label} archive did not contain a regular ${binary} binary." >&2
		return 1
	}

	install -d -m 0755 "$(dirname -- "$install_path")"
	candidate="$(dirname -- "$install_path")/.${binary}.candidate.$$"
	install -m 0755 "$tmp/$binary" "$candidate" || return $?
	if [[ "$("$candidate" "${version_argv[@]}" 2>/dev/null | head -n1 || true)" != *"${release_tag#v}"* ]]; then
		rm -f -- "$candidate"
		echo "  Downloaded ${label} binary did not report ${release_tag}." >&2
		return 1
	fi
	mv -f -- "$candidate" "$install_path" || return $?
	install -d -m 0755 "$(dirname -- "$stamp")"
	printf 'v%s\n' "${release_tag#v}" >"$tmp/stamp"
	install -m 0644 "$tmp/stamp" "$stamp" || return $?
	rm -rf -- "$tmp"
	trap - RETURN
	log_ok "${label} ${release_tag} installed at ${install_path}"
}

# Installs the latest verified release unless the one installed is already as
# new. With force, reinstalls it even then.
release_cli_sync_latest_release() {
	dotfiles_catalog_install "$1" "${2:-0}"
}

install_release_cli() {
	dotfiles_catalog_install "$1"
}

check_release_cli() {
	dotfiles_catalog_check "$1" "$(release_cli_field "$1" label)"
}

upgrade_release_cli() {
	dotfiles_catalog_upgrade "$1"
}

# The per-component names the registry, probes and update steps call.
check_kubeconform() { check_release_cli kubeconform; }
check_tflint() { check_release_cli tflint; }
check_zizmor() { check_release_cli zizmor; }
check_vale() { check_release_cli vale; }
check_yt_dlp() { check_release_cli yt_dlp; }
check_trivy() { check_release_cli trivy; }
check_infracost() { check_release_cli infracost; }
upgrade_kubeconform() { upgrade_release_cli kubeconform; }
upgrade_tflint() { upgrade_release_cli tflint; }
upgrade_zizmor() { upgrade_release_cli zizmor; }
upgrade_vale() { upgrade_release_cli vale; }
upgrade_yt_dlp() { upgrade_release_cli yt_dlp; }
upgrade_trivy() { upgrade_release_cli trivy; }
upgrade_infracost() { upgrade_release_cli infracost; }
