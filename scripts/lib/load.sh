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
# shellcheck source=scripts/lib/agent_bootstrap_paths.sh
source "$_LIB_DIR/agent_bootstrap_paths.sh"
# shellcheck source=scripts/lib/menu_runner.sh
source "$_LIB_DIR/menu_runner.sh"
# shellcheck source=scripts/lib/docker.sh
source "$_LIB_DIR/docker.sh"
# shellcheck source=scripts/lib/arch.sh
source "$_LIB_DIR/arch.sh"

# Legacy aliases for component_menu until migrated to menu_checkbox_run.
_fit_menu_line() { menu_fit_line "$@"; }
_fit_menu_line_with_indent() { menu_fit_indent "$@"; }
_menu_tty_cols() { menu_tty_cols; }
_menu_tty_rows() { menu_tty_rows; }
_menu_clear_screen() { ui_clear; }
_read_component_menu_key() { menu_read_key; }

_menu_decode_escape_sequence() {
	local seq="$1"
	case "$seq" in
	'[A' | 'OA') printf 'up\n' ;;
	'[B' | 'OB') printf 'down\n' ;;
	*) printf 'ignore\n' ;;
	esac
}
