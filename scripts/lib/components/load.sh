# shellcheck shell=bash

_COMPONENTS_LIB_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/components/registry.sh
source "$_COMPONENTS_LIB_DIR/registry.sh"
# shellcheck source=scripts/lib/components/descriptions.sh
source "$_COMPONENTS_LIB_DIR/descriptions.sh"
# shellcheck source=scripts/lib/components/plan.sh
source "$_COMPONENTS_LIB_DIR/plan.sh"
# shellcheck source=scripts/lib/components/probes.sh
source "$_COMPONENTS_LIB_DIR/probes.sh"
# shellcheck source=scripts/lib/components/install_dispatch.sh
source "$_COMPONENTS_LIB_DIR/install_dispatch.sh"
# shellcheck source=scripts/lib/components/menu.sh
source "$_COMPONENTS_LIB_DIR/menu.sh"

comp_registry_init
