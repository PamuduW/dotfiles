# shellcheck shell=bash
# Requires: PKG_FILE, logging.sh

if ! declare -F read_packages_by_tags >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/package_metadata.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/package_metadata.sh"
fi

apt_install_packages() {
	local pkgs rc
	mapfile -t pkgs < <(read_packages_by_tags "$@")
	if [[ ${#pkgs[@]} -eq 0 ]]; then
		log_skip "No packages for tags: $*"
		return 0
	fi
	log_step "Install apt packages: $*"
	if _run_quiet_command "apt packages ($*)" sudo apt-get -qq -o Dpkg::Use-Pty=0 install -y "${pkgs[@]}"; then
		log_ok "Apt packages installed: $*"
	else
		rc=$?
		log_warn "Apt package install failed: $*"
		return "$rc"
	fi
}
