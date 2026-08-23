# shellcheck shell=bash
# Run independent probes concurrently and emit their output in input order.
#
# Status probes and update checks both fan out over a fixed list of slow,
# independent commands (version queries, `npm view`, GitHub release lookups).
# Run serially that is the sum of every probe; run this way it is the slowest
# single probe. Output order is the input order regardless of finish order, so
# report rows stay deterministic.

if [[ "${_DOTFILES_PARALLEL_PROBE_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_PARALLEL_PROBE_LOADED=1

# run_probes_parallel <fallback> <command>...
#
# Each argument after the fallback is run through `eval` in its own subshell.
# A probe that fails or prints nothing contributes <fallback> instead, so one
# broken probe cannot drop a row or stall the report.
run_probes_parallel() (
	local fallback="$1"
	shift
	local probe_dir index pid output
	local -a pids=()

	(($# > 0)) || return 0
	probe_dir="$(mktemp -d)" || return 1
	trap 'rm -rf -- "$probe_dir"' EXIT

	index=0
	for probe in "$@"; do
		(
			if output="$(eval "$probe" 2>/dev/null)" && [[ -n "$output" ]]; then
				printf '%s\n' "$output"
			else
				printf '%s\n' "$fallback"
			fi
		) >"$probe_dir/$index" &
		pids+=("$!")
		index=$((index + 1))
	done

	for pid in "${pids[@]}"; do
		wait "$pid" || true
	done

	index=0
	while ((index < $#)); do
		cat "$probe_dir/$index"
		index=$((index + 1))
	done
)
