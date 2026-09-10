#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# One Python process per command (ADR-0001). What is worth pinning here is not
# that the verbs work -- their own suites cover the readings and the layout --
# but the two things that make a coprocess different from a script: the answers
# must be identical to running those scripts standalone, and the ways bash takes
# the descriptors away must fail to a fallback rather than to a wrong table.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1

if ! command -v python3 >/dev/null 2>&1; then
	printf 'ok - python service skipped; python3 unavailable\n'
	exit 0
fi

# shellcheck source=scripts/lib/shared/py_service.sh
source "$REPO_DIR/scripts/lib/shared/py_service.sh"
PY_DIR="$REPO_DIR/scripts/lib/shared/python"

passed=0
failed=0
expect() {
	local label="$1" want="$2" got="$3"
	if [[ "$got" == "$want" ]]; then
		printf 'ok - %s\n' "$label"
		passed=$((passed + 1))
	else
		printf 'not ok - %s\n     want: %s\n     got:  %s\n' "$label" "$want" "$got"
		failed=$((failed + 1))
	fi
}

py_service_available || {
	printf 'not ok - the service starts\n'
	exit 1
}
expect 'the service answers a ping' ok "$(py_service_call ping </dev/null)"

# Classification through the service must equal classification by the script it
# replaced. Same requests, same order, same bytes.
requests=$'stow_targets\x1f0\nstow_targets\x1f3\nportainer\x1f1\x1f1\x1f'
expect 'classify matches the standalone script' \
	"$(printf '%s\n' "$requests" | python3 "$PY_DIR/probe_classify.py")" \
	"$(py_service_call classify < <(printf '%s\n' "$requests"))"

rows=$'Git identity|Ada <ada@example.com>|configured\nDocker Engine|29.8.0|installed\nApply dotfiles|8 targets missing|missing'
expect 'render matches the standalone renderer' \
	"$(printf '%s\n' "$rows" | python3 "$PY_DIR/render_report.py" --cols 80 --rollup --title 'Check Status')" \
	"$(py_service_call render --cols 80 --rollup --title 'Check Status' < <(printf '%s\n' "$rows"))"

expect 'repo status matches the standalone checker' \
	"$(python3 "$PY_DIR/repo_status.py" "$REPO_DIR" --label 'Dotfiles repo' --timeout 5)" \
	"$(py_service_call repo_status "$REPO_DIR" 'Dotfiles repo' 5 </dev/null)"

# Bash closes coprocess descriptors in the children it forks for a pipeline, so
# the payload arrives on a descriptor that is no longer there. The call must
# fail rather than half-answer: every caller has a Bash path, and a partial
# table is the one outcome that would not reach it. This is why the client says
# to feed payloads with a process substitution.
pipeline_out="$(printf 'stow_targets\x1f0\n' | py_service_call classify 2>/dev/null)"
pipeline_rc=$?
expect 'a call used as a pipeline element fails' 1 "$pipeline_rc"
expect 'and answers nothing at all' '' "$pipeline_out"

# The failed call never reached the service, so nothing is out of step: the
# child could not write, and the parent's request/response is where it was. The
# next call must still be answered rather than the whole command dropping to
# Bash because one caller used the wrong form.
expect 'a failed pipeline call leaves the service usable' \
	'installed|stow bash bin readline' \
	"$(py_service_call classify < <(printf 'stow_targets\x1f0\n'))"

py_service_stop

# And the switch that turns it off is honoured, so the Bash paths stay reachable
# on a machine that has python3.
(
	_PY_SERVICE_STATE=unstarted
	DOTFILES_PY_SERVICE=0
	py_service_available
	exit_code=$?
	[[ "$exit_code" -eq 1 ]]
) && printf 'ok - DOTFILES_PY_SERVICE=0 keeps the service off\n' && passed=$((passed + 1)) ||
	{ printf 'not ok - DOTFILES_PY_SERVICE=0 keeps the service off\n' && failed=$((failed + 1)); }

printf '\nRan %d python-service test(s); %d failure(s).\n' "$((passed + failed))" "$failed"
((failed == 0))
