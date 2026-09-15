# shellcheck shell=bash

_COMPONENTS_LIB_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/components/registry.sh
source "$_COMPONENTS_LIB_DIR/registry.sh"
# shellcheck source=scripts/lib/components/plan.sh
source "$_COMPONENTS_LIB_DIR/plan.sh"
# shellcheck source=scripts/lib/components/probes.sh
source "$_COMPONENTS_LIB_DIR/probes.sh"
if [[ -z "${DOTFILES_SHARED_LIB:-}" ]]; then
	# shellcheck source=scripts/lib/shared_resolve.sh
	source "$_COMPONENTS_LIB_DIR/../shared_resolve.sh"
	dotfiles_shared_require "$_COMPONENTS_LIB_DIR/../../.." || return 1
fi
# shellcheck source=/dev/null
source "$DOTFILES_SHARED_LIB/sudo_prime.sh"
# shellcheck source=scripts/lib/components/install_dispatch.sh
source "$_COMPONENTS_LIB_DIR/install_dispatch.sh"
# shellcheck source=scripts/lib/components/menu.sh
source "$_COMPONENTS_LIB_DIR/menu.sh"

comp_registry_validate_contract

comp_registry_init
