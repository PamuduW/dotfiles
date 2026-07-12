# shellcheck shell=bash

resolve_dotfiles_cmd() {
	if [[ -x "$DOTFILES_DIR/bin/bin/dotfiles" ]]; then
		printf '%s\n' "$DOTFILES_DIR/bin/bin/dotfiles"
		return 0
	fi
	local cmd
	cmd="$(command -v dotfiles 2>/dev/null || true)"
	if [[ -n "$cmd" ]]; then
		printf '%s\n' "$cmd"
		return 0
	fi
	return 1
}
