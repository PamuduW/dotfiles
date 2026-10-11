# shellcheck shell=bash
# Kubeconform, TFLint and zizmor: the latest GitHub release of each, verified
# against the SHA-256 digest GitHub publishes for the asset, installed to
# ~/.local/bin. The rows are in RELEASE_CLI_TOOLS (managed_tool_state.sh).
#
# Dotfiles owns the executable and nothing else: no TFLint plugin or
# .tflint.hcl, no zizmor token or configuration, no Kubernetes schema cache.
# Those belong to the repository that uses the tool.

if ! declare -F release_cli_command >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi

release_cli_asset_name() {
	local key="$1" asset arch triple
	asset="$(release_cli_field "$key" asset)" || return 1
	[[ "$(uname -s)" == Linux ]] || return 1
	case "$(uname -m)" in
	x86_64 | amd64) arch=amd64 triple=x86_64 ;;
	aarch64 | arm64) arch=arm64 triple=aarch64 ;;
	*) return 1 ;;
	esac
	asset="${asset//\{arch\}/$arch}"
	printf '%s\n' "${asset//\{triple\}/$triple}"
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

asset_name = sys.argv[1]
release = json.load(sys.stdin)
tag = release.get("tag_name", "")
if not re.fullmatch(r"v?[0-9]+\.[0-9]+\.[0-9]+(?:[+-][0-9A-Za-z.-]+)?", tag):
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

# Lists the archive's members, one per line.
_release_cli_members() {
	local archive_type="$1" archive="$2"
	case "$archive_type" in
	tar) tar -tzf "$archive" ;;
	zip) unzip -Z1 "$archive" ;;
	*) return 1 ;;
	esac
}

_release_cli_extract() {
	local archive_type="$1" archive="$2" destination="$3" member="$4"
	case "$archive_type" in
	tar) tar -xzf "$archive" -C "$destination" "$member" ;;
	zip) unzip -q -o "$archive" "$member" -d "$destination" ;;
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
	asset="$(release_cli_asset_name "$key")" || {
		echo "  ${label} supports only Linux amd64/arm64 in this installer." >&2
		return 1
	}
	url="https://github.com/${repository}/releases/download/${release_tag}/${asset}"

	for command_name in curl sha256sum install "$([[ "$archive_type" == zip ]] && echo unzip || echo tar)"; do
		command -v "$command_name" >/dev/null 2>&1 || {
			echo "  ${command_name} is required to install ${label}." >&2
			return 1
		}
	done

	tmp="$(mktemp -d)" || return 1
	trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
	archive="$tmp/$asset"
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
	mapfile -t members < <(_release_cli_members "$archive_type" "$archive")
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
	local key="$1" force="${2:-0}" label installed latest
	local -a metadata=()
	label="$(release_cli_field "$key" label)" || return 1
	mapfile -t metadata < <(release_cli_latest_release_metadata "$key")
	[[ "${#metadata[@]}" -eq 2 ]] || {
		echo "  Could not verify the latest ${label} release and published digest; preserving the installed binary." >&2
		return 1
	}
	latest="v${metadata[0]#v}"
	installed="$(release_cli_installed_tag "$key" 2>/dev/null || true)"
	if [[ "$force" != 1 && -n "$installed" ]] &&
		[[ "$(printf '%s\n%s\n' "${installed#v}" "${latest#v}" | sort -V | tail -n1)" == "${installed#v}" ]]; then
		log_skip "${label} already current at ${installed}"
		return 0
	fi
	release_cli_install_release "$key" "${metadata[0]}" "${metadata[1]}"
}

install_release_cli() {
	local key="$1" label existing
	label="$(release_cli_field "$key" label)" || return 1
	if existing="$(release_cli_command "$key" 2>/dev/null)"; then
		# An installation Dotfiles does not own is never touched, forced or not.
		if ! release_cli_is_dotfiles_owned "$key"; then
			log_warn "${label} already exists outside Dotfiles ownership at ${existing}; preserving it"
			return 0
		fi
		if skip_unless_forced "${label} already installed"; then
			return 0
		fi
		release_cli_sync_latest_release "$key" 1
		return
	fi
	release_cli_sync_latest_release "$key"
}

check_release_cli() {
	local key="$1" label installed latest action available='—' upgradable=0
	local -a metadata=()
	label="$(release_cli_field "$key" label)" || return 1
	installed="$(release_cli_installed_version "$key")"
	if [[ "$installed" == 'not installed' ]]; then
		action=skip
	elif ! release_cli_is_dotfiles_owned "$key"; then
		action=external
	else
		mapfile -t metadata < <(release_cli_latest_release_metadata "$key" 2>/dev/null)
		if [[ "${#metadata[@]}" -eq 2 ]]; then
			latest="v${metadata[0]#v}"
			available="$latest"
			if [[ "$(printf '%s\n%s\n' "${installed#v}" "${latest#v}" | sort -V | tail -n1)" != "${installed#v}" ]]; then
				action=upgrade
				upgradable=1
			else
				action=current
			fi
		else
			action=unknown
		fi
	fi
	printf '%s|%s|%s|%s\n' "$label" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}

upgrade_release_cli() {
	local key="$1" label before after
	label="$(release_cli_field "$key" label)" || return 1
	if ! release_cli_command "$key" >/dev/null 2>&1; then
		log_skip "${label} not installed"
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	if ! release_cli_is_dotfiles_owned "$key"; then
		log_skip "${label} is externally managed; preserving it"
		if declare -F upgrade_result_set >/dev/null 2>&1; then upgrade_result_set skipped; fi
		return 0
	fi
	before="$(release_cli_installed_tag "$key" 2>/dev/null || true)"
	release_cli_sync_latest_release "$key" || return $?
	after="$(release_cli_installed_tag "$key" 2>/dev/null || true)"
	if declare -F upgrade_result_set >/dev/null 2>&1; then
		if [[ "$after" != "$before" ]]; then
			upgrade_result_set updated
		else
			upgrade_result_set already-current
		fi
	fi
}

# The per-component names the registry, probes and update steps call.
check_kubeconform() { check_release_cli kubeconform; }
check_tflint() { check_release_cli tflint; }
check_zizmor() { check_release_cli zizmor; }
upgrade_kubeconform() { upgrade_release_cli kubeconform; }
upgrade_tflint() { upgrade_release_cli tflint; }
upgrade_zizmor() { upgrade_release_cli zizmor; }
