# shellcheck shell=bash
# shellcheck disable=SC2034  # Namerefs are written through, not read, in this file.
# Per-component status probes (_comp_probe_<id>).

if ! declare -F codex_cli_install_state >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi

_comp_probe_capture() {
	local output_name="$1" timeout_seconds="$2" captured='' rc
	shift 2
	if captured="$(timeout --kill-after=0.2 "$timeout_seconds" "$@" 2>/dev/null)"; then
		rc=0
	else
		rc=$?
	fi
	[[ "$rc" -eq 137 ]] && rc=124
	captured="${captured%%$'\n'*}"
	printf -v "$output_name" '%s' "$captured"
	return "$rc"
}

_install_short_label() {
	local label="$1"
	label="${label%%(*}"
	label="${label%% }"
	printf '%.22s' "$label"
}

# collect_component_status_rows <array-name> [enabled-only]
# Pass "true" as the second argument to include only components selected in
# COMP_ON. Both status and the install summary go through here so neither can
# drift back to a serial re-probe.
collect_component_status_rows() {
	local output_name="$1" enabled_only="${2:-false}"
	local -n output_rows="$output_name"
	mapfile -t output_rows < <(_collect_component_status_rows_stream "$enabled_only")
}

_collect_component_status_rows_stream() (
	local enabled_only="${1:-false}"
	local probe_dir i key label probe result detail pid
	local -a pids=() indexes=()
	probe_dir="$(mktemp -d)" || return 1
	trap 'rm -r -- "$probe_dir"' EXIT

	for i in "${!COMP_KEYS[@]}"; do
		key="${COMP_KEYS[$i]}"
		[[ "$enabled_only" == true ]] && { is_on "$key" || continue; }
		indexes+=("$i")
		(
			# Note the deliberate difference from run_probes_parallel: a
			# component probe's nonzero exit means the probe failed, whereas an
			# update check returns nonzero to mean "no upgrade available". Do
			# not unify these without changing the probe contract.
			if probe="$(comp_probe "$key")"; then
				probe="${probe%%$'\n'*}"
				printf '%s\n' "${probe:-check|probe returned no result}"
			else
				printf 'check|probe failed\n'
			fi
		) >"$probe_dir/$i" &
		pids+=("$!")
	done

	for pid in "${pids[@]}"; do
		wait "$pid" || true
	done

	for i in "${indexes[@]}"; do
		label="$(_install_short_label "${COMP_LABELS[$i]}")"
		probe="$(<"$probe_dir/$i")"
		IFS='|' read -r result detail <<<"$probe"
		printf '%s|%s|%s\n' "$label" "$detail" "$result"
	done
)

# --- Generic "is this CLI installed, and at what version?" probe ---
#
# Nine components differ only in the binary name, an optional ~/.local/bin
# fallback, whether nvm must be loaded first, the version arguments, and an
# optional version-extraction regex. _comp_probe_version holds that shape once;
# _COMP_VERSION_PROBES is the data. The two label columns are separate because
# the original probes worded "not on PATH" and "probe timed out" differently.
#
# Row format:
#   id|missing-label|timeout-label|commands|version-args|extract-regex|prefix|preload
#     commands      space-separated; first found on PATH wins, then
#                   ~/.local/bin/<name> for each, in order
#     version-args  space-separated (e.g. "--version")
#     extract       optional ERE; first match becomes the reported version
#     prefix        optional literal prefix on the reported version
#     preload       "nvm" to source nvm.sh before resolving, else empty
_COMP_VERSION_PROBES=(
	'powershell|pwsh|powershell|pwsh|--version|||'
	'nodejs|node|node|node|--version||node |nvm'
	'direnv|direnv|direnv|direnv|version|||'
	'docker|docker|docker|docker|--version|||'
	'lazygit|lazygit|lazygit|lazygit|--version|[0-9]+\.[0-9]+\.[0-9]+||'
	'lazydocker|lazydocker|lazydocker|lazydocker|--version|[0-9]+\.[0-9]+\.[0-9]+||'
	'cursor_cli|cursor/agent|cursor cli|agent cursor|--version|||'
	'claude_cli|claude|claude cli|claude|--version|||'
	'copilot_cli|copilot|copilot cli|copilot|--version|||'
)

# Resolution is shared with the update checks; see scripts/lib/tool_resolve.sh.
if ! declare -F tool_resolve >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/tool_resolve.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/lib/tool_resolve.sh"
fi
if ! declare -F read_packages_by_tags >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/package_metadata.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/package_metadata.sh"
fi

_comp_probe_version() {
	local missing_label="$1" timeout_label="$2" names="$3"
	local version_args="${4:---version}" extract="${5:-}" prefix="${6:-}" preload="${7:-}"
	local timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	local binary raw='' version rc=0

	if [[ "$preload" == nvm ]]; then
		local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
		# shellcheck source=/dev/null
		[[ -s "${nvm_dir}/nvm.sh" ]] && . "${nvm_dir}/nvm.sh"
	fi

	binary="$(tool_resolve "$names")" || {
		printf 'missing|%s not on PATH\n' "$missing_label"
		return 0
	}

	# shellcheck disable=SC2086  # version_args is an internal word list.
	_comp_probe_capture raw "$timeout_seconds" "$binary" $version_args || rc=$?
	if [[ "$rc" -eq 124 ]]; then
		printf 'check|%s probe timed out\n' "$timeout_label"
		return 0
	fi

	version="$raw"
	if [[ -n "$extract" ]]; then
		version="$(grep -oE "$extract" <<<"$raw" | head -n1 || true)"
	fi
	printf 'installed|%s%s\n' "$prefix" "${version:-$timeout_label}"
}

# Define _comp_probe_<id> for every row in the table.
_comp_probe_register_version_probes() {
	local row id missing_label timeout_label names version_args extract prefix preload
	for row in "${_COMP_VERSION_PROBES[@]}"; do
		IFS='|' read -r id missing_label timeout_label names version_args extract prefix preload <<<"$row"
		eval "_comp_probe_${id}() {
			_comp_probe_version ${missing_label@Q} ${timeout_label@Q} ${names@Q} \
				${version_args@Q} ${extract@Q} ${prefix@Q} ${preload@Q}
		}"
	done
}
_comp_probe_register_version_probes

_comp_probe_git_identity() {
	local name email
	name="$(git config --global user.name 2>/dev/null || true)"
	email="$(git config --global user.email 2>/dev/null || true)"
	if [[ -n "$name" && -n "$email" ]]; then
		printf 'configured|%s <%s>\n' "$name" "$email"
	else
		printf 'missing|not configured\n'
	fi
}

_comp_probe_system_packages() {
	local pkg_file="${PKG_FILE:-${DOTFILES_DIR:-}/packages/packages.txt}"
	local missing=0 checked=0 tags
	local -a packages=()

	if [[ ! -f "$pkg_file" ]]; then
		printf 'missing|packages.txt not found\n'
		return 0
	fi

	tags="$(comp_package_tags system_packages)"
	# shellcheck disable=SC2086 # Component package tags are an internal word list.
	mapfile -t packages < <(PKG_FILE="$pkg_file" read_packages_by_tags $tags)
	checked="${#packages[@]}"

	# One dpkg-query for the whole set instead of one process per package.
	if ((checked > 0)); then
		local installed_count
		installed_count="$(
			dpkg-query -W -f='${Status}\n' "${packages[@]}" 2>/dev/null |
				grep -c '^install ok installed$' || true
		)"
		missing=$((checked - installed_count))
		((missing < 0)) && missing=0
	fi

	if [[ "$checked" -eq 0 ]]; then
		printf 'skipped|no packages listed\n'
	elif [[ "$missing" -eq 0 ]]; then
		printf 'installed|%d apt packages\n' "$checked"
	else
		printf 'missing|%d of %d packages not installed\n' "$missing" "$checked"
	fi
}

_comp_probe_python() {
	command -v python3 >/dev/null 2>&1 || {
		printf 'missing|python3 not on PATH\n'
		return
	}
	python3 -m pip --version >/dev/null 2>&1 || {
		printf 'missing|python3-pip unavailable\n'
		return
	}
	python3 -m venv --help >/dev/null 2>&1 || {
		printf 'missing|python3-venv unavailable\n'
		return
	}
	printf 'installed|python3 pip venv\n'
}

_comp_probe_graphify_cli() {
	local graphify_path ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if graphify_path="$(graphify_command 2>/dev/null)"; then
		_comp_probe_capture ver "$timeout_seconds" "$graphify_path" --version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|graphify cli probe timed out\n'
			return
		fi
		if declare -F graphify_cli_is_uv_owned >/dev/null 2>&1 && graphify_cli_is_uv_owned; then
			printf 'installed|%s (uv)\n' "${ver:-$graphify_path}"
		else
			printf 'installed|%s\n' "${ver:-$graphify_path}"
		fi
	else
		printf 'missing|graphify not on PATH\n'
	fi
}

_comp_probe_boost_cli() {
	local boost_path ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if boost_path="$(boost_command 2>/dev/null)"; then
		_comp_probe_capture ver "$timeout_seconds" "$boost_path" version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|boost cli probe timed out\n'
			return
		fi
		if boost_cli_is_dotfiles_owned; then
			printf 'installed|%s (Dotfiles managed)\n' "${ver:-$boost_path}"
		else
			printf 'installed|%s (external)\n' "${ver:-$boost_path}"
		fi
	else
		printf 'missing|boost not on PATH\n'
	fi
}

_comp_probe_codex_cli() {
	local state codex_path ver='' rc=0 timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	state="$(codex_cli_install_state)" || state=absent
	case "$state" in
	standalone)
		codex_path="$(codex_visible_install_path)"
		_comp_probe_capture ver "$timeout_seconds" "$codex_path" --version || rc=$?
		if [[ "$rc" -eq 124 ]]; then
			printf 'check|codex cli probe timed out\n'
			return
		fi
		printf 'installed|%s (standalone)\n' "${ver:-$codex_path}"
		;;
	external)
		codex_path="$(codex_active_command 2>/dev/null || true)"
		_comp_probe_capture ver "$timeout_seconds" "$codex_path" --version || rc=$?
		if [[ "$rc" -eq 124 ]]; then
			printf 'check|codex cli probe timed out\n'
			return
		fi
		printf 'check|%s (external; migration required)\n' "${ver:-$codex_path}"
		;;
	standalone-shadowed)
		codex_path="$(codex_active_command 2>/dev/null || true)"
		printf 'check|standalone Codex is shadowed by %s\n' "${codex_path:-unknown}"
		;;
	*)
		printf 'missing|codex not on PATH\n'
		;;
	esac
}

_comp_probe_go() {
	local raw ver rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v go >/dev/null 2>&1; then
		_comp_probe_capture raw "$timeout_seconds" go version || rc=$?
		if [[ "${rc:-0}" -eq 124 ]]; then
			printf 'check|go probe timed out\n'
			return
		fi
		ver="$(grep -oE 'go[0-9.]+' <<<"$raw" | head -n1 || true)"
		if [[ -n "$ver" ]]; then
			printf 'installed|%s\n' "$ver"
			return
		fi
	fi
	if command -v asdf >/dev/null 2>&1; then
		rc=0
		_comp_probe_capture raw "$timeout_seconds" asdf current golang || rc=$?
		if [[ "$rc" -eq 124 ]]; then
			printf 'check|go probe timed out\n'
			return
		fi
		ver="$(awk '$1=="golang" {print $2; exit}' <<<"$raw")"
		if [[ -n "$ver" && "$ver" != system ]]; then
			printf 'installed|go%s (asdf)\n' "$ver"
		else
			printf 'missing|asdf has no selected Go version\n'
		fi
	else
		printf 'missing|working Go installation not found\n'
	fi
}

_comp_probe_portainer() {
	local name rc timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	_comp_probe_capture name "$timeout_seconds" docker ps -a \
		--filter 'name=^/portainer$' --format '{{.Names}}' || rc=$?
	if [[ "${rc:-0}" -eq 124 ]]; then
		printf 'check|portainer probe timed out\n'
	elif [[ "$name" == portainer ]]; then
		printf 'installed|container exists (stopped by default)\n'
	else
		printf 'missing|portainer container not found\n'
	fi
}

_comp_probe_monaspace_fonts() {
	local font_dir count ver
	font_dir="$HOME/.local/share/fonts/monaspace"
	if [[ -d "$font_dir" ]] && compgen -G "${font_dir}/*.otf" >/dev/null 2>&1; then
		count="$(find "$font_dir" -maxdepth 1 -name '*.otf' 2>/dev/null | wc -l | tr -d ' ')"
		ver="installed"
		[[ -f "${font_dir}/.version" ]] && ver="$(cat "${font_dir}/.version")"
		printf 'installed|%s (%s fonts)\n' "$ver" "$count"
	else
		printf 'missing|fonts not in ~/.local/share/fonts/monaspace\n'
	fi
}

_comp_probe_ssh_key() {
	if [[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]]; then
		printf 'installed|~/.ssh key present\n'
	else
		printf 'missing|no default key found\n'
	fi
}

_comp_probe_dotfiles() {
	local repo_dir="${DOTFILES_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)}"
	local target expected missing=0
	while IFS='|' read -r target expected; do
		if [[ ! -L "$target" || "$(readlink -f "$target" 2>/dev/null || true)" != "$expected" ]]; then
			missing=$((missing + 1))
		fi
	done <<EOF
$HOME/.bashrc|$repo_dir/bash/.bashrc
$HOME/.bash_aliases|$repo_dir/bash/.bash_aliases
$HOME/.inputrc|$repo_dir/readline/.inputrc
$HOME/bin/ex|$repo_dir/bin/bin/ex
$HOME/bin/clip|$repo_dir/bin/bin/clip
$HOME/bin/codex-rc|$repo_dir/bin/bin/codex-rc
$HOME/bin/claude-rc|$repo_dir/bin/bin/claude-rc
$HOME/bin/dotfiles|$repo_dir/bin/bin/dotfiles
EOF
	if ((missing == 0)); then
		printf 'installed|stow bash bin readline\n'
	else
		printf 'missing|%d managed stow target(s) missing or incorrect\n' "$missing"
	fi
}

_comp_probe_wsl_conf() {
	local conf="${DOTFILES_WSL_CONF:-/etc/wsl.conf}"
	if [[ -f "$conf" ]] &&
		wsl_conf_has_setting "$conf" boot systemd true &&
		wsl_conf_has_setting "$conf" interop appendWindowsPath true; then
		printf 'configured|systemd + appendWindowsPath\n'
	else
		printf 'check|/etc/wsl.conf not as expected\n'
	fi
}

_comp_probe_git_credential() {
	local helper recurse fetch push summary
	helper="$(git config --global --get-all credential.helper 2>/dev/null || true)"
	recurse="$(git config --global --get submodule.recurse 2>/dev/null || true)"
	fetch="$(git config --global --get fetch.recurseSubmodules 2>/dev/null || true)"
	push="$(git config --global --get push.recurseSubmodules 2>/dev/null || true)"
	summary="$(git config --global --get status.submoduleSummary 2>/dev/null || true)"
	if [[ -n "$helper" && "$recurse" == true && "$fetch" == on-demand &&
		"$push" == check && "$summary" == true ]]; then
		printf 'configured|credential helper + recursive submodule defaults\n'
	elif [[ -z "$helper" && "$recurse" == true && "$fetch" == on-demand &&
		"$push" == check && "$summary" == true ]]; then
		printf 'check|submodule defaults set; credential helper not configured\n'
	else
		printf 'check|Git configuration incomplete\n'
	fi
}

print_install_summary() {
	local row label detail result cols key install_result i
	local ok_count=0 miss_count=0
	local -a rows=() enabled_keys=()

	cols="$(menu_tty_cols)"
	rt_print_header "Install summary" "" "$cols"
	rt_print_table_columns

	collect_component_status_rows rows true
	for key in "${COMP_KEYS[@]}"; do
		is_on "$key" && enabled_keys+=("$key")
	done
	for i in "${!rows[@]}"; do
		row="${rows[$i]}"
		IFS='|' read -r label detail result <<<"$row"
		key="${enabled_keys[$i]:-}"
		install_result=''
		if declare -p INSTALL_COMPONENT_RESULT >/dev/null 2>&1; then
			install_result="${INSTALL_COMPONENT_RESULT[$key]:-}"
		fi
		if [[ "$install_result" == failed ]]; then
			detail="installer failed; $detail"
			result=failed
		fi
		case "$result" in
		installed | configured) ((++ok_count)) ;;
		*) ((++miss_count)) ;;
		esac
		rt_print_table_row "$label" "$detail" "$result"
	done

	echo ""
	if [[ $miss_count -eq 0 ]]; then
		echo "Install finished — ${ok_count} component(s) look good."
	else
		echo "Install finished — ${ok_count} ok, ${miss_count} need attention (see log above)."
	fi
}
