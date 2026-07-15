# shellcheck shell=bash

if ! declare -F github_curl >/dev/null; then
	_GITHUB_RELEASE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
	# shellcheck source=scripts/lib/github_api.sh
	source "$_GITHUB_RELEASE_LIB_DIR/github_api.sh"
fi

install_lazygit_from_github() {
	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for lazygit install." >&2
		return 1
	}
	command -v tar >/dev/null 2>&1 || {
		echo "  tar required for lazygit install." >&2
		return 1
	}

	log_step "Install lazygit from GitHub releases"
	local ver tmp
	ver="$(github_latest_release_version jesseduffield/lazygit)" || {
		echo "  Could not determine lazygit version." >&2
		return 1
	}

	tmp="$(mktemp -d)"
	# shellcheck disable=SC2064  # Capture this invocation's temp path now for RETURN cleanup.
	trap "rm -rf -- '$tmp'; trap - RETURN" RETURN
	local arch_suffix tarball
	arch_suffix="$(_linux_github_arch_suffix)" || return 1
	tarball="lazygit_${ver}_linux_${arch_suffix}.tar.gz"
	github_curl -fsSL -o "$tmp/$tarball" \
		"https://github.com/jesseduffield/lazygit/releases/download/v${ver}/${tarball}"
	github_curl -fsSL -o "$tmp/checksums.txt" \
		"https://github.com/jesseduffield/lazygit/releases/download/v${ver}/checksums.txt"
	if ! (cd "$tmp" && sha256sum --check --ignore-missing checksums.txt); then
		echo "  lazygit checksum verification failed." >&2
		return 1
	fi
	tar -C "$tmp" -xzf "$tmp/$tarball" lazygit
	sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
	rm -rf "$tmp"
	trap - RETURN
	log_ok "lazygit v${ver} installed"
}

install_lazydocker_from_github() {
	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for lazydocker install." >&2
		return 1
	}
	command -v tar >/dev/null 2>&1 || {
		echo "  tar required for lazydocker install." >&2
		return 1
	}

	log_step "Install lazydocker from GitHub releases"
	local ver tmp
	ver="$(github_latest_release_version jesseduffield/lazydocker)" || {
		echo "  Could not determine lazydocker version." >&2
		return 1
	}

	tmp="$(mktemp -d)"
	# shellcheck disable=SC2064  # Capture this invocation's temp path now for RETURN cleanup.
	trap "rm -rf -- '$tmp'; trap - RETURN" RETURN
	local arch_suffix tarball
	arch_suffix="$(_linux_github_arch_suffix)" || return 1
	tarball="lazydocker_${ver}_Linux_${arch_suffix}.tar.gz"
	github_curl -fsSL -o "$tmp/$tarball" \
		"https://github.com/jesseduffield/lazydocker/releases/download/v${ver}/${tarball}"
	github_curl -fsSL -o "$tmp/checksums.txt" \
		"https://github.com/jesseduffield/lazydocker/releases/download/v${ver}/checksums.txt"
	if ! (cd "$tmp" && sha256sum --check --ignore-missing checksums.txt); then
		echo "  lazydocker checksum verification failed." >&2
		return 1
	fi
	tar -C "$tmp" -xzf "$tmp/$tarball"

	if [[ ! -f "$tmp/lazydocker" ]]; then
		local binpath
		binpath="$(find "$tmp" -maxdepth 3 -type f -name lazydocker | head -n1 || true)"
		[[ -n "$binpath" ]] && cp "$binpath" "$tmp/lazydocker"
	fi

	sudo install -m 0755 "$tmp/lazydocker" /usr/local/bin/lazydocker
	rm -rf "$tmp"
	trap - RETURN
	log_ok "lazydocker v${ver} installed"
}
