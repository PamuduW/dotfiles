# shellcheck shell=bash

_INSTALL_LIB_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/installers/logging.sh
source "$_INSTALL_LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/installers/apt.sh
source "$_INSTALL_LIB_DIR/apt.sh"
# shellcheck source=scripts/lib/installers/github_release.sh
source "$_INSTALL_LIB_DIR/github_release.sh"
# shellcheck source=scripts/lib/installers/docker.sh
source "$_INSTALL_LIB_DIR/docker.sh"
# shellcheck source=scripts/lib/installers/cli_tools.sh
source "$_INSTALL_LIB_DIR/cli_tools.sh"
# shellcheck source=scripts/lib/installers/fonts.sh
source "$_INSTALL_LIB_DIR/fonts.sh"
# shellcheck source=scripts/lib/installers/stow.sh
source "$_INSTALL_LIB_DIR/stow.sh"
