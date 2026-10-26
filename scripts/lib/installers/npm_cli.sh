# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"
# markdownlint-cli2, CSpell and Mermaid CLI: the latest npm release of each,
# installed with its dependencies into its own prefix under
# ~/.local/share/dotfiles-npm. The rows are in NPM_CLI_TOOLS
# (managed_tool_state.sh).
#
# npm checks every downloaded tarball against the registry's integrity hash.
# Package install scripts never run (--ignore-scripts): none of the three
# needs one, and Puppeteer's would download a second Chrome. Mermaid CLI uses
# the Chrome headless shell Dotfiles installs instead.
#
# Dotfiles owns the executable and nothing else: no .markdownlint-cli2 file,
# no CSpell dictionary or configuration, no Mermaid configuration. Those belong
# to the repository that uses the tool.

if ! declare -F npm_cli_command >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi

npm_cli_latest_version() {
	local package version
	package="$(npm_cli_field "$1" package)" || return 1
	version="$(npm view "$package" version 2>/dev/null)" || return 1
	[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || return 1
	printf '%s\n' "$version"
}

# The wrapper ~/.local/bin links to. Mermaid CLI's gets the Chrome headless
# shell unless the caller chose a browser.
_npm_cli_write_wrapper() {
	local key="$1" prefix="$2" binary
	binary="$(npm_cli_field "$key" binary)"
	install -d -m 0755 "$prefix/bin"
	{
		printf '%s\n' '#!/usr/bin/env bash'
		if [[ "$key" == mermaid_cli ]]; then
			# shellcheck disable=SC2016  # Expanded when the wrapper runs.
			printf '%s\n' 'if [[ -z "${PUPPETEER_EXECUTABLE_PATH:-}" && -x "$HOME/.local/bin/chrome-headless-shell" ]]; then' \
				'	export PUPPETEER_EXECUTABLE_PATH="$HOME/.local/bin/chrome-headless-shell"' 'fi'
		fi
		printf 'exec "%s/node_modules/.bin/%s" "$@"\n' "$(npm_cli_root "$key")" "$binary"
	} >"$prefix/bin/$binary"
	chmod 0755 "$prefix/bin/$binary"
}

npm_cli_install_release() {
	local key="$1" version="$2"
	local label package binary root link stamp staging previous reported
	label="$(npm_cli_field "$key" label)" || return 1
	package="$(npm_cli_field "$key" package)"
	binary="$(npm_cli_field "$key" binary)"
	root="$(npm_cli_root "$key")"
	link="$(npm_cli_install_path "$key")"
	stamp="$(npm_cli_management_stamp "$key")"

	command -v npm >/dev/null 2>&1 || {
		echo "  npm is required to install ${label}; install Node.js first." >&2
		return 1
	}

	# Staged beside the final directory so the swap is a rename on one
	# filesystem. The wrapper names the final path, so the staged copy is
	# checked through node_modules directly.
	install -d -m 0755 "$(dirname -- "$root")" "$(dirname -- "$link")" "$(dirname -- "$stamp")"
	staging="$(mktemp -d "${root}.staging.XXXXXX")" || return 1
	trap '[[ -n "${staging:-}" ]] && rm -rf -- "$staging"' RETURN
	log_step "Install ${label} ${version}"
	if ! PUPPETEER_SKIP_DOWNLOAD=1 npm install --prefix "$staging" --no-fund --no-audit \
		--ignore-scripts --omit=dev "${package}@${version}" >/dev/null 2>&1; then
		echo "  npm could not install ${package}@${version}." >&2
		return 1
	fi
	[[ -x "$staging/node_modules/.bin/$binary" ]] || {
		echo "  ${package}@${version} did not provide a ${binary} command." >&2
		return 1
	}
	reported="$("$staging/node_modules/.bin/$binary" --version 2>/dev/null | head -n1 || true)"
	if [[ "$reported" != *"$version"* ]]; then
		echo "  Installed ${label} did not report ${version}." >&2
		return 1
	fi
	_npm_cli_write_wrapper "$key" "$staging"

	previous="${root}.previous.$$"
	if [[ -e "$root" ]]; then
		mv -- "$root" "$previous" || return $?
	fi
	if ! mv -- "$staging" "$root"; then
		[[ -e "$previous" ]] && mv -- "$previous" "$root"
		return 1
	fi
	ln -sfn -- "$root/bin/$binary" "$link" || return $?
	printf '%s\n' "$version" >"${stamp}.$$" || return $?
	mv -f -- "${stamp}.$$" "$stamp" || return $?
	[[ -e "$previous" ]] && rm -rf -- "$previous"
	trap - RETURN
	log_ok "${label} ${version} installed at ${link}"
}

# Installs the latest release unless the one installed is already as new.
# With force, reinstalls it even then.
npm_cli_sync_latest() {
	dotfiles_catalog_install "$1"
}

install_npm_cli() {
	dotfiles_catalog_install "$1"
}

check_npm_cli() {
	dotfiles_catalog_check "$1" "$(npm_cli_field "$1" label)"
}

upgrade_npm_cli() {
	dotfiles_catalog_upgrade "$1"
}

# The per-component names the registry, probes and update steps call.
check_markdownlint_cli2() { check_npm_cli markdownlint_cli2; }
check_cspell() { check_npm_cli cspell; }
check_mermaid_cli() { check_npm_cli mermaid_cli; }
upgrade_markdownlint_cli2() { upgrade_npm_cli markdownlint_cli2; }
upgrade_cspell() { upgrade_npm_cli cspell; }
upgrade_mermaid_cli() { upgrade_npm_cli mermaid_cli; }
