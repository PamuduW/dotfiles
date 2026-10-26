# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"
# Tool discovery and version reading are shared with the status probes.
if ! declare -F tool_resolve >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/tool_resolve.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tool_resolve.sh"
fi

# --- Cursor CLI ---
cursor_installed_version() {
	local binary raw
	binary="$(tool_resolve 'agent cursor-agent')" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
}

cursor_is_installed() {
	tool_resolve 'agent cursor-agent' >/dev/null 2>&1
}

# Cursor publishes no queryable "latest" version, so this probe never reports an
# upgrade and always returns nonzero (no upgrade available).
check_cursor_cli() {
	dotfiles_catalog_check cursor_cli "Cursor CLI"
}

upgrade_cursor_cli() {
	dotfiles_catalog_upgrade cursor_cli
}

# --- Codex CLI ---
CODEX_RELEASE_VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-alpha(\.[0-9]+){0,2}|-beta(\.[0-9]+)?)?$'

codex_release_version_is_valid() {
	[[ "$1" =~ $CODEX_RELEASE_VERSION_REGEX ]]
}

codex_installed_version() {
	local binary raw
	binary="$(codex_visible_install_path)"
	codex_path_is_standalone_owned "$binary" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
}

codex_version_number() {
	local line word
	local -a words=()
	line="${1:-}"
	line="${line%%$'\n'*}"
	read -r -a words <<<"$line"
	for word in "${words[@]}"; do
		if codex_release_version_is_valid "$word"; then
			printf '%s\n' "$word"
			return 0
		fi
	done
	return 1
}

codex_latest_channel_json() {
	curl -fsSL --proto '=https' --tlsv1.2 'https://releases.openai.com/codex/channels/latest'
}

codex_available_version() {
	dotfiles_catalog_begin && dotfiles_catalog_get codex_cli version
}

codex_semver_compare() {
	local left="$1" right="$2" left_core right_core left_pre='' right_pre=''
	local -a left_parts right_parts left_ids right_ids
	local i left_number right_number left_rank right_rank
	codex_release_version_is_valid "$left" && codex_release_version_is_valid "$right" || return 2

	left_core="${left%%-*}"
	right_core="${right%%-*}"
	[[ "$left" == *-* ]] && left_pre="${left#*-}"
	[[ "$right" == *-* ]] && right_pre="${right#*-}"
	IFS='.' read -r -a left_parts <<<"$left_core"
	IFS='.' read -r -a right_parts <<<"$right_core"
	for i in 0 1 2; do
		left_number=$((10#${left_parts[$i]}))
		right_number=$((10#${right_parts[$i]}))
		if ((left_number < right_number)); then
			printf '%s\n' -1
			return 0
		fi
		if ((left_number > right_number)); then
			printf '%s\n' 1
			return 0
		fi
	done

	if [[ -z "$left_pre" && -z "$right_pre" ]]; then
		printf '%s\n' 0
		return 0
	fi
	if [[ -z "$left_pre" ]]; then
		printf '%s\n' 1
		return 0
	fi
	if [[ -z "$right_pre" ]]; then
		printf '%s\n' -1
		return 0
	fi
	IFS='.' read -r -a left_ids <<<"$left_pre"
	IFS='.' read -r -a right_ids <<<"$right_pre"
	[[ "${left_ids[0]}" == alpha ]] && left_rank=0 || left_rank=1
	[[ "${right_ids[0]}" == alpha ]] && right_rank=0 || right_rank=1
	if ((left_rank < right_rank)); then
		printf '%s\n' -1
		return 0
	fi
	if ((left_rank > right_rank)); then
		printf '%s\n' 1
		return 0
	fi
	for ((i = 1; i < ${#left_ids[@]} && i < ${#right_ids[@]}; i++)); do
		left_number=$((10#${left_ids[$i]}))
		right_number=$((10#${right_ids[$i]}))
		if ((left_number < right_number)); then
			printf '%s\n' -1
			return 0
		fi
		if ((left_number > right_number)); then
			printf '%s\n' 1
			return 0
		fi
	done
	if ((${#left_ids[@]} < ${#right_ids[@]})); then
		printf '%s\n' -1
		return 0
	fi
	if ((${#left_ids[@]} > ${#right_ids[@]})); then
		printf '%s\n' 1
		return 0
	fi
	printf '%s\n' 0
}

check_codex_cli() {
	dotfiles_catalog_check codex_cli "Codex CLI"
}

upgrade_codex_cli() {
	dotfiles_catalog_upgrade codex_cli
}

# --- Claude CLI ---
claude_installed_version() {
	local binary raw
	binary="$(tool_resolve claude)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	printf '%s\n' "${raw%%$'\n'*}"
}

check_claude_cli() {
	dotfiles_catalog_check claude_cli "Claude CLI"
}

upgrade_claude_cli() {
	dotfiles_catalog_upgrade claude_cli
}

# --- lazygit ---
lazygit_installed_version() {
	local binary raw version
	binary="$(tool_resolve lazygit)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo installed
		return
	}
	version="$(grep -oP 'version=\K[0-9.]+' <<<"$raw" | head -n1 || true)"
	printf '%s\n' "${version:-${raw%%$'\n'*}}"
}

check_lazygit() {
	dotfiles_catalog_check lazygit "lazygit"
}

upgrade_lazygit() {
	dotfiles_catalog_upgrade lazygit
}

# --- lazydocker ---
lazydocker_installed_version() {
	local binary raw version
	binary="$(tool_resolve lazydocker)" || {
		echo "$NOT_INSTALLED"
		return
	}
	raw="$(tool_version_raw "$binary" --version)" || {
		echo "$NOT_INSTALLED"
		return
	}
	version="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$raw" | head -n1 || true)"
	printf '%s\n' "${version:-$NOT_INSTALLED}"
}

check_lazydocker() {
	dotfiles_catalog_check lazydocker "lazydocker"
}

upgrade_lazydocker() {
	dotfiles_catalog_upgrade lazydocker
}

# --- Ubuntu Sans Mono fonts — opt-in ---
ubuntu_sans_mono_installed_version() {
	local font_dir="$HOME/.local/share/fonts/ubuntu-sans-mono"
	if [[ -d "$font_dir" ]] && compgen -G "${font_dir}/*.ttf" >/dev/null 2>&1; then
		if [[ -f "${font_dir}/.version" ]]; then
			cat "${font_dir}/.version"
		else
			echo "installed"
		fi
	else
		echo "$NOT_INSTALLED"
	fi
}

ubuntu_sans_mono_latest_version() {
	dotfiles_catalog_begin && dotfiles_catalog_get ubuntu_sans_mono_fonts version
}

check_ubuntu_sans_mono() {
	dotfiles_catalog_check ubuntu_sans_mono_fonts "Ubuntu Sans Mono fonts"
}

upgrade_ubuntu_sans_mono() {
	dotfiles_catalog_upgrade ubuntu_sans_mono_fonts
}
