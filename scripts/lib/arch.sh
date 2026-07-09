# shellcheck shell=bash
# Map uname -m to GitHub release tarball architecture suffix (x86_64 / arm64).

_linux_github_arch_suffix() {
	local arch
	arch="$(uname -m)"
	case "$arch" in
	x86_64 | amd64) printf '%s\n' 'x86_64' ;;
	aarch64 | arm64) printf '%s\n' 'arm64' ;;
	*)
		printf 'Unsupported CPU architecture for GitHub Linux binaries: %s\n' "$arch" >&2
		return 1
		;;
	esac
}
