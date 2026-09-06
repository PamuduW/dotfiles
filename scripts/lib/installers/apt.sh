# shellcheck shell=bash
# Requires: PKG_FILE, logging.sh

if ! declare -F read_packages_by_tags >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/package_metadata.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/package_metadata.sh"
fi

# Refresh only the source list a component just added.
#
# A bare `apt-get update` re-fetches every configured index, which on a fresh
# machine is the dominant cost of adding one vendor repository: the install
# preamble has already refreshed the rest, and nothing else has changed since.
# Falls back to a full refresh when the targeted form is unavailable, so a
# component is never left installing against an index that does not list it.
apt_refresh_source_list() {
	local list="$1"
	[[ -f "$list" ]] || {
		sudo apt-get update -qq
		return $?
	}
	sudo apt-get update -qq \
		-o Dir::Etc::sourcelist="$list" \
		-o Dir::Etc::sourceparts=- \
		-o APT::Get::List-Cleanup=0 ||
		sudo apt-get update -qq
}

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
	local entry pkg chosen
	for entry in "${pkgs[@]}"; do
		# `a|b` means "a, or b where a does not exist". Package renames are the
		# common case: `dnsutils` became `bind9-dnsutils`, and the transitional
		# name was dropped in a later release.
		chosen=''
		while IFS= read -r pkg; do
			[[ -n "$pkg" ]] || continue
			if apt_package_is_available "$pkg"; then
				chosen="$pkg"
				break
			fi
		done < <(printf '%s\n' "${entry//|/$'\n'}")
		if [[ -n "$chosen" ]]; then
			available+=("$chosen")
		else
			unavailable+=("${entry//|/ or }")
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
