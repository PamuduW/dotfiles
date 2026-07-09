# shellcheck shell=bash
# Shared helpers for Agents menu status and git-sync reports.

_agent_bootstrap_status_json() {
	local ab_home="$1"

	[[ -x "$ab_home/install.sh" ]] || return 1
	(
		cd "$ab_home" || exit 1
		./install.sh status --json 2>/dev/null
	)
}

_agent_json_get() {
	local json="$1"
	local key="$2"
	python3 - "$json" "$key" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
value = data.get(sys.argv[2])
if value is None:
    raise SystemExit(1)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

_agents_count_row() {
	local result="$1"
	case "$result" in
	ok | installed | configured) ((++_agents_ok_count)) ;;
	check | drift | extra) ((++_agents_check_count)) ;;
	missing | failed) ((++_agents_miss_count)) ;;
	skipped*) ;;
	esac
}

_agents_print_row() {
	local component="$1"
	local detail="$2"
	local result="$3"

	_agents_count_row "$result"
	ui_print_report_table_row "$component" "$detail" "$result"
}
