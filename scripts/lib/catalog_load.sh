# shellcheck shell=bash
# The implementation is linted as a production file. Load it once at runtime
# without expanding it into every installer during static source analysis.
if ! declare -F dotfiles_catalog_begin >/dev/null; then
	_DOTFILES_CATALOG_SOURCE="${BASH_SOURCE[0]%/*}/software_catalog.sh"
	# shellcheck source=/dev/null
	source "$_DOTFILES_CATALOG_SOURCE"
fi
