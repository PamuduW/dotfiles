#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init

test_harness_report_init

source "$ROOT/scripts/lib/installers/logging.sh"
source "$ROOT/scripts/lib/installers/graphify.sh"

test_forced_reinstall_reaches_the_installer() (
	# Break caught: the forced branch was written as
	# `skip_unless_forced ... || return 1`, meaning "fall through" but returning
	# failure. Every forced run reported Graphify as a failed component while
	# installing nothing.
	local calls="$TEST_HARNESS_ROOT/graphify-forced.calls"
	: >"$calls"
	graphify_command() { printf '%s\n' /fake/graphify; }
	graphify_cli_is_uv_owned() { return 0; }
	ensure_graphify_uv() { return 0; }
	graphify_uv_command() { printf 'true\n'; }
	_run_quiet_command() {
		printf 'installed\n' >>"$calls"
		return 0
	}

	# Unforced: already present, so nothing runs.
	(DOTFILES_FORCE_REINSTALL=0 install_graphify_cli) >/dev/null || return 1
	[[ ! -s "$calls" ]] || return 1

	# Forced: the installer runs, and the component does not report failure.
	(DOTFILES_FORCE_REINSTALL=1 install_graphify_cli) >/dev/null || return 1
	grep -Fqx installed "$calls"
)

test_a_non_uv_graphify_is_preserved_even_when_forced() (
	# Force reinstalls what this repository owns. An installation uv did not
	# create is somebody else's, and replacing it is not ours to do.
	local calls="$TEST_HARNESS_ROOT/graphify-external.calls"
	: >"$calls"
	graphify_command() { printf '%s\n' /usr/local/bin/graphify; }
	graphify_cli_is_uv_owned() { return 1; }
	ensure_graphify_uv() {
		printf 'touched\n' >>"$calls"
		return 0
	}

	(DOTFILES_FORCE_REINSTALL=1 install_graphify_cli) >/dev/null || return 1
	[[ ! -s "$calls" ]]
)

test_install_missing_graphify_uses_official_package() (
	local calls="$TEST_HARNESS_ROOT/graphify-install.calls"
	: >"$calls"
	PATH="$HOME/.local/bin:$PATH"
	export PATH
	graphify_command() {
		[[ -x "$HOME/.local/bin/graphify" ]] || return 1
		printf '%s\n' "$HOME/.local/bin/graphify"
	}
	uv() {
		printf 'uv:%s\n' "$*" >>"$calls"
		case "$*" in
		'tool list') return 0 ;;
		'tool install graphifyy')
			mkdir -p "$HOME/.local/bin"
			printf '%s\n' '#!/usr/bin/env bash' 'printf "graphify 1.2.3\\n"' >"$HOME/.local/bin/graphify"
			chmod +x "$HOME/.local/bin/graphify"
			;;
		*) return 97 ;;
		esac
	}
	install_graphify_cli >/dev/null
	grep -Fqx 'uv:tool install graphifyy' "$calls"
	[[ -x "$HOME/.local/bin/graphify" ]]
)

test_install_existing_external_graphify_is_preserved() (
	local calls="$TEST_HARNESS_ROOT/graphify-external.calls"
	: >"$calls"
	graphify() { [[ "$1" == --version ]] && printf 'graphify 9.9.9\n'; }
	uv() {
		printf 'uv:%s\n' "$*" >>"$calls"
		[[ "$*" == 'tool list' ]] && return 0
		return 97
	}
	install_graphify_cli >/dev/null
	! grep -Fq 'tool install graphifyy' "$calls"
)

test_install_existing_uv_graphify_is_idempotent() (
	local calls="$TEST_HARNESS_ROOT/graphify-owned.calls"
	: >"$calls"
	graphify() { [[ "$1" == --version ]] && printf 'graphify 1.2.3\n'; }
	uv() {
		printf 'uv:%s\n' "$*" >>"$calls"
		[[ "$*" == 'tool list' ]] && printf 'graphifyy v1.2.3\n'
	}
	install_graphify_cli >/dev/null
	! grep -Fq 'tool install graphifyy' "$calls"
)

test_missing_uv_uses_official_astral_installer() (
	local calls="$TEST_HARNESS_ROOT/uv-bootstrap.calls"
	: >"$calls"
	graphify_uv_command() {
		[[ -x "$HOME/.local/bin/uv" ]] || return 1
		printf '%s\n' "$HOME/.local/bin/uv"
	}
	curl() {
		printf 'curl:%s\n' "$*" >>"$calls"
		printf '%s\n' \
			'printf "UV-INSTALLER-NOISE\\n"' \
			'mkdir -p "$HOME/.local/bin"' \
			'printf "%s\\n" "#!/usr/bin/env bash" "exit 0" >"$HOME/.local/bin/uv"' \
			'chmod +x "$HOME/.local/bin/uv"'
	}
	local output
	output="$(ensure_graphify_uv 2>&1)" || return 1
	grep -Fqx 'curl:-LsSf https://astral.sh/uv/install.sh' "$calls" || return 1
	[[ -x "$HOME/.local/bin/uv" ]] || return 1
	# The vendor script narrates its own progress and the step reports its own
	# result, so the narration stays out of the run transcript.
	[[ "$output" != *UV-INSTALLER-NOISE* ]]
)

expect_success 'forced reinstall reaches the installer' test_forced_reinstall_reaches_the_installer
expect_success 'a non-uv Graphify is preserved even when forced' test_a_non_uv_graphify_is_preserved_even_when_forced
expect_success 'missing Graphify installs the official graphifyy package' test_install_missing_graphify_uses_official_package
expect_success 'external Graphify installations are preserved' test_install_existing_external_graphify_is_preserved
expect_success 'uv-owned Graphify installation is idempotent' test_install_existing_uv_graphify_is_idempotent
expect_success 'missing uv uses the official Astral installer' test_missing_uv_uses_official_astral_installer

finish_tests
