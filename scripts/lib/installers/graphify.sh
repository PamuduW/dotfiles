# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"

if ! declare -F graphify_command >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi

check_graphify_cli() {
	dotfiles_catalog_check "graphify_cli" "Graphify CLI"
}

upgrade_graphify_cli() {
	dotfiles_catalog_upgrade "graphify_cli" || return $?
	if [[ "${UPGRADE_STEP_ACTIVE_RESULT:-}" == updated ]]; then
		printf "Graphify CLI changed; run 'agentbot update' to refresh its skill.\n"
	fi
}

ensure_graphify_uv() {
	dotfiles_catalog_install "uv"
}

install_graphify_cli() {
	dotfiles_catalog_install "graphify_cli"
}
