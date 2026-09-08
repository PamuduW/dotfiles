# shellcheck shell=bash
# Client for the one-process-per-command Python service (python/service.py).
#
# ADR-0001: Bash gathers the raw facts and one Python invocation classifies,
# checks and renders. Every caller keeps its Bash path for the machine that has
# no runtime yet, so a service that will not start, dies, or answers strangely
# is a fallback rather than a failure.
#
# Two rules, both because a coprocess belongs to the shell that started it:
#
#   * Start it from the parent, never first from a subshell. A caller that will
#     use the service inside `$( )`, a pipeline or `< <( )` calls
#     py_service_available first, so the process is already there to inherit.
#   * One request at a time. Nothing here interleaves, and no parallel probe
#     issues a request -- the collector resolves classifications after its
#     probes have been waited on.
#
# And one that bash imposes: **py_service_call is never a pipeline element.**
# Bash closes coprocess descriptors in the children it forks for a pipeline, so
# `printf ... | py_service_call classify` writes to a closed descriptor and the
# call fails to a fallback that was never needed. Feed the payload with a
# process substitution or a here-string instead:
#
#     py_service_call classify < <(printf '%s\n' "${requests[@]}")
#
# Command substitution, process substitution and `< <( )` are all fine; it is
# specifically the pipeline that does it. tests/test_py_service.sh pins both
# halves of that so the rule does not have to be remembered.

if [[ "${_PY_SERVICE_LOADED:-0}" == 1 ]]; then
	return 0
fi
_PY_SERVICE_LOADED=1

_PY_SERVICE_END=$'\x03'
_PY_SERVICE_FS=$'\x1f'
_PY_SERVICE_STATE=unstarted

# Start the service if it is not running yet. Idempotent, and it gives up for
# good the first time it cannot start: a machine without python3 does not grow
# one part-way through a command.
py_service_available() {
	local script

	case "$_PY_SERVICE_STATE" in
	ready) return 0 ;;
	unavailable) return 1 ;;
	esac
	_PY_SERVICE_STATE=unavailable

	[[ "${DOTFILES_PY_SERVICE:-1}" == 1 ]] || return 1
	command -v python3 >/dev/null 2>&1 || return 1
	script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/python/service.py"
	[[ -f "$script" ]] || return 1

	# No bytecode: the shared tree is vendored and held byte-identical with the
	# sibling repository, where a stale __pycache__ masks an edit.
	coproc PY_SERVICE { PYTHONDONTWRITEBYTECODE=1 python3 "$script" 2>/dev/null; } || return 1
	_PY_SERVICE_STATE=ready
	return 0
}

# py_service_call <verb> [argument]...
# Payload on stdin, response on stdout. Callers with no payload redirect from
# /dev/null rather than leaving the read to find a terminal.
py_service_call() {
	local verb="$1" arg line
	shift

	py_service_available || return 1

	{
		printf '%s' "$verb"
		for arg in "$@"; do
			printf '%s%s' "$_PY_SERVICE_FS" "$arg"
		done
		printf '\n'
		cat
		printf '%s\n' "$_PY_SERVICE_END"
	} 1>&"${PY_SERVICE[1]}" || {
		_PY_SERVICE_STATE=unavailable
		return 1
	}

	while IFS= read -r -t "${DOTFILES_PY_SERVICE_TIMEOUT:-30}" line <&"${PY_SERVICE[0]}"; do
		if [[ "$line" == "$_PY_SERVICE_END" ]]; then
			return 0
		fi
		printf '%s\n' "$line"
	done

	# Timed out or the process is gone. Either way this side of the protocol is
	# out of step, so nothing uses it again and the caller takes its Bash path.
	_PY_SERVICE_STATE=unavailable
	return 1
}

py_service_stop() {
	local fd
	[[ "$_PY_SERVICE_STATE" == ready ]] || return 0
	_PY_SERVICE_STATE=stopped
	# Closing its stdin is how the service is asked to leave; it reads EOF and
	# returns. The `{fd}>&-` form closes the descriptor whose number is in fd,
	# which the array element cannot be spelled as directly.
	fd="${PY_SERVICE[1]}"
	exec {fd}>&- || true
}
