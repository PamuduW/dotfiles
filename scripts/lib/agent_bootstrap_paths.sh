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

# Canonical location: immediate parent of dotfiles + agent_bootstrap.
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

# Where clone/update should target.
agent_bootstrap_clone_home() {
	if [[ -n "${AGENT_BOOTSTRAP_CLONE_HOME:-}" ]]; then
		printf '%s\n' "$AGENT_BOOTSTRAP_CLONE_HOME"
		return 0
	fi
	agent_bootstrap_sibling_home
}

# Installed repo: only the canonical sibling (ignore stale AGENT_BOOTSTRAP_HOME elsewhere).
resolve_agent_bootstrap_home() {
	local canonical

	canonical="$(agent_bootstrap_sibling_home)" || return 1

	if [[ -n "${AGENT_BOOTSTRAP_HOME:-}" && "$AGENT_BOOTSTRAP_HOME" != "$canonical" ]]; then
		if [[ "${AGENT_BOOTSTRAP_ALLOW_OVERRIDE:-}" == 1 && -x "${AGENT_BOOTSTRAP_HOME}/install.sh" ]]; then
			printf '%s\n' "$AGENT_BOOTSTRAP_HOME"
			return 0
		fi
	fi

	if [[ -x "$canonical/install.sh" ]]; then
		printf '%s\n' "$canonical"
		return 0
	fi
	return 1
}

# Allowed clone URLs when AGENT_BOOTSTRAP_REPO_URL is overridden (supply-chain guard).
agent_bootstrap_repo_url_allowed() {
	local url="${1:-}"

	if [[ "${AGENT_BOOTSTRAP_REPO_URL_ALLOW_ANY:-}" == 1 ]]; then
		return 0
	fi

	case "$url" in
	git@github.com:PamuduW/agent_bootstrap.git | git@github.com:PamuduW/agent_bootstrap | https://github.com/PamuduW/agent_bootstrap.git | https://github.com/PamuduW/agent_bootstrap)
		return 0
		;;
	esac

	echo "Warning: AGENT_BOOTSTRAP_REPO_URL is not on the allowlist: ${url}" >&2
	echo "  Allowed: git@github.com:PamuduW/agent_bootstrap.git" >&2
	echo "         or https://github.com/PamuduW/agent_bootstrap.git" >&2
	echo "  Set AGENT_BOOTSTRAP_REPO_URL_ALLOW_ANY=1 to bypass (unsafe)." >&2
	return 1
}

# Re-export AGENT_BOOTSTRAP_HOME only when install.sh exists at the canonical sibling.
sync_agent_bootstrap_home_env() {
	local resolved

	resolved="$(resolve_agent_bootstrap_home 2>/dev/null || true)"
	if [[ -n "$resolved" ]]; then
		export AGENT_BOOTSTRAP_HOME="$resolved"
		return 0
	fi

	unset AGENT_BOOTSTRAP_HOME
	return 1
}
