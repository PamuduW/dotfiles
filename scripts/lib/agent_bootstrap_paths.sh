# shellcheck shell=bash
# agent_bootstrap lives as a sibling of the dotfiles repo (plan5 / plan8).
# Clone target: $(dirname "$DOTFILES_DIR")/agent_bootstrap — never a fixed ~/Dev path.

# Repo root when menus run (DOTFILES_DIR) or when inferred from stowed ~/.bashrc.
dotfiles_repo_root() {
	local resolved dotfiles_root

	if [[ -n "${DOTFILES_DIR:-}" && -d "${DOTFILES_DIR}" ]]; then
		printf '%s\n' "$DOTFILES_DIR"
		return 0
	fi

	if [[ -f "${HOME}/.bashrc" ]]; then
		resolved="$(readlink -f "${HOME}/.bashrc" 2>/dev/null || true)"
		if [[ -n "$resolved" && -f "$resolved" ]]; then
			dotfiles_root="$(dirname "$(dirname "$resolved")")"
			if [[ -d "$dotfiles_root/scripts" && -f "$dotfiles_root/bash/.bashrc" ]]; then
				printf '%s\n' "$dotfiles_root"
				return 0
			fi
		fi
	fi

	return 1
}

# Default clone/install location: immediate parent of dotfiles + agent_bootstrap.
agent_bootstrap_sibling_home() {
	local dotfiles_root="${1:-}"
	local sibling

	if [[ -z "$dotfiles_root" ]]; then
		dotfiles_root="$(dotfiles_repo_root)" || {
			echo "Error: cannot resolve dotfiles repo root (set DOTFILES_DIR or stow bash)." >&2
			return 1
		}
	fi

	sibling="$(dirname "$dotfiles_root")/agent_bootstrap"
	printf '%s\n' "$sibling"
}

# Optional override for non-default layouts; otherwise same as sibling.
agent_bootstrap_clone_home() {
	if [[ -n "${AGENT_BOOTSTRAP_CLONE_HOME:-}" ]]; then
		printf '%s\n' "$AGENT_BOOTSTRAP_CLONE_HOME"
		return 0
	fi
	agent_bootstrap_sibling_home
}

# Installed repo: explicit AGENT_BOOTSTRAP_HOME, else sibling when install.sh exists.
resolve_agent_bootstrap_home() {
	local sibling

	if [[ -n "${AGENT_BOOTSTRAP_HOME:-}" && -x "${AGENT_BOOTSTRAP_HOME}/install.sh" ]]; then
		printf '%s\n' "$AGENT_BOOTSTRAP_HOME"
		return 0
	fi

	sibling="$(agent_bootstrap_sibling_home)" || return 1
	if [[ -x "$sibling/install.sh" ]]; then
		printf '%s\n' "$sibling"
		return 0
	fi
	return 1
}
