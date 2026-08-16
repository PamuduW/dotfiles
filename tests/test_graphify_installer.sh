#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/test_harness.sh
source "$TEST_DIR/lib/test_harness.sh"
test_harness_init

test_harness_report_init

source "$ROOT/scripts/lib/installers/logging.sh"
source "$ROOT/scripts/lib/installers/graphify.sh"

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
			'mkdir -p "$HOME/.local/bin"' \
			'printf "%s\\n" "#!/usr/bin/env bash" "exit 0" >"$HOME/.local/bin/uv"' \
			'chmod +x "$HOME/.local/bin/uv"'
	}
	ensure_graphify_uv >/dev/null
	grep -Fqx 'curl:-LsSf https://astral.sh/uv/install.sh' "$calls"
	[[ -x "$HOME/.local/bin/uv" ]]
)

expect_success 'missing Graphify installs the official graphifyy package' test_install_missing_graphify_uses_official_package
expect_success 'external Graphify installations are preserved' test_install_existing_external_graphify_is_preserved
expect_success 'uv-owned Graphify installation is idempotent' test_install_existing_uv_graphify_is_idempotent
expect_success 'missing uv uses the official Astral installer' test_missing_uv_uses_official_astral_installer

finish_tests
