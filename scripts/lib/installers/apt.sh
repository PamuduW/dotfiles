# shellcheck shell=bash
# Requires: PKG_FILE, logging.sh

if ! declare -F read_packages_by_tags >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/package_metadata.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/package_metadata.sh"
fi

# Whether apt can install this name on this release. A package that exists in
# the index has a Candidate line; an unknown name produces no output at all, and
# a name that exists only as a stale record has `Candidate: (none)`.
apt_package_is_available() {
	local candidate
	candidate="$(apt-cache policy -- "$1" 2>/dev/null | awk '/^  Candidate:/ {print $2; exit}')"
	[[ -n "$candidate" && "$candidate" != '(none)' ]]
}

# Partition a package list into what this release actually has.
#
# `apt-get install` is all-or-nothing: one unknown name aborts the whole
# transaction. A single package dropped from a new Ubuntu release therefore
# left every other package uninstalled, which then took out anything depending
# on them -- a missing `stow` failing the dotfiles component, for instance.
# Install what exists, name what does not, and let the probes report the gap.
apt_install_packages() {
	local pkgs rc
	mapfile -t pkgs < <(read_packages_by_tags "$@")
	if [[ ${#pkgs[@]} -eq 0 ]]; then
		log_skip "No packages for tags: $*"
		return 0
	fi

	local -a available=() unavailable=()
	local pkg
	for pkg in "${pkgs[@]}"; do
		if apt_package_is_available "$pkg"; then
			available+=("$pkg")
		else
			unavailable+=("$pkg")
		fi
	done

	if ((${#unavailable[@]} > 0)); then
		log_warn "Not available on this release, skipping: ${unavailable[*]}"
	fi

	if ((${#available[@]} == 0)); then
		log_warn "No requested packages are available for tags: $*"
		return 0
	fi

	log_step "Install apt packages: $*"
	if _run_quiet_command "apt packages ($*)" sudo apt-get -qq -o Dpkg::Use-Pty=0 install -y "${available[@]}"; then
		if ((${#unavailable[@]} > 0)); then
			log_ok "Apt packages installed: $* (${#unavailable[@]} unavailable on this release)"
		else
			log_ok "Apt packages installed: $*"
		fi
	else
		rc=$?
		log_warn "Apt package install failed: $*"
		return "$rc"
	fi
}
