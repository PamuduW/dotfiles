# shellcheck shell=bash
# shellcheck disable=SC1091  # Dynamic loader paths are rooted beside this file.
# Load unified menu / UI library (order matters).

_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/bootstrap.sh
source "$_LIB_DIR/bootstrap.sh"
# shellcheck source=scripts/lib/menu_render.sh
source "$_LIB_DIR/menu_render.sh"
# shellcheck source=scripts/lib/tty.sh
source "$_LIB_DIR/tty.sh"
# shellcheck source=scripts/lib/repo_update.sh
source "$_LIB_DIR/repo_update.sh"
# shellcheck source=scripts/lib/report_table.sh
source "$_LIB_DIR/report_table.sh"
# shellcheck source=scripts/lib/wsl_conf.sh
source "$_LIB_DIR/wsl_conf.sh"
# shellcheck source=scripts/lib/command_metadata.sh
source "$_LIB_DIR/command_metadata.sh"
# shellcheck source=scripts/lib/github_token.sh
source "$_LIB_DIR/github_token.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_LIB_DIR/ui.sh"
ui_init_colors
# shellcheck source=scripts/lib/menu_descriptions.sh
source "$_LIB_DIR/menu_descriptions.sh"
# shellcheck source=scripts/lib/menu_keys.sh
source "$_LIB_DIR/menu_keys.sh"
# shellcheck source=scripts/lib/menu_simple.sh
source "$_LIB_DIR/menu_simple.sh"
# shellcheck source=scripts/lib/menu_paging.sh
source "$_LIB_DIR/menu_paging.sh"
# shellcheck source=scripts/lib/menu_checkbox.sh
source "$_LIB_DIR/menu_checkbox.sh"
# shellcheck source=scripts/lib/menu_runner.sh
source "$_LIB_DIR/menu_runner.sh"
# shellcheck source=scripts/lib/docker.sh
source "$_LIB_DIR/docker.sh"
# shellcheck source=scripts/lib/arch.sh
source "$_LIB_DIR/arch.sh"
