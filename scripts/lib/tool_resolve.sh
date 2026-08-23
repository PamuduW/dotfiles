# shellcheck shell=bash
# Shared CLI discovery and version reading.
#
# Status probes (components/probes.sh) and update checks (updates/*.sh) both
# need to answer "where is this tool, and what version is it?" for the same
# set of CLIs. This module owns that so the two paths cannot disagree.

if [[ "${_DOTFILES_TOOL_RESOLVE_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_TOOL_RESOLVE_LOADED=1

# Print the path of the first usable executable: every candidate on PATH first,
# then the vendor-local ~/.local/bin fallback several installers use.
# NAMES is a space-separated candidate list in preference order.
tool_resolve() {
	local names="$1" name resolved
	for name in $names; do
		if resolved="$(command -v "$name" 2>/dev/null)"; then
			printf '%s\n' "$resolved"
			return 0
		fi
	done
	for name in $names; do
		if [[ -x "$HOME/.local/bin/$name" ]]; then
			printf '%s\n' "$HOME/.local/bin/$name"
			return 0
		fi
	done
	return 1
}

# Print a tool's raw version output, or return 1 when it cannot be read.
#
# This deliberately does not pipe into head: `cmd --version | head -n1` reports
# the exit status of head, which is 0 even when cmd failed and produced nothing,
# so a trailing `|| echo installed` fallback could never fire and the caller
# printed an empty version instead. Callers do their own first-line or regex
# extraction on the returned text.
tool_version_raw() {
	local binary="$1" raw
	shift
	raw="$("$binary" "$@" 2>/dev/null)" || return 1
	[[ -n "$raw" ]] || return 1
	printf '%s' "$raw"
}
