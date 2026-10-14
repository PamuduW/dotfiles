# shellcheck shell=bash
# Read-only local state shared by component probes and managed CLI installers.

codex_standalone_root() {
	printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/packages/standalone"
}

codex_visible_install_path() {
	printf '%s\n' "${CODEX_INSTALL_DIR:-$HOME/.local/bin}/codex"
}

codex_active_command() {
	command -v codex 2>/dev/null
}

codex_path_is_standalone_owned() {
	local candidate="$1" candidate_path standalone_root
	[[ -f "$candidate" && -x "$candidate" ]] || return 1
	candidate_path="$(readlink -f -- "$candidate" 2>/dev/null)" || return 1
	standalone_root="$(readlink -f -- "$(codex_standalone_root)" 2>/dev/null)" || return 1
	[[ "$candidate_path" == "$standalone_root"/* ]]
}

codex_standalone_is_installed() {
	codex_path_is_standalone_owned "$(codex_visible_install_path)"
}

codex_cli_is_standalone_active() {
	local active_command active_path visible_path
	active_command="$(codex_active_command)" || return 1
	codex_path_is_standalone_owned "$active_command" || return 1
	active_path="$(readlink -f -- "$active_command" 2>/dev/null)" || return 1
	visible_path="$(readlink -f -- "$(codex_visible_install_path)" 2>/dev/null)" || return 1
	[[ "$active_path" == "$visible_path" ]]
}

codex_cli_install_state() {
	if codex_standalone_is_installed; then
		if codex_cli_is_standalone_active; then
			printf '%s\n' standalone
		elif ! codex_active_command >/dev/null 2>&1; then
			# Installed at the managed path with nothing else claiming the name.
			# The directory is simply not on PATH in this session yet, which is
			# the normal state right after a fresh install. Calling that
			# "shadowed" sent it into the npm migration path, which then failed
			# because there was no npm Codex to migrate.
			printf '%s\n' standalone-not-on-path
		else
			printf '%s\n' standalone-shadowed
		fi
	elif codex_active_command >/dev/null; then
		printf '%s\n' external
	else
		printf '%s\n' absent
	fi
}

codex_collect_nvm_commands() {
	local output_name="$1" root="${NVM_DIR:-$HOME/.nvm}" command_path
	local -n output_ref="$output_name"
	output_ref=()
	for command_path in "$root"/versions/node/*/bin/codex; do
		[[ -e "$command_path" ]] || continue
		output_ref+=("$command_path")
	done
}

codex_collect_nvm_packages() {
	local output_name="$1" root="${NVM_DIR:-$HOME/.nvm}" package_dir
	local -n output_ref="$output_name"
	output_ref=()
	for package_dir in "$root"/versions/node/*/lib/node_modules/@openai/codex; do
		[[ -e "$package_dir" ]] || continue
		output_ref+=("$package_dir")
	done
}

codex_nvm_command_is_managed_package() {
	local command_path="$1" tree package_dir canonical_command canonical_tree canonical_package
	tree="${command_path%/bin/codex}"
	package_dir="$tree/lib/node_modules/@openai/codex"
	[[ -x "$command_path" && -x "$tree/bin/npm" && -f "$package_dir/package.json" ]] || return 1
	canonical_command="$(readlink -f -- "$command_path" 2>/dev/null)" || return 1
	canonical_tree="$(readlink -f -- "$tree" 2>/dev/null)" || return 1
	canonical_package="$(readlink -f -- "$package_dir" 2>/dev/null)" || return 1
	[[ "$canonical_package" == "$canonical_tree"/* && "$canonical_command" == "$canonical_package"/* ]]
}

codex_nvm_migration_inventory() {
	local output_name="$1" active canonical_active command_path canonical_command active_matched=0
	local -a found_commands=() found_packages=()
	codex_collect_nvm_commands found_commands
	((${#found_commands[@]} > 0)) || return 1
	codex_collect_nvm_packages found_packages
	((${#found_packages[@]} == ${#found_commands[@]})) || return 1
	active="$(codex_active_command)" || return 1
	canonical_active="$(readlink -f -- "$active" 2>/dev/null)" || return 1
	for command_path in "${found_commands[@]}"; do
		codex_nvm_command_is_managed_package "$command_path" || return 1
		canonical_command="$(readlink -f -- "$command_path" 2>/dev/null)" || return 1
		[[ "$canonical_active" == "$canonical_command" ]] && active_matched=1
	done
	[[ "$active_matched" -eq 1 ]] || return 1
	local -n output_ref="$output_name"
	output_ref=("${found_commands[@]}")
}

graphify_uv_command() {
	if command -v uv >/dev/null 2>&1; then
		command -v uv
	elif [[ -x "$HOME/.local/bin/uv" ]]; then
		printf '%s\n' "$HOME/.local/bin/uv"
	else
		return 1
	fi
}

graphify_command() {
	if command -v graphify >/dev/null 2>&1; then
		command -v graphify
	elif [[ -x "$HOME/.local/bin/graphify" ]]; then
		printf '%s\n' "$HOME/.local/bin/graphify"
	else
		return 1
	fi
}

graphify_cli_is_uv_owned() {
	local uv_cmd tool_list
	uv_cmd="$(graphify_uv_command)" || return 1
	tool_list="$("$uv_cmd" tool list 2>/dev/null)" || return 1
	grep -Eq '(^|[[:space:]])graphifyy([[:space:]]|$)' <<<"$tool_list"
}

graphify_installed_version() {
	local graphify_cmd version
	if graphify_cmd="$(graphify_command 2>/dev/null)"; then
		version="$("$graphify_cmd" --version 2>/dev/null | head -n1 || true)"
		printf '%s\n' "${version:-installed}"
	else
		printf '%s\n' 'not installed'
	fi
}

boost_install_path() {
	printf '%s\n' "$HOME/.local/bin/boost"
}

boost_management_stamp() {
	printf '%s\n' "$HOME/.local/share/dotfiles/boost-cli.version"
}

boost_command() {
	if command -v boost >/dev/null 2>&1; then
		command -v boost
	elif [[ -x "$HOME/.local/bin/boost" ]]; then
		printf '%s\n' "$HOME/.local/bin/boost"
	else
		return 1
	fi
}

boost_installed_version() {
	local boost_cmd version
	boost_cmd="$(boost_command 2>/dev/null)" || {
		printf '%s\n' 'not installed'
		return 0
	}
	version="$("$boost_cmd" version 2>/dev/null | head -n1 || true)"
	printf '%s\n' "${version:-installed}"
}

boost_cli_is_dotfiles_owned() {
	local command_path install_path stamp
	command_path="$(boost_command 2>/dev/null)" || return 1
	install_path="$(boost_install_path)"
	stamp="$(boost_management_stamp)"
	[[ "$command_path" == "$install_path" ]] || return 1
	[[ -f "$stamp" && ! -L "$stamp" ]] || return 1
	[[ "$(<"$stamp")" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]
}

boost_installed_tag() {
	local version
	version="$(boost_installed_version)"
	version="$(grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?' <<<"$version" | head -n1)"
	[[ -n "$version" ]] || return 1
	[[ "$version" == v* ]] || version="v$version"
	printf '%s\n' "$version"
}

# --- Release CLIs: single-binary tools installed from verified GitHub releases ---
#
# Kubeconform, TFLint and zizmor (roadmap item 9), Vale and yt-dlp (item 11),
# and Trivy and Infracost (item 12) share one lifecycle: the
# latest GitHub release, verified against the SHA-256 digest GitHub publishes
# for the asset, installed to ~/.local/bin with an ownership stamp, exactly as
# Boost is. Only this table differs between them.
#
# Row format: key|label|repository|asset|archive|binary|version-args
#   asset    {arch} is amd64/arm64, {triple} is x86_64/aarch64, {arch_word} is
#            64-bit/arm64, {arch_bits} is 64bit/ARM64, {aarch64_suffix} is
#            empty/_aarch64, and {version} is the release tag without its v
#   archive  tar (gzip), zip, or raw (the asset is the binary itself)
RELEASE_CLI_TOOLS=(
	'kubeconform|Kubeconform|yannh/kubeconform|kubeconform-linux-{arch}.tar.gz|tar|kubeconform|-v'
	'tflint|TFLint|terraform-linters/tflint|tflint_linux_{arch}.zip|zip|tflint|--version'
	'zizmor|zizmor|zizmorcore/zizmor|zizmor-{triple}-unknown-linux-gnu.tar.gz|tar|zizmor|--version'
	'vale|Vale|errata-ai/vale|vale_{version}_Linux_{arch_word}.tar.gz|tar|vale|--version'
	'yt_dlp|yt-dlp|yt-dlp/yt-dlp|yt-dlp_linux{aarch64_suffix}|raw|yt-dlp|--version'
	'trivy|Trivy|aquasecurity/trivy|trivy_{version}_Linux-{arch_bits}.tar.gz|tar|trivy|--version'
	'infracost|Infracost|infracost/cli|infracost-linux-{arch}.tar.gz|tar|infracost|--version'
)

# release_cli_field <key> <label|repository|asset|archive|binary|version-args>
release_cli_field() {
	local key="$1" field="$2" row index
	case "$field" in
	label) index=1 ;; repository) index=2 ;; asset) index=3 ;;
	archive) index=4 ;; binary) index=5 ;; version-args) index=6 ;;
	*) return 1 ;;
	esac
	for row in "${RELEASE_CLI_TOOLS[@]}"; do
		[[ "${row%%|*}" == "$key" ]] || continue
		IFS='|' read -r -a _release_cli_row <<<"$row"
		printf '%s\n' "${_release_cli_row[$index]}"
		return 0
	done
	return 1
}

release_cli_install_path() {
	printf '%s\n' "$HOME/.local/bin/$(release_cli_field "$1" binary)"
}

release_cli_management_stamp() {
	printf '%s\n' "$HOME/.local/share/dotfiles/$1.version"
}

release_cli_command() {
	local binary
	binary="$(release_cli_field "$1" binary)" || return 1
	if command -v "$binary" >/dev/null 2>&1; then
		command -v "$binary"
	elif [[ -x "$HOME/.local/bin/$binary" ]]; then
		printf '%s\n' "$HOME/.local/bin/$binary"
	else
		return 1
	fi
}

# The version as v1.2.3, or nothing when the binary is missing or says no
# version. Every one of them prints its version on the first line.
release_cli_installed_tag() {
	local command_path version
	local -a version_argv=()
	command_path="$(release_cli_command "$1" 2>/dev/null)" || return 1
	read -r -a version_argv <<<"$(release_cli_field "$1" version-args)"
	version="$("$command_path" "${version_argv[@]}" 2>/dev/null | head -n1 || true)"
	version="$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?' <<<"$version" | head -n1)"
	[[ -n "$version" ]] || return 1
	printf 'v%s\n' "${version#v}"
}

release_cli_installed_version() {
	release_cli_command "$1" >/dev/null 2>&1 || {
		printf '%s\n' 'not installed'
		return 0
	}
	release_cli_installed_tag "$1" 2>/dev/null || printf '%s\n' installed
}

release_cli_is_dotfiles_owned() {
	local command_path stamp
	command_path="$(release_cli_command "$1" 2>/dev/null)" || return 1
	[[ "$command_path" == "$(release_cli_install_path "$1")" ]] || return 1
	stamp="$(release_cli_management_stamp "$1")"
	[[ -f "$stamp" && ! -L "$stamp" ]] || return 1
	[[ "$(<"$stamp")" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]
}

# --- Chrome headless shell: the browser Archify's browser gate drives ---
#
# Chrome for Testing's headless shell, the latest Stable build, unpacked into
# its own directory with a link in ~/.local/bin and an ownership stamp. The
# directory holds the whole build: the shell loads its libraries and resources
# from beside itself.
chrome_headless_root() {
	printf '%s\n' "$HOME/.local/share/chrome-headless-shell"
}

chrome_headless_install_path() {
	printf '%s\n' "$HOME/.local/bin/chrome-headless-shell"
}

chrome_headless_management_stamp() {
	printf '%s\n' "$HOME/.local/share/dotfiles/chrome_headless.version"
}

chrome_headless_command() {
	if command -v chrome-headless-shell >/dev/null 2>&1; then
		command -v chrome-headless-shell
	elif [[ -x "$(chrome_headless_install_path)" ]]; then
		chrome_headless_install_path
	else
		return 1
	fi
}

# The four-part Chrome version, or nothing when the shell is missing or does
# not start (a missing system library fails here).
chrome_headless_installed_tag() {
	local command_path version
	command_path="$(chrome_headless_command 2>/dev/null)" || return 1
	version="$("$command_path" --version 2>/dev/null | head -n1 || true)"
	version="$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' <<<"$version" | head -n1)"
	[[ -n "$version" ]] || return 1
	printf '%s\n' "$version"
}

chrome_headless_installed_version() {
	chrome_headless_command >/dev/null 2>&1 || {
		printf '%s\n' 'not installed'
		return 0
	}
	chrome_headless_installed_tag 2>/dev/null || printf '%s\n' installed
}

chrome_headless_is_dotfiles_owned() {
	local command_path target root stamp
	command_path="$(chrome_headless_command 2>/dev/null)" || return 1
	[[ "$command_path" == "$(chrome_headless_install_path)" && -L "$command_path" ]] || return 1
	target="$(readlink -f -- "$command_path" 2>/dev/null)" || return 1
	root="$(readlink -f -- "$(chrome_headless_root)" 2>/dev/null)" || return 1
	[[ "$target" == "$root"/* ]] || return 1
	stamp="$(chrome_headless_management_stamp)"
	[[ -f "$stamp" && ! -L "$stamp" ]] || return 1
	[[ "$(<"$stamp")" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# --- npm CLIs: Node command-line tools, each in its own Dotfiles prefix ---
#
# markdownlint-cli2, CSpell and Mermaid CLI (roadmap item 11). Each is the
# latest npm release, installed with its dependencies into its own prefix
# under ~/.local/share/dotfiles-npm, with a wrapper there that ~/.local/bin
# links to, and an ownership stamp. nvm's global folder is not used: it
# changes with every Node version.
#
# Row format: key|label|package|binary
NPM_CLI_TOOLS=(
	'markdownlint_cli2|markdownlint-cli2|markdownlint-cli2|markdownlint-cli2'
	'cspell|CSpell|cspell|cspell'
	'mermaid_cli|Mermaid CLI|@mermaid-js/mermaid-cli|mmdc'
)

# npm_cli_field <key> <label|package|binary>
npm_cli_field() {
	local key="$1" field="$2" row index
	case "$field" in
	label) index=1 ;; package) index=2 ;; binary) index=3 ;;
	*) return 1 ;;
	esac
	for row in "${NPM_CLI_TOOLS[@]}"; do
		[[ "${row%%|*}" == "$key" ]] || continue
		IFS='|' read -r -a _npm_cli_row <<<"$row"
		printf '%s\n' "${_npm_cli_row[$index]}"
		return 0
	done
	return 1
}

npm_cli_root() {
	printf '%s\n' "$HOME/.local/share/dotfiles-npm/$1"
}

npm_cli_install_path() {
	printf '%s\n' "$HOME/.local/bin/$(npm_cli_field "$1" binary)"
}

npm_cli_management_stamp() {
	printf '%s\n' "$HOME/.local/share/dotfiles/$1.version"
}

npm_cli_command() {
	local binary
	binary="$(npm_cli_field "$1" binary)" || return 1
	if command -v "$binary" >/dev/null 2>&1; then
		command -v "$binary"
	elif [[ -x "$HOME/.local/bin/$binary" ]]; then
		printf '%s\n' "$HOME/.local/bin/$binary"
	else
		return 1
	fi
}

# The version as 1.2.3, or nothing when the tool is missing or says no version.
# Each prints its version on the first line.
npm_cli_installed_tag() {
	local command_path version
	command_path="$(npm_cli_command "$1" 2>/dev/null)" || return 1
	version="$("$command_path" --version 2>/dev/null | head -n1 || true)"
	version="$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?' <<<"$version" | head -n1)"
	[[ -n "$version" ]] || return 1
	printf '%s\n' "$version"
}

npm_cli_installed_version() {
	npm_cli_command "$1" >/dev/null 2>&1 || {
		printf '%s\n' 'not installed'
		return 0
	}
	npm_cli_installed_tag "$1" 2>/dev/null || printf '%s\n' installed
}

npm_cli_is_dotfiles_owned() {
	local command_path target root stamp
	command_path="$(npm_cli_command "$1" 2>/dev/null)" || return 1
	[[ "$command_path" == "$(npm_cli_install_path "$1")" && -L "$command_path" ]] || return 1
	target="$(readlink -f -- "$command_path" 2>/dev/null)" || return 1
	root="$(readlink -f -- "$(npm_cli_root "$1")" 2>/dev/null)" || return 1
	[[ "$target" == "$root"/* ]] || return 1
	stamp="$(npm_cli_management_stamp "$1")"
	[[ -f "$stamp" && ! -L "$stamp" ]] || return 1
	[[ "$(<"$stamp")" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]
}
