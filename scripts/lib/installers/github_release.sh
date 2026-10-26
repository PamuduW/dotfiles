# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"

if ! declare -F github_curl >/dev/null; then
	_GITHUB_RELEASE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
	# shellcheck source=scripts/lib/github_api.sh
	source "$_GITHUB_RELEASE_LIB_DIR/github_api.sh"
fi

install_lazygit_from_github() {
	dotfiles_catalog_install "lazygit"
}

install_lazydocker_from_github() {
	dotfiles_catalog_install "lazydocker"
}
