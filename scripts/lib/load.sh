# shellcheck shell=bash
# shellcheck disable=SC1091  # Dynamic loader paths are rooted beside this file.
# Load unified menu / UI library (order matters).

_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# The shared terminal stack lives in the dotfiles-shared repository. Resolve it
# before anything sources from it, so a missing or mismatched checkout reports
# itself instead of failing on whichever `source` happens to run first.
# shellcheck source=scripts/lib/shared_resolve.sh
source "$_LIB_DIR/shared_resolve.sh"
dotfiles_shared_resolve "$(cd -- "$_LIB_DIR/../.." && pwd)" || return 1
_TUI_DIR="$DOTFILES_SHARED_LIB/tui"

# shellcheck source=scripts/lib/bootstrap.sh
source "$_LIB_DIR/bootstrap.sh"
source "$_TUI_DIR/colors.sh"
# shellcheck source=scripts/lib/parallel_probe.sh
source "$_LIB_DIR/parallel_probe.sh"
# shellcheck source=scripts/lib/tool_resolve.sh
source "$_LIB_DIR/tool_resolve.sh"
source "$_TUI_DIR/menu_render.sh"
source "$_TUI_DIR/tty.sh"
# shellcheck source=scripts/lib/repo_update.sh
source "$_LIB_DIR/repo_update.sh"
source "$_TUI_DIR/report_table.sh"
# shellcheck source=scripts/lib/wsl_conf.sh
source "$_LIB_DIR/wsl_conf.sh"
# shellcheck source=scripts/lib/command_metadata.sh
source "$_LIB_DIR/command_metadata.sh"
# shellcheck source=scripts/lib/github_token.sh
source "$_LIB_DIR/github_token.sh"
source "$_TUI_DIR/ui.sh"
ui_init_colors
source "$_TUI_DIR/menu_descriptions.sh"
source "$_TUI_DIR/menu_keys.sh"
source "$_TUI_DIR/menu_simple.sh"
source "$_TUI_DIR/menu_paging.sh"
source "$_TUI_DIR/menu_checkbox.sh"
source "$_TUI_DIR/menu_runner.sh"
# shellcheck source=scripts/lib/docker.sh
source "$_LIB_DIR/docker.sh"
# shellcheck source=scripts/lib/arch.sh
source "$_LIB_DIR/arch.sh"
