# shellcheck shell=bash

BOOST_PINNED_VERSION="v0.12.6"
BOOST_RELEASE_REPOSITORY="jfrog/boost"
BOOST_LINUX_AMD64_SHA256="a15bf39a41fe2d768054d0137c1dfa30b2feb4d4f83cdb8b1919fab5b8d75896"
BOOST_LINUX_ARM64_SHA256="146b677e5e57671bd189c17be7edd31d583ea2a555b30d5c57a3c18f9d466312"

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
	[[ "$(<"$stamp")" == "$BOOST_PINNED_VERSION" ]]
}

boost_platform_arch() {
	[[ "$(uname -s)" == Linux ]] || return 1
	case "$(uname -m)" in
	x86_64 | amd64) printf '%s\n' amd64 ;;
	aarch64 | arm64) printf '%s\n' arm64 ;;
	*) return 1 ;;
	esac
}

boost_expected_sha256() {
	case "$1" in
	amd64) printf '%s\n' "$BOOST_LINUX_AMD64_SHA256" ;;
	arm64) printf '%s\n' "$BOOST_LINUX_ARM64_SHA256" ;;
	*) return 1 ;;
	esac
}

check_boost_cli() {
	local installed action
	installed="$(boost_installed_version)"
	if [[ "$installed" == 'not installed' ]]; then
		action=skip
	elif boost_cli_is_dotfiles_owned; then
		if [[ "$installed" == *"${BOOST_PINNED_VERSION#v}"* ]]; then
			action=pinned
		else
			action='restore pin'
		fi
	else
		action='externally managed'
	fi
	printf 'Boost CLI|%s|%s|%s\n' "$installed" "$BOOST_PINNED_VERSION" "$action"
}

install_boost_cli() {
	local existing arch asset expected archive_url tmp archive actual install_path stamp
	install_path="$(boost_install_path)"
	stamp="$(boost_management_stamp)"

	if existing="$(boost_command 2>/dev/null)" && ! boost_cli_is_dotfiles_owned; then
		log_warn "Boost CLI already exists outside Dotfiles ownership at ${existing}; preserving it"
		return 0
	fi
	if boost_cli_is_dotfiles_owned && [[ "$(boost_installed_version)" == *"${BOOST_PINNED_VERSION#v}"* ]]; then
		log_skip "Boost CLI already installed at ${BOOST_PINNED_VERSION}"
		return 0
	fi

	arch="$(boost_platform_arch)" || {
		echo "  Boost ${BOOST_PINNED_VERSION} supports only Linux amd64/arm64 in this installer." >&2
		return 1
	}
	asset="boost-linux-${arch}.tar.gz"
	expected="$(boost_expected_sha256 "$arch")" || return 1
	archive_url="https://github.com/${BOOST_RELEASE_REPOSITORY}/releases/download/${BOOST_PINNED_VERSION}/${asset}"

	for command_name in curl tar sha256sum install; do
		command -v "$command_name" >/dev/null 2>&1 || {
			echo "  ${command_name} is required to install Boost." >&2
			return 1
		}
	done

	tmp="$(mktemp -d)" || return 1
	trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' RETURN
	archive="$tmp/$asset"
	log_step "Install Boost CLI ${BOOST_PINNED_VERSION}"
	if ! github_curl -fsSL -o "$archive" "$archive_url"; then
		echo "  Failed to download ${asset}." >&2
		return 1
	fi
	actual="$(sha256sum "$archive" | awk '{print $1}')"
	if [[ "$actual" != "$expected" ]]; then
		echo "  Boost SHA-256 verification failed; refusing to install the downloaded binary." >&2
		return 1
	fi

	local -a members=()
	mapfile -t members < <(tar -tzf "$archive") || return 1
	if [[ "${#members[@]}" -ne 2 || "${members[0]}" != boost || "${members[1]}" != boost-ci ]]; then
		echo "  Boost archive contents are unexpected; refusing extraction." >&2
		return 1
	fi
	tar -xzf "$archive" -C "$tmp" boost || return $?
	[[ -f "$tmp/boost" && ! -L "$tmp/boost" ]] || {
		echo "  Boost archive did not contain a regular boost binary." >&2
		return 1
	}

	install -d -m 0755 "$(dirname -- "$install_path")"
	install -m 0755 "$tmp/boost" "$install_path" || return $?
	if [[ "$("$install_path" version 2>/dev/null | head -n1 || true)" != *"${BOOST_PINNED_VERSION#v}"* ]]; then
		echo "  Installed Boost binary did not report ${BOOST_PINNED_VERSION}." >&2
		return 1
	fi
	install -d -m 0755 "$(dirname -- "$stamp")"
	printf '%s\n' "$BOOST_PINNED_VERSION" >"$tmp/boost-cli.version"
	install -m 0644 "$tmp/boost-cli.version" "$stamp" || return $?
	rm -rf -- "$tmp"
	trap - RETURN
	log_ok "Boost CLI ${BOOST_PINNED_VERSION} installed at ${install_path}"
}

upgrade_boost_cli() {
	if ! boost_command >/dev/null 2>&1; then
		printf '%s\n' '  Boost CLI not installed, skipping'
		return 0
	fi
	if ! boost_cli_is_dotfiles_owned; then
		printf '%s\n' '  Boost CLI is externally managed, preserving it'
		return 0
	fi
	install_boost_cli
}
