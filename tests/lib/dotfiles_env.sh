# shellcheck shell=bash
# shellcheck disable=SC1091  # Loader paths are rooted at REPO_DIR.
# Load the Dotfiles library set for behavior tests.
#
# The component, installer, and update modules form one dependency web
# (probes read the registry, install dispatch reads the installers, the update
# workflow reads both), so behavior suites that touch any of it load all of it.
# Kept here rather than repeated at the top of every suite.
#
# Requires REPO_DIR. Exports DOTFILES_DIR so the modules resolve their paths.

DOTFILES_DIR="${REPO_DIR:?dotfiles_env.sh requires REPO_DIR}"
export DOTFILES_DIR

source "$REPO_DIR/scripts/lib/shared/tui/tty.sh"
source "$REPO_DIR/scripts/lib/shared/tui/menu_render.sh"
source "$REPO_DIR/scripts/lib/repo_update.sh"
source "$REPO_DIR/scripts/lib/wsl_conf.sh"
source "$REPO_DIR/scripts/lib/components/registry.sh"
source "$REPO_DIR/scripts/lib/installers/apt.sh"
# shellcheck source=scripts/lib/managed_tool_state.sh
source "$REPO_DIR/scripts/lib/managed_tool_state.sh"
source "$REPO_DIR/scripts/lib/installers/cli_tools.sh"
source "$REPO_DIR/scripts/lib/installers/docker.sh"
source "$REPO_DIR/scripts/lib/installers/remote_script.sh"
source "$REPO_DIR/scripts/lib/installers/github_release.sh"
source "$REPO_DIR/scripts/lib/components/probes.sh"
source "$REPO_DIR/scripts/lib/installers/stow.sh"
source "$REPO_DIR/scripts/lib/components/install_dispatch.sh"
source "$REPO_DIR/scripts/menus/initial_setup.sh"
source "$REPO_DIR/scripts/lib/update_components.sh"
source "$REPO_DIR/scripts/lib/update_workflow.sh"
