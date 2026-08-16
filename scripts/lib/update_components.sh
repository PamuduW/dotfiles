# shellcheck shell=bash
# Compatibility loader for the focused update modules. Public function names
# remain unchanged for update_workflow.sh and the dotfiles CLI.

_UPDATE_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/updates" && pwd)"
# shellcheck source=scripts/lib/updates/common.sh
source "$_UPDATE_MODULE_DIR/common.sh"
# shellcheck source=scripts/lib/updates/system.sh
source "$_UPDATE_MODULE_DIR/system.sh"
# shellcheck source=scripts/lib/updates/integrations.sh
source "$_UPDATE_MODULE_DIR/integrations.sh"
# shellcheck source=scripts/lib/updates/runtimes.sh
source "$_UPDATE_MODULE_DIR/runtimes.sh"
# shellcheck source=scripts/lib/updates/repository.sh
source "$_UPDATE_MODULE_DIR/repository.sh"
