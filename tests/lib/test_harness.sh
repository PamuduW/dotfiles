#!/usr/bin/env bash
# shellcheck shell=bash

test_harness_cleanup() {
	local root="${TEST_HARNESS_ROOT:-}"
	[[ -n "$root" && "$root" != "/" && -d "$root" ]] || return 0
	rm -rf -- "$root"
}

test_harness_teardown() {
	local original_status=$? protected_status=0
	trap - EXIT

	if [[ -n "${TEST_HARNESS_ROOT:-}" && -d "$TEST_HARNESS_ROOT" ]]; then
		test_harness_verify_protected_paths || protected_status=$?
		test_harness_cleanup
	fi

	if ((protected_status != 0)); then
		exit 94
	fi
	exit "$original_status"
}

test_harness_init() {
	local temp_base
	if [[ -n "${TEST_HARNESS_ROOT:-}" ]]; then
		return 0
	fi

	ORIGINAL_HOME="${HOME:-}"
	ORIGINAL_PATH="${PATH:-/usr/bin:/bin}"
	ORIGINAL_TMPDIR="${TMPDIR:-}"
	temp_base="${TMPDIR:-/tmp}"
	TEST_HARNESS_ROOT="$(mktemp -d "$temp_base/dotfiles-test-harness.XXXXXX")"
	trap test_harness_teardown EXIT
	if [[ "${TEST_HARNESS_FAIL_AFTER_ROOT:-}" == "1" ]]; then
		printf 'injected harness init failure after root creation\n' >&2
		return 93
	fi
	HOME="$TEST_HARNESS_ROOT/home"
	XDG_CONFIG_HOME="$TEST_HARNESS_ROOT/xdg"
	TMPDIR="$TEST_HARNESS_ROOT/tmp"
	TEST_FAKE_BIN="$TEST_HARNESS_ROOT/bin"
	TEST_FAKE_CONFIG="$TEST_HARNESS_ROOT/config"
	TEST_FAKE_SIBLINGS="$TEST_HARNESS_ROOT/siblings"
	TEST_COMMAND_LOG="$TEST_HARNESS_ROOT/log/commands.log"
	TEST_URL_LOG="$TEST_HARNESS_ROOT/log/urls.log"

	mkdir -p -- \
		"$HOME" \
		"$XDG_CONFIG_HOME" \
		"$TMPDIR" \
		"$TEST_FAKE_BIN" \
		"$TEST_FAKE_CONFIG" \
		"$TEST_FAKE_SIBLINGS" \
		"$(dirname -- "$TEST_COMMAND_LOG")"
	: >"$TEST_COMMAND_LOG"
	: >"$TEST_URL_LOG"

	export ORIGINAL_HOME ORIGINAL_PATH ORIGINAL_TMPDIR TEST_HARNESS_ROOT HOME XDG_CONFIG_HOME TMPDIR
	export TEST_FAKE_BIN TEST_FAKE_CONFIG TEST_FAKE_SIBLINGS
	export TEST_COMMAND_LOG TEST_URL_LOG
	PATH="$TEST_FAKE_BIN:$ORIGINAL_PATH"
	export PATH

	test_harness_write_fake_dispatcher
	ln -s -- _test_fake_command "$TEST_FAKE_BIN/git"
	ln -s -- _test_fake_command "$TEST_FAKE_BIN/curl"
	ln -s -- _test_fake_command "$TEST_FAKE_BIN/npx"

}

test_harness_fingerprint_path() {
	local path="$1" entry relative name_hash metadata content_hash target_hash
	if [[ ! -e "$path" && ! -L "$path" ]]; then
		printf '%s\n' 'MISSING'
		return 0
	fi

	{
		while IFS= read -r -d '' entry; do
			if [[ "$entry" == "$path" ]]; then
				relative='.'
			else
				relative="${entry#"$path"/}"
			fi
			name_hash="$(printf '%s' "$relative" | sha256sum | awk '{print $1}')"
			metadata="$(stat -c '%F|%a|%u|%g|%s|%Y' -- "$entry")"
			printf 'entry=%s|meta=%s|' "$name_hash" "$metadata"
			if [[ -L "$entry" ]]; then
				target_hash="$(readlink -- "$entry" | sha256sum | awk '{print $1}')"
				printf 'link=%s\n' "$target_hash"
			elif [[ -f "$entry" ]]; then
				content_hash="$(sha256sum -- "$entry" | awk '{print $1}')"
				printf 'file=%s\n' "$content_hash"
			else
				printf '%s\n' 'non-file'
			fi
		done < <(find -P "$path" -print0 | sort -z)
	} | sha256sum | awk '{print $1}'
}

test_harness_protect_original_path() {
	local relative="$1" protected_dir id path
	[[ -n "${TEST_HARNESS_ROOT:-}" && -d "$TEST_HARNESS_ROOT" ]] || return 92
	[[ -n "${ORIGINAL_HOME:-}" ]] || return 92
	if [[ -z "$relative" || "$relative" == /* || "$relative" == *$'\n'* || "$relative" == *$'\r'* ]]; then
		printf 'protected path must be a safe relative original-home path\n' >&2
		return 92
	fi
	case "/$relative/" in
	*/../* | */./*)
		printf 'protected path may not contain dot traversal segments\n' >&2
		return 92
		;;
	esac

	protected_dir="$TEST_HARNESS_ROOT/protected"
	mkdir -p -- "$protected_dir"
	id="$(printf '%s' "$relative" | sha256sum | awk '{print $1}')"
	path="$ORIGINAL_HOME/$relative"
	printf '%s\n' "$relative" >"$protected_dir/$id.path"
	test_harness_fingerprint_path "$path" >"$protected_dir/$id.before"
}

test_harness_verify_protected_paths() {
	local protected_dir="${TEST_HARNESS_ROOT:-}/protected"
	local path_file id relative before after changed=0
	[[ -d "$protected_dir" ]] || return 0

	for path_file in "$protected_dir"/*.path; do
		[[ -f "$path_file" ]] || continue
		id="${path_file##*/}"
		id="${id%.path}"
		IFS= read -r relative <"$path_file"
		before="$(<"$protected_dir/$id.before")"
		test_harness_fingerprint_path "$ORIGINAL_HOME/$relative" >"$protected_dir/$id.after"
		after="$(<"$protected_dir/$id.after")"
		if [[ "$before" != "$after" ]]; then
			printf 'protected original-home path changed during test: %s\n' "$relative" >&2
			changed=1
		fi
	done
	((changed == 0))
}

test_harness_write_fake_dispatcher() {
	local dispatcher="$TEST_FAKE_BIN/_test_fake_command"
	# shellcheck disable=SC2016  # These lines are the generated script, not current-shell expansions.
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'set -u' \
		'command_name="${TEST_FAKE_COMMAND_NAME:-$(basename -- "$0")}"' \
		'config_dir="${TEST_FAKE_CONFIG:?}"' \
		'command_log="${TEST_COMMAND_LOG:?}"' \
		'url_log="${TEST_URL_LOG:?}"' \
		'sanitize() {' \
		'  local value="$1" secret="${TEST_CANARY_SECRET:-}" scheme rest' \
		'  value="${value//$'"'"'\n'"'"'/ }"' \
		'  value="${value//$'"'"'\r'"'"'/ }"' \
		'  value="${value//$'"'"'\t'"'"'/ }"' \
		'  if [[ -n "$secret" ]]; then value="${value//"$secret"/[redacted]}"; fi' \
		'  case "$value" in' \
		'    Authorization:*|authorization:*) value="Authorization: [redacted]" ;;' \
		'    GITHUB_TOKEN=*|GH_TOKEN=*) value="${value%%=*}=[redacted]" ;;' \
		'  esac' \
		'  if [[ "$value" == http://*@* || "$value" == https://*@* ]]; then' \
		'    scheme="${value%%://*}"' \
		'    rest="${value#*://}"' \
		'    value="${scheme}://[redacted]@${rest#*@}"' \
		'  fi' \
		'  printf "%s" "$value"' \
		'}' \
		'printf "%s" "$command_name" >>"$command_log"' \
		'for arg in "$@"; do' \
		'  safe="$(sanitize "$arg")"' \
		'  printf "\t%s" "$safe" >>"$command_log"' \
		'  if [[ "$arg" == http://* || "$arg" == https://* ]]; then printf "%s\n" "$safe" >>"$url_log"; fi' \
		'done' \
		'printf "\n" >>"$command_log"' \
		'if [[ ! -f "$config_dir/$command_name.exit" ]]; then' \
		'  printf "blocked unconfigured fake command: %s\n" "$command_name" >&2' \
		'  exit 97' \
		'fi' \
		'if [[ -s "$config_dir/$command_name.stdout" ]]; then' \
		'  while IFS= read -r line || [[ -n "$line" ]]; do printf "%s\n" "$(sanitize "$line")"; done <"$config_dir/$command_name.stdout"' \
		'fi' \
		'if [[ -s "$config_dir/$command_name.stderr" ]]; then' \
		'  while IFS= read -r line || [[ -n "$line" ]]; do printf "%s\n" "$(sanitize "$line")" >&2; done <"$config_dir/$command_name.stderr"' \
		'fi' \
		'read -r rc <"$config_dir/$command_name.exit"' \
		'exit "$rc"' \
		>"$dispatcher"
	chmod 700 "$dispatcher"
}

test_harness_configure_fake() {
	local name="$1" rc="$2" stdout="${3:-}" stderr="${4:-}"
	[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]
	[[ "$rc" =~ ^[0-9]+$ && "$rc" -le 255 ]]
	printf '%s\n' "$rc" >"$TEST_FAKE_CONFIG/$name.exit"
	printf '%s' "$stdout" >"$TEST_FAKE_CONFIG/$name.stdout"
	printf '%s' "$stderr" >"$TEST_FAKE_CONFIG/$name.stderr"
}

test_harness_clear_fake() {
	local name="$1"
	[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]
	rm -f -- \
		"$TEST_FAKE_CONFIG/$name.exit" \
		"$TEST_FAKE_CONFIG/$name.stdout" \
		"$TEST_FAKE_CONFIG/$name.stderr"
}

test_harness_reset_logs() {
	: >"$TEST_COMMAND_LOG"
	: >"$TEST_URL_LOG"
}

test_harness_sanitize() {
	local value="$1" secret="${TEST_CANARY_SECRET:-}" scheme rest
	value="${value//$'\n'/ }"
	value="${value//$'\r'/ }"
	value="${value//$'\t'/ }"
	if [[ -n "$secret" ]]; then
		value="${value//"$secret"/[redacted]}"
	fi
	case "$value" in
	Authorization:* | authorization:*) value='Authorization: [redacted]' ;;
	GITHUB_TOKEN=* | GH_TOKEN=*) value="${value%%=*}=[redacted]" ;;
	esac
	if [[ "$value" == http://*@* || "$value" == https://*@* ]]; then
		scheme="${value%%://*}"
		rest="${value#*://}"
		value="${scheme}://[redacted]@${rest#*@}"
	fi
	printf '%s' "$value"
}

test_harness_log_call() {
	local name="$1" arg safe
	shift
	printf '%s' "$(test_harness_sanitize "$name")" >>"$TEST_COMMAND_LOG"
	for arg in "$@"; do
		safe="$(test_harness_sanitize "$arg")"
		printf '\t%s' "$safe" >>"$TEST_COMMAND_LOG"
		if [[ "$arg" == http://* || "$arg" == https://* ]]; then
			printf '%s\n' "$safe" >>"$TEST_URL_LOG"
		fi
	done
	printf '\n' >>"$TEST_COMMAND_LOG"
}

test_harness_create_fake_sibling() {
	local name="$1" sibling installer
	[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]
	sibling="$TEST_FAKE_SIBLINGS/$name"
	installer="$sibling/install.sh"
	mkdir -p -- "$sibling"
	# shellcheck disable=SC2016  # Expand TEST_FAKE_BIN when the generated installer runs.
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'TEST_FAKE_COMMAND_NAME=sibling-install exec "${TEST_FAKE_BIN:?}/_test_fake_command" "$@"' \
		>"$installer"
	chmod 700 "$installer"
	printf '%s\n' "$sibling"
}

test_harness_invoke_relaunch() {
	local wrapper="${TEST_RELAUNCH_WRAPPER:-}"
	if [[ -z "$wrapper" || "$(type -t "$wrapper" || true)" != "function" ]]; then
		printf 'test relaunch wrapper is not configured\n' >&2
		return 96
	fi
	"$wrapper" "$@"
}

test_harness_assert_isolated_path() {
	local path="$1"
	case "$path" in
	"$HOME" | "$HOME"/* | "$XDG_CONFIG_HOME" | "$XDG_CONFIG_HOME"/*) return 0 ;;
	*)
		printf 'refusing path outside isolated HOME/XDG roots\n' >&2
		return 95
		;;
	esac
}
