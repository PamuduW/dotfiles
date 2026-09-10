# shellcheck shell=bash
# shellcheck disable=SC2034  # Namerefs are written through, not read, in this file.
# Per-component status probes (_comp_probe_<id>).

if ! declare -F codex_cli_install_state >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/managed_tool_state.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/managed_tool_state.sh"
fi
if ! declare -F py_service_available >/dev/null 2>&1; then
	# shellcheck source=scripts/lib/shared/py_service.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/shared/py_service.sh"
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

# --- Classification: one Python process per run ----------------------------
#
# ADR-0001 stage two. The readings live in shared/python/probe_classify.py. The
# `_comp_classify_*` functions below stay as the fallback for the paths that run
# before Dotfiles has installed a runtime, exactly as the Bash renderer does,
# and tests/test_probe_classify_parity.sh holds the two sides in agreement.
#
# While a collector is batching, a probe does not classify inline: comp_classify
# emits the request and the collector answers every request in one call. Per
# probe that spawn measured ~324 ms of a ~900 ms `dotfiles status`; batched, it
# is ~18 ms.
#
# The wire format is a line per request, fields separated by \x1f, with any
# newline inside a field carried as \x1e -- requests travel through files that
# are read a line at a time, and neither byte occurs in a version string, a path
# or a package name.
_COMP_CLASSIFY_MARK=$'\x01'
_COMP_CLASSIFY_FS=$'\x1f'
_COMP_CLASSIFY_NL=$'\x1e'

# comp_classify <name> <argument>...
comp_classify() {
	local out='' arg first=1

	if [[ "${COMP_CLASSIFY_DEFER:-0}" != 1 ]]; then
		"_comp_classify_$1" "${@:2}"
		return 0
	fi

	for arg in "$@"; do
		arg="${arg//$'\n'/$_COMP_CLASSIFY_NL}"
		if ((first)); then
			out="$arg"
			first=0
		else
			out+="${_COMP_CLASSIFY_FS}${arg}"
		fi
	done
	printf '%s%s\n' "$_COMP_CLASSIFY_MARK" "$out"
}

# _comp_classify_resolve <requests-array> <results-array> [use-service]
#
# Answers in input order, one result per request, through the one Python process
# this command runs. Bash answers the batch itself when there is no service --
# first setup draws this table before the runtime exists, so the fallback is
# permanent rather than migration scaffolding -- and when the service did not
# answer for every request. Pass 0 as the third argument to take that path
# deliberately, which is how it is tested without hiding python3 from the
# harness.
_comp_classify_resolve() {
	local -n _requests="$1"
	local -n _results="$2"
	local use_service="${3:-1}"
	local request body field
	local -a fields=()

	_results=()
	((${#_requests[@]} > 0)) || return 0

	if [[ "$use_service" == 1 ]] && py_service_available; then
		# Process substitution, not a pipeline: bash closes coprocess descriptors
		# in pipeline children. See scripts/lib/shared/py_service.sh.
		mapfile -t _results < <(py_service_call classify < <(printf '%s\n' "${_requests[@]}"))
		((${#_results[@]} == ${#_requests[@]})) && return 0
	fi

	_results=()
	for request in "${_requests[@]}"; do
		# Split by hand rather than with `read -a`: a request whose last field
		# is empty is normal (an absent version prefix, an unset git value), and
		# read drops it, which would shift every argument after it.
		fields=()
		body="${request}${_COMP_CLASSIFY_FS}"
		while [[ -n "$body" ]]; do
			field="${body%%"$_COMP_CLASSIFY_FS"*}"
			fields+=("${field//$_COMP_CLASSIFY_NL/$'\n'}")
			body="${body#*"$_COMP_CLASSIFY_FS"}"
		done
		_results+=("$("_comp_classify_${fields[0]}" "${fields[@]:1}")")
	done
}

# The apt reading is counted and worded in one request: how many entries have no
# installed alternative is not a decision any caller needs on its own, and a
# value handed back mid-probe cannot be deferred to a batched call.
_comp_classify_apt() {
	local queried="$1" catalog="$2" missing_label="$3" clean_detail="$4"
	local entry_count="$5" installed_count="$6"
	shift 6

	if [[ "$catalog" != 1 ]]; then
		printf 'missing|packages.txt not found\n'
		return 0
	fi
	# A query that never answered says nothing about what is installed. Reading
	# its silence as "none of them" would report a healthy machine as empty.
	if [[ "$queried" != 1 ]]; then
		printf 'check|package state unknown (dpkg-query timed out)\n'
		return 0
	fi

	local -a entries=("${@:1:entry_count}")
	local -A installed=() available=()
	local name

	for name in "${@:entry_count+1:installed_count}"; do
		[[ -n "$name" ]] && installed["$name"]=1
	done
	for name in "${@:entry_count+installed_count+1}"; do
		[[ -n "$name" ]] && available["$name"]=1
	done

	local missing unavailable
	read -r missing unavailable < <(_comp_package_gaps entries installed available)
	_comp_classify_apt_packages "${#entries[@]}" "$missing" \
		"$missing_label" "$clean_detail" "$unavailable"
}

# Every external command a probe runs is bounded, not only the ones whose output
# _comp_probe_capture collects. The collector waits on every probe child, so one
# command that never returns is a `dotfiles status` that never returns either --
# no table, no rollup, nothing to interrupt but the terminal.
#
# Package queries get a longer bound than version probes: measured at 36 ms for
# dpkg-query and 318 ms for apt-cache over the whole catalogue, so ten seconds is
# thirty times the headroom, and a machine slow enough to exceed it has a real
# problem worth reporting rather than guessing about.
_comp_probe_bounded() {
	local seconds="$1"
	shift
	timeout --kill-after=0.2 "$seconds" "$@"
}

_comp_package_probe_timeout() {
	printf '%s\n' "${COMP_PACKAGE_PROBE_TIMEOUT_SECONDS:-10}"
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
	local i result detail
	local -a probes=()

	_collect_component_probes probes "$enabled_only"
	output_rows=()
	for i in "${!probes[@]}"; do
		IFS='|' read -r result detail <<<"${probes[$i]#*"$_COMP_CLASSIFY_FS"}"
		output_rows+=("$(_install_short_label "${COMP_LABELS[${probes[$i]%%"$_COMP_CLASSIFY_FS"*}]}")|${detail}|${result}")
	done
}

# collect_component_probe_results <assoc-array-name>
# key -> probe result, from the same parallel probe the status table uses, so
# full-update and status cannot disagree about what is installed.
collect_component_probe_results() {
	local output_name="$1" entry index result
	local -n output_map="$output_name"
	local -a probes=()

	_collect_component_probes probes false
	output_map=()
	for entry in "${probes[@]}"; do
		index="${entry%%"$_COMP_CLASSIFY_FS"*}"
		result="${entry#*"$_COMP_CLASSIFY_FS"}"
		output_map["${COMP_KEYS[$index]}"]="${result%%|*}"
	done
}

# The probes whose interrogation is Python (shared/python/probes.py). They read
# the filesystem and Git configuration, so one process answers all of them and
# there is nothing to overlap; the ones that run a version command stay below,
# where Bash already runs them in parallel. Without the service every one of
# these falls through to its Bash probe, which is why both still exist --
# `python3` belongs to the optional `python` component, so a first setup that
# deselects it prints its install summary with no interpreter.
_COMP_PYTHON_PROBES=(monaspace_fonts dotfiles wsl_conf git_identity git_credential)
# What the stream writes where such a probe's result will go.
_COMP_PROBE_PENDING=$'\x02'

# comp_probe is the documented seam: a caller that replaces it -- every suite
# that drives a report without touching the machine does -- expects every probe
# to go through its version. Answering some of them in another process before
# that function is ever called would step around it silently, so the shortcut
# above applies only while the seam is the one the registry defined.
# Captured here, while this file loads, and never later: a definition recorded
# on first use would record whatever a caller had already put there.
_COMP_PROBE_STOCK_DEFINITION="$(declare -f comp_probe 2>/dev/null || true)"
_comp_probe_is_stock() {
	[[ -n "$_COMP_PROBE_STOCK_DEFINITION" ]] || return 1
	[[ "$(declare -f comp_probe 2>/dev/null || true)" == "$_COMP_PROBE_STOCK_DEFINITION" ]]
}

# _collect_component_probes <array-name> <enabled-only>
#
# `index<FS>result|detail` per probed component, in registry order.
#
# Interrogation happens in a subshell, one child per component; classification
# happens here, in the caller's shell, in one call. That split is not only the
# ADR's -- a coprocess belongs to the shell that started it, and bash closes its
# descriptors in a `( )` subshell, so a reading resolved down there would spawn
# its own interpreter or fall back to Bash on every run.
_collect_component_probes() {
	local output_name="$1" enabled_only="${2:-false}"
	local -n _probes="$output_name"
	local entry index probe
	local -a requests=() request_rows=() results=()

	# Asked for first and read for last, with the parallel Bash probes in
	# between: these are quick, but running them before the slow ones start
	# added their time to the command rather than hiding it, which is the whole
	# reason the Bash side probes in parallel at all.
	local -A answered=()
	local pending=false
	if _comp_probe_is_stock && py_service_send probe "${DOTFILES_DIR:-$PWD}" \
		< <(printf '%s\n' "${_COMP_PYTHON_PROBES[@]}"); then
		pending=true
	fi

	mapfile -t _probes < <(_component_probe_stream "$enabled_only" "$pending")

	if [[ "$pending" == true ]]; then
		local key result
		while IFS=$'\x1f' read -r key result; do
			[[ -n "$key" ]] || continue
			answered["$key"]="$result"
		done < <(py_service_receive)
	fi

	# The stream left a placeholder for every key answered over there.
	local index entry
	for index in "${!_probes[@]}"; do
		entry="${_probes[$index]}"
		key="${entry#*"$_COMP_CLASSIFY_FS"}"
		[[ "$key" == "$_COMP_PROBE_PENDING"* ]] || continue
		key="${key#"$_COMP_PROBE_PENDING"}"
		_probes[index]="${entry%%"$_COMP_CLASSIFY_FS"*}${_COMP_CLASSIFY_FS}${answered[$key]:-check|probe failed}"
	done

	for index in "${!_probes[@]}"; do
		probe="${_probes[$index]#*"$_COMP_CLASSIFY_FS"}"
		if [[ "${probe:0:1}" == "$_COMP_CLASSIFY_MARK" ]]; then
			requests+=("${probe:1}")
			request_rows+=("$index")
		fi
	done

	((${#requests[@]} > 0)) || return 0
	_comp_classify_resolve requests results
	for index in "${!request_rows[@]}"; do
		entry="${_probes[${request_rows[$index]}]}"
		_probes[${request_rows[$index]}]="${entry%%"$_COMP_CLASSIFY_FS"*}${_COMP_CLASSIFY_FS}${results[$index]}"
	done
}

# Interrogation only: every probe runs in its own child and nothing here decides
# what an answer means.
_component_probe_stream() (
	local enabled_only="${1:-false}" python_pending="${2:-false}"
	local probe_dir i key probe pid
	local -a pids=() indexes=()
	# Keys being answered elsewhere: this leaves a marker rather than probing
	# them, and the caller fills it in when the answer arrives.
	local -A elsewhere=()
	if [[ "$python_pending" == true ]]; then
		for key in "${_COMP_PYTHON_PROBES[@]}"; do elsewhere["$key"]=1; done
	fi
	probe_dir="$(mktemp -d)" || return 1
	trap 'rm -r -- "$probe_dir"' EXIT

	# Probes emit classification requests rather than readings; the caller
	# answers every request in this run in one call.
	local COMP_CLASSIFY_DEFER=1

	for i in "${!COMP_KEYS[@]}"; do
		key="${COMP_KEYS[$i]}"
		[[ "$enabled_only" == true ]] && { is_on "$key" || continue; }
		indexes+=("$i")
		if [[ -n "${elsewhere[$key]+x}" ]]; then
			printf '%s%s\n' "$_COMP_PROBE_PENDING" "$key" >"$probe_dir/$i"
			continue
		fi
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
		printf '%s%s%s\n' "$i" "$_COMP_CLASSIFY_FS" "$(<"$probe_dir/$i")"
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

	binary="$(tool_resolve "$names")" || binary=''
	if [[ -n "$binary" ]]; then
		# shellcheck disable=SC2086  # version_args is an internal word list.
		_comp_probe_capture raw "$timeout_seconds" "$binary" $version_args || rc=$?
	fi

	comp_classify version "$missing_label" "$timeout_label" "$binary" "$rc" "$raw" "$extract" "$prefix"
}

# Pure: how a version probe's result reads. Shared by every component in the
# version-probe table, so a change here reaches roughly ten probes at once --
# which is the argument for testing it directly rather than through any one of
# them.
#
# `grep` appears here but transforms text and touches no system state; the
# extraction pattern is part of the reading, not the asking.
_comp_classify_version() {
	local missing_label="$1" timeout_label="$2" binary="$3" rc="$4"
	local raw="$5" extract="$6" prefix="$7"
	local version

	if [[ -z "$binary" ]]; then
		printf 'missing|%s not on PATH\n' "$missing_label"
		return 0
	fi
	if [[ "$rc" -eq 124 ]]; then
		printf 'check|%s probe timed out\n' "$timeout_label"
		return 0
	fi

	version="$raw"
	if [[ -n "$extract" ]]; then
		version="$(grep -oE "$extract" <<<"$raw" | head -n1 || true)"
	fi
	# An empty version still reports installed: the binary resolved and
	# answered, so falling back to its label beats claiming it is missing.
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

# Pure: both halves or neither. An identity with only one of them configured is
# not usable, and `git commit` says so at the worst possible moment.
_comp_classify_git_identity() {
	local name="$1" email="$2"

	if [[ -n "$name" && -n "$email" ]]; then
		printf 'configured|%s <%s>\n' "$name" "$email"
	else
		printf 'missing|not configured\n'
	fi
}

_comp_probe_git_identity() {
	local name email
	name="$(git config --global user.name 2>/dev/null || true)"
	email="$(git config --global user.email 2>/dev/null || true)"
	comp_classify git_identity "$name" "$email"
}

# Which of these names this release can still install.
#
# One `apt-cache policy` for the whole set rather than one per name, and the
# same reading apt_install_packages uses: a name with no candidate, or none at
# all, is not something a machine can be told to install.
_comp_apt_available() {
	local line name=''
	while IFS= read -r line; do
		case "$line" in
		'  Candidate: '*)
			[[ -n "$name" && "${line#'  Candidate: '}" != '(none)' ]] && printf '%s\n' "$name"
			name=''
			;;
		[![:space:]]*:)
			name="${line%:}"
			;;
		esac
	done < <(_comp_probe_bounded "$(_comp_package_probe_timeout)" apt-cache policy -- "$@" 2>/dev/null)
}

# Interrogation for an apt-backed component. The count and the wording of a
# complete set travel with the request: `clean_suffix` is what this component
# adds after "<n> apt packages", and everything else is decided in the reading.
_comp_probe_apt_packages_for_component() {
	local component="$1" missing_label="$2" clean_suffix="${3:-}"
	local pkg_file="${PKG_FILE:-${DOTFILES_DIR:-}/packages/packages.txt}"
	local package_count=0 tags queried=0
	local -a packages=() installed_names=() available_names=()

	if [[ ! -f "$pkg_file" ]]; then
		comp_classify apt 1 0 "$missing_label" '' 0
		return 0
	fi

	tags="$(comp_package_tags "$component")"
	# shellcheck disable=SC2086 # Component package tags are an internal word list.
	mapfile -t packages < <(PKG_FILE="$pkg_file" read_packages_by_tags $tags)
	package_count="${#packages[@]}"

	# One dpkg-query for the whole set instead of one process per package.
	# Entries may be `preferred|fallback` package renames, so every alternative
	# goes into the one query and the reading counts an entry as present when any
	# of its names came back installed.
	if ((package_count > 0)); then
		local entry alt satisfied
		local -a all_names=() alternatives=()
		for entry in "${packages[@]}"; do
			# Split with read, not a process substitution per entry: this runs
			# once per package in a table of fifty-odd, twice, and the forks
			# cost more than everything else the probe does.
			IFS='|' read -r -a alternatives <<<"$entry"
			for alt in "${alternatives[@]}"; do
				[[ -n "$alt" ]] && all_names+=("$alt")
			done
		done

		local name rest
		local -A installed_set=()
		local query_file
		query_file="$(mktemp)" || return 1
		# shellcheck disable=SC2016  # dpkg-query's own format language, not ours.
		if _comp_probe_bounded "$(_comp_package_probe_timeout)" \
			dpkg-query -W -f='${Package} ${Status}\n' "${all_names[@]}" >"$query_file" 2>/dev/null ||
			[[ -s "$query_file" ]]; then
			# dpkg-query exits non-zero when any name is unknown, which is the
			# normal case for a rename; output is what says it answered.
			queried=1
		fi
		while read -r name rest; do
			if [[ "$rest" == 'install ok installed' ]]; then
				installed_names+=("$name")
				installed_set["$name"]=1
			fi
		done <"$query_file"
		rm -f -- "$query_file"

		# Asked only about entries nothing satisfies, and only when there are
		# any: `apt-cache policy` over the whole catalogue costs ~318 ms against
		# a ~700 ms status, while an unsatisfied entry is usually none at all.
		# What comes back separates a package this release dropped from one the
		# operator can still install.
		local -a absent=()
		for entry in "${packages[@]}"; do
			IFS='|' read -r -a alternatives <<<"$entry"
			satisfied=false
			for alt in "${alternatives[@]}"; do
				[[ -n "$alt" && -n "${installed_set[$alt]+x}" ]] && satisfied=true && break
			done
			[[ "$satisfied" == true ]] && continue
			for alt in "${alternatives[@]}"; do
				[[ -n "$alt" ]] && absent+=("$alt")
			done
		done
		((${#absent[@]} > 0)) && mapfile -t available_names < <(_comp_apt_available "${absent[@]}")
	fi

	# Nothing to query is a complete answer, so an empty catalogue counts as
	# queried; the reading below decides what an empty list means.
	((package_count > 0)) || queried=1
	comp_classify apt "$queried" 1 "$missing_label" "${package_count} apt packages${clean_suffix}" \
		"$package_count" "${#installed_names[@]}" \
		${packages[@]+"${packages[@]}"} \
		${installed_names[@]+"${installed_names[@]}"} \
		${available_names[@]+"${available_names[@]}"}
}

# Pure: how the entries with no installed alternative divide.
#
# A package this release does not carry cannot be installed by anyone, so
# counting it as missing leaves a row permanently red with nothing to do about
# it. The installer already draws this line -- apt_install_packages skips what
# `apt-cache policy` has no candidate for and says how many it skipped -- and
# the reading did not, so the two disagreed about the same machine.
_comp_package_gaps() {
	local entries_name="$1" installed_name="$2" available_name="$3"
	local -n _entries="$entries_name"
	local -n _installed="$installed_name"
	local -n _available="$available_name"
	local entry alt missing=0 unavailable=0 state

	for entry in "${_entries[@]}"; do
		state=unavailable
		while IFS= read -r alt; do
			[[ -n "$alt" ]] || continue
			if [[ -n "${_installed[$alt]+x}" ]]; then
				state=installed
				break
			fi
			[[ -n "${_available[$alt]+x}" ]] && state=missing
		done < <(printf '%s\n' "${entry//|/$'\n'}")
		case "$state" in
		missing) missing=$((missing + 1)) ;;
		unavailable) unavailable=$((unavailable + 1)) ;;
		esac
	done

	printf '%s %s\n' "$missing" "$unavailable"
}

# Pure: how many entries have no installed alternative.
#
# Defect 9 lived here. Entries may be `preferred|fallback` renames, and querying
# the raw entry counted a renamed package as missing even though it was
# installed under its current name. An entry counts as present when *any* of its
# alternatives is installed.
#
# Takes the package list and the installed set by name, so it can be tested
# against any combination without a dpkg to produce one.
_comp_missing_package_count() {
	local packages_name="$1" installed_name="$2"
	local -n _pkg_entries="$packages_name"
	local -n _installed="$installed_name"
	local entry alt installed_count=0 missing

	for entry in "${_pkg_entries[@]}"; do
		while IFS= read -r alt; do
			if [[ -n "$alt" && -n "${_installed[$alt]+x}" ]]; then
				installed_count=$((installed_count + 1))
				break
			fi
		done < <(printf '%s\n' "${entry//|/$'\n'}")
	done

	missing=$((${#_pkg_entries[@]} - installed_count))
	((missing < 0)) && missing=0
	printf '%s\n' "$missing"
}

# Pure: how the two counts read. An empty set is skipped rather than clean --
# nothing was checked. The complete-set wording arrives as an argument because
# the two callers word it differently, and because a caller that has to branch
# on the reading to finish its own sentence cannot defer that reading.
_comp_classify_apt_packages() {
	local package_count="$1" missing="$2" missing_label="$3" clean_detail="$4"
	local unavailable="${5:-0}" aside=''

	((unavailable > 0)) && printf -v aside ' (%d unavailable on this release)' "$unavailable"

	if [[ "$package_count" -eq 0 ]]; then
		printf 'skipped|no packages listed\n'
		return 0
	fi
	if [[ "$missing" -ne 0 ]]; then
		printf 'missing|%d of %d %s not installed%s\n' \
			"$missing" "$package_count" "$missing_label" "$aside"
		return 0
	fi
	printf 'installed|%s%s\n' "$clean_detail" "$aside"
}

_comp_probe_system_packages() {
	_comp_probe_apt_packages_for_component system_packages packages
}

# Pure: three questions asked in order, because each one needs the answer before
# it. The reading names the first that failed rather than the last.
_comp_classify_python_runtime() {
	local python3_present="$1" pip_ok="$2" venv_ok="$3"

	if [[ "$python3_present" != 1 ]]; then
		printf 'missing|python3 not on PATH\n'
	elif [[ "$pip_ok" != 1 ]]; then
		printf 'missing|python3-pip unavailable\n'
	elif [[ "$venv_ok" != 1 ]]; then
		printf 'missing|python3-venv unavailable\n'
	else
		printf 'installed|python3 pip venv ready\n'
	fi
}

# Interrogation. The branch below is on raw answers, not on a reading: a working
# runtime is the precondition for asking about packages at all.
_comp_probe_python() {
	local python3_present=0 pip_ok=0 venv_ok=0

	local timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if command -v python3 >/dev/null 2>&1; then
		python3_present=1
		_comp_probe_bounded "$timeout_seconds" python3 -m pip --version >/dev/null 2>&1 && pip_ok=1
		((pip_ok)) &&
			_comp_probe_bounded "$timeout_seconds" python3 -m venv --help >/dev/null 2>&1 && venv_ok=1
	fi

	if ((python3_present && pip_ok && venv_ok)); then
		_comp_probe_apt_packages_for_component python 'Python packages' '; python3 pip venv ready'
		return
	fi
	comp_classify python_runtime "$python3_present" "$pip_ok" "$venv_ok"
}

# Pure: Graphify and Boost differ only in what they call themselves and in what
# owning them means -- uv against nothing, Dotfiles-managed against external.
# The same shape as the version reading, plus the ownership the two report.
_comp_classify_owned_cli() {
	local missing_label="$1" timeout_label="$2" owned_suffix="$3" external_suffix="$4"
	local found="$5" rc="$6" ver="$7" path="$8" owned="$9"

	if [[ "$found" != 1 ]]; then
		printf 'missing|%s not on PATH\n' "$missing_label"
		return 0
	fi
	if [[ "$rc" -eq 124 ]]; then
		printf 'check|%s probe timed out\n' "$timeout_label"
		return 0
	fi
	if [[ "$owned" == 1 ]]; then
		printf 'installed|%s%s\n' "${ver:-$path}" "$owned_suffix"
	else
		printf 'installed|%s%s\n' "${ver:-$path}" "$external_suffix"
	fi
}

_comp_probe_graphify_cli() {
	local graphify_path='' ver='' rc=0 found=0 owned=0
	local timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"

	if graphify_path="$(graphify_command 2>/dev/null)"; then
		found=1
		_comp_probe_capture ver "$timeout_seconds" "$graphify_path" --version || rc=$?
		if declare -F graphify_cli_is_uv_owned >/dev/null 2>&1 && graphify_cli_is_uv_owned; then
			owned=1
		fi
	fi

	comp_classify owned_cli graphify 'graphify cli' ' (uv)' '' \
		"$found" "$rc" "$ver" "$graphify_path" "$owned"
}

_comp_probe_boost_cli() {
	local boost_path='' ver='' rc=0 found=0 owned=0
	local timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"

	if boost_path="$(boost_command 2>/dev/null)"; then
		found=1
		_comp_probe_capture ver "$timeout_seconds" "$boost_path" version || rc=$?
		boost_cli_is_dotfiles_owned && owned=1
	fi

	comp_classify owned_cli boost 'boost cli' ' (Dotfiles managed)' ' (external)' \
		"$found" "$rc" "$ver" "$boost_path" "$owned"
}

# Classification for Codex. Defect 6 in the clean-machine history was a
# standalone install not yet on PATH being read as shadowed, which routed the
# run into a migration with nothing to migrate. The state names carry that
# distinction; this maps them to what the operator is told.
#
# Pure: no commands, no PATH lookups.
_comp_classify_codex_cli() {
	local state="$1" codex_path="$2" ver="$3" rc="$4"

	case "$state" in
	standalone | standalone-not-on-path)
		if [[ "$rc" -eq 124 ]]; then
			printf 'check|codex cli probe timed out\n'
			return 0
		fi
		if [[ "$state" == standalone-not-on-path ]]; then
			printf 'installed|%s (standalone, not on PATH in this session)\n' "${ver:-$codex_path}"
		else
			printf 'installed|%s (standalone)\n' "${ver:-$codex_path}"
		fi
		;;
	external)
		if [[ "$rc" -eq 124 ]]; then
			printf 'check|codex cli probe timed out\n'
			return 0
		fi
		printf 'check|%s (external; migration required)\n' "${ver:-$codex_path}"
		;;
	standalone-shadowed)
		printf 'check|standalone Codex is shadowed by %s\n' "${codex_path:-unknown}"
		;;
	*)
		printf 'missing|codex not on PATH\n'
		;;
	esac
}

# Interrogation. Which questions get asked depends on the install state, but no
# answer is decided here.
_comp_probe_codex_cli() {
	local state codex_path='' ver='' rc=0 timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	state="$(codex_cli_install_state)" || state=absent
	case "$state" in
	standalone | standalone-not-on-path)
		codex_path="$(codex_visible_install_path)"
		_comp_probe_capture ver "$timeout_seconds" "$codex_path" --version || rc=$?
		;;
	external)
		codex_path="$(codex_active_command 2>/dev/null || true)"
		_comp_probe_capture ver "$timeout_seconds" "$codex_path" --version || rc=$?
		;;
	standalone-shadowed)
		codex_path="$(codex_active_command 2>/dev/null || true)"
		;;
	esac
	comp_classify codex_cli "$state" "$codex_path" "$ver" "$rc"
}

# Classification for Go, which has two sources and a fallback between them.
#
# The subtle path: `go` resolves but its output does not parse, so the reading
# falls through to asdf rather than reporting a version it does not have. That
# case is unreachable through a real toolchain and is exactly what a pure
# reading makes testable.
_comp_classify_go() {
	local go_present="$1" go_rc="$2" go_raw="$3"
	local asdf_present="$4" asdf_rc="$5" asdf_raw="$6"
	local ver

	if [[ "$go_present" == 1 ]]; then
		if [[ "$go_rc" -eq 124 ]]; then
			printf 'check|go probe timed out\n'
			return 0
		fi
		ver="$(grep -oE 'go[0-9.]+' <<<"$go_raw" | head -n1 || true)"
		if [[ -n "$ver" ]]; then
			printf 'installed|%s\n' "$ver"
			return 0
		fi
	fi

	if [[ "$asdf_present" == 1 ]]; then
		if [[ "$asdf_rc" -eq 124 ]]; then
			printf 'check|go probe timed out\n'
			return 0
		fi
		ver="$(awk '$1=="golang" {print $2; exit}' <<<"$asdf_raw")"
		if [[ -n "$ver" && "$ver" != system ]]; then
			printf 'installed|go%s (asdf)\n' "$ver"
		else
			printf 'missing|asdf has no selected Go version\n'
		fi
		return 0
	fi

	printf 'missing|working Go installation not found\n'
}

# Interrogation. Asks both sources; decides between them nowhere.
_comp_probe_go() {
	local timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	local go_present=0 go_rc=0 go_raw=''
	local asdf_present=0 asdf_rc=0 asdf_raw=''

	if command -v go >/dev/null 2>&1; then
		go_present=1
		_comp_probe_capture go_raw "$timeout_seconds" go version || go_rc=$?
	fi
	if command -v asdf >/dev/null 2>&1; then
		asdf_present=1
		_comp_probe_capture asdf_raw "$timeout_seconds" asdf current golang || asdf_rc=$?
	fi

	comp_classify go "$go_present" "$go_rc" "$go_raw" \
		"$asdf_present" "$asdf_rc" "$asdf_raw"
}

# Classification, separated from interrogation on purpose.
#
# ADR-0001's second amendment: three of the five component defects in
# docs/history/bootstrap-clean-machine-testing.md were misreadings of an
# interrogation that was itself correct, and defect 5 was this probe reading a
# refused `docker ps` as "container not found". The reading is where the bugs
# are, and a reading that takes its inputs as arguments can be tested against
# every state without a docker to produce them.
#
# Pure: no commands, no filesystem, no environment.
_comp_classify_portainer() {
	local docker_present="$1" rc="$2" name="$3"

	if [[ "$docker_present" != 1 ]]; then
		printf 'missing|docker is not installed\n'
		return 0
	fi
	if [[ "$rc" -eq 124 ]]; then
		printf 'check|portainer probe timed out\n'
	elif [[ "$name" == portainer ]]; then
		printf 'installed|container exists (stopped by default)\n'
	elif [[ "$rc" -ne 0 ]]; then
		# The daemon refused the query, so this says nothing about the
		# container. Reporting "not found" here made a fresh install look
		# failed: the docker group is granted during that same run and is not
		# active until the next session.
		printf 'check|cannot query docker yet (new docker group needs a new session)\n'
	else
		printf 'missing|portainer container not found\n'
	fi
}

# Interrogation. Everything here needs a real machine; nothing here decides.
_comp_probe_portainer() {
	local name rc=0 timeout_seconds="${COMP_PROBE_TIMEOUT_SECONDS:-3}"
	if ! command -v docker >/dev/null 2>&1; then
		comp_classify portainer 0 0 ''
		return 0
	fi
	_comp_probe_capture name "$timeout_seconds" docker ps -a \
		--filter 'name=^/portainer$' --format '{{.Names}}' || rc=$?
	comp_classify portainer 1 "$rc" "$name"
}

# Pure: a directory with no .otf in it is not an installation, so presence here
# means the fonts, never the folder.
_comp_classify_monaspace_fonts() {
	local present="$1" count="$2" ver="$3"

	if [[ "$present" != 1 ]]; then
		printf 'missing|fonts not in ~/.local/share/fonts/monaspace\n'
	else
		printf 'installed|%s (%s fonts)\n' "$ver" "$count"
	fi
}

_comp_probe_monaspace_fonts() {
	local font_dir count='' ver='' present=0
	font_dir="$HOME/.local/share/fonts/monaspace"

	if [[ -d "$font_dir" ]] && compgen -G "${font_dir}/*.otf" >/dev/null 2>&1; then
		present=1
		count="$(find "$font_dir" -maxdepth 1 -name '*.otf' 2>/dev/null | wc -l | tr -d ' ')"
		ver="installed"
		[[ -f "${font_dir}/.version" ]] && ver="$(cat "${font_dir}/.version")"
	fi

	comp_classify monaspace_fonts "$present" "$count" "$ver"
}

# Pure: a link pointing somewhere else is as missing as no link at all, so the
# count is of targets that do not resolve into this checkout.
_comp_classify_stow_targets() {
	local missing="$1"

	if [[ "$missing" -eq 0 ]]; then
		printf 'installed|stow bash bin readline\n'
	else
		printf 'missing|%d managed stow target(s) missing or incorrect\n' "$missing"
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
$HOME/bin/git|$repo_dir/bin/bin/git
$HOME/bin/dotfiles|$repo_dir/bin/bin/dotfiles
EOF
	comp_classify stow_targets "$missing"
}

_comp_classify_wsl_conf() {
	local present="$1" systemd="$2" append_windows_path="$3"

	if [[ "$present" == 1 && "$systemd" == 1 && "$append_windows_path" == 1 ]]; then
		printf 'configured|systemd + appendWindowsPath\n'
	else
		printf 'check|/etc/wsl.conf not as expected\n'
	fi
}

_comp_probe_wsl_conf() {
	local conf="${DOTFILES_WSL_CONF:-/etc/wsl.conf}"
	local present=0 systemd=0 append_windows_path=0

	if [[ -f "$conf" ]]; then
		present=1
		wsl_conf_has_setting "$conf" boot systemd true && systemd=1
		wsl_conf_has_setting "$conf" interop appendWindowsPath true && append_windows_path=1
	fi

	comp_classify wsl_conf "$present" "$systemd" "$append_windows_path"
}

# Classification for the Git credential and submodule defaults. Five inputs,
# three outcomes, and the middle one is easy to lose: submodule defaults all set
# but no credential helper is a different message from a partial configuration,
# and only one of the five values distinguishes them.
_comp_classify_git_credential() {
	local helper="$1" recurse="$2" fetch="$3" push="$4" summary="$5"
	local defaults_set=0

	[[ "$recurse" == true && "$fetch" == on-demand &&
		"$push" == check && "$summary" == true ]] && defaults_set=1

	if ((defaults_set)) && [[ -n "$helper" ]]; then
		printf 'configured|credential helper + recursive submodule defaults\n'
	elif ((defaults_set)); then
		printf 'check|submodule defaults set; credential helper not configured\n'
	else
		printf 'check|Git configuration incomplete\n'
	fi
}

_comp_probe_git_credential() {
	local helper recurse fetch push summary
	helper="$(git config --global --get-all credential.helper 2>/dev/null || true)"
	recurse="$(git config --global --get submodule.recurse 2>/dev/null || true)"
	fetch="$(git config --global --get fetch.recurseSubmodules 2>/dev/null || true)"
	push="$(git config --global --get push.recurseSubmodules 2>/dev/null || true)"
	summary="$(git config --global --get status.submoduleSummary 2>/dev/null || true)"
	comp_classify git_credential "$helper" "$recurse" "$fetch" "$push" "$summary"
}

# What Doctor used to be. It was a second screen over the same probes as Check
# Status, showing a strict subset of its rows -- on a healthy machine, one row
# reading "All components | installed or configured | ok" against Status's
# twenty. The part that was not a duplicate is this: the list of commands that
# fix what the probes found. It belongs under the table that found it.
#
# Callers pass the rows they already collected, so nothing is probed twice.
# Returns 1 when something needs attention, which is what `dotfiles doctor`
# reports as its exit status and full-update's postflight reads.
status_print_suggestions() {
	local rows_name="$1"
	local -n suggestion_rows="$rows_name"
	local row component detail result codex_path
	local miss_count=0 check_count=0 codex_missing=0 codex_conflict=0
	local -a attention=()
	local width=0

	for row in "${suggestion_rows[@]}"; do
		IFS='|' read -r component detail result <<<"$row"
		[[ -n "$component" ]] || continue
		# Green is fine and a skip is a deliberate non-event.
		case "$result" in
		skipped*) continue ;;
		esac
		[[ "$(status_result_class "$result")" == ok ]] && continue
		if [[ "$component" == 'Codex CLI' ]]; then
			if [[ "$result" == missing ]]; then
				codex_missing=1
			elif [[ "$detail" == *'(external; migration required)'* || "$detail" == *'shadowed by'* ]]; then
				codex_conflict=1
			fi
		fi
		case "$result" in
		missing) ((++miss_count)) ;;
		*) ((++check_count)) ;;
		esac
		((${#component} > width)) && width="${#component}"
		attention+=("$row")
	done

	((miss_count + check_count > 0)) || return 0

	# The one useful thing the Doctor screen did that the table does not: pull
	# the handful that need attention out of twenty rows that do not.
	printf '\n'
	rt_print_section 'Needs attention'
	for row in "${attention[@]}"; do
		IFS='|' read -r component detail result <<<"$row"
		printf '    %-*s  %s\n' "$width" "$component" "$detail"
	done

	printf '\n'
	rt_print_section 'Suggested'
	((codex_missing > 0)) &&
		printf '    Run initial setup and select Codex CLI:  dotfiles menu\n'
	if ((codex_conflict > 0)); then
		codex_path="$(codex_active_command 2>/dev/null || true)"
		printf '    Resolve the conflicting Codex command:  %s\n' "${codex_path:-unknown}"
		printf '    See README.md#codex-cli-migration.\n'
	fi
	((miss_count > 0)) &&
		printf '    Install what is missing:  dotfiles menu  (Install Dotfiles)\n'
	((check_count > 0)) &&
		printf '    Re-check after updating:  dotfiles update\n'
	printf '    Repair stow links only:   dotfiles restow\n'
	return 1
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
		case "$install_result" in
		failed)
			detail="installer failed; $detail"
			result=failed
			;;
		# Never attempted, so whatever the probe found is what was already on
		# the machine -- saying "installed" here would credit the run for it.
		not-run)
			detail="not run (apt index refresh failed); $detail"
			result=check
			;;
		esac
		case "$result" in
		installed | configured) ((++ok_count)) ;;
		*) ((++miss_count)) ;;
		esac
		rt_print_table_row "$label" "$detail" "$result"
	done

	echo ""
	if [[ $miss_count -eq 0 ]]; then
		echo "  Install finished — ${ok_count} component(s) look good."
	else
		echo "  Install finished — ${ok_count} ok, ${miss_count} need attention (see log above)."
	fi
}
