#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# Component status probes: what each probe reports for present, absent,
# and partially configured components.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

test_python_probe_requires_python_pip_and_venv() (
	local fake_bin="$TEST_HARNESS_ROOT/python-empty-bin"
	mkdir -p "$fake_bin"
	local output
	output="$(PATH="$fake_bin" _comp_probe_python)"
	[[ "$output" == missing\|* ]]
)

test_go_probe_does_not_treat_empty_asdf_as_installed() (
	local fake_bin="$TEST_HARNESS_ROOT/go-empty-bin"
	mkdir -p "$fake_bin"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/asdf"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$fake_bin/go"
	chmod +x "$fake_bin/asdf" "$fake_bin/go"
	local output
	output="$(PATH="$fake_bin:/usr/bin:/bin" _comp_probe_go)"
	[[ "$output" == missing\|* ]]
)

test_dotfiles_probe_requires_every_managed_link() (
	local fake_home="$TEST_HARNESS_ROOT/partial-dotfiles-home"
	mkdir -p "$fake_home/bin"
	: >"$fake_home/bin/ex"
	local output
	output="$(HOME="$fake_home" _comp_probe_dotfiles)"
	[[ "$output" == missing\|* || "$output" == check\|* ]]
)

test_wsl_probe_requires_both_settings() (
	local conf="$TEST_HARNESS_ROOT/wsl.conf"
	printf '[boot]\nsystemd=true\n' >"$conf"
	local output
	output="$(DOTFILES_WSL_CONF="$conf" _comp_probe_wsl_conf)"
	[[ "$output" == check\|* ]]
)

test_absent_optional_components_are_counted_as_missing() (
	local fake_home="$TEST_HARNESS_ROOT/absent-components-home"
	local git_config="$TEST_HARNESS_ROOT/empty-gitconfig"
	mkdir -p "$fake_home"
	: >"$git_config"
	[[ "$(HOME="$fake_home" GIT_CONFIG_GLOBAL="$git_config" GIT_CONFIG_NOSYSTEM=1 _comp_probe_git_identity)" == missing\|* ]]
	[[ "$(HOME="$fake_home" _comp_probe_ssh_key)" == missing\|* ]]
)

test_system_package_probe_uses_system_package_tags_only() (
	local pkg_file="$TEST_HARNESS_ROOT/scoped-packages.txt" output
	printf '%s\n' \
		'# @core' 'core-package' \
		'# @python' 'python-package' \
		'# @cli' 'cli-package' \
		'# @system' 'system-package' >"$pkg_file"
	local queried="$TEST_HARNESS_ROOT/scoped-packages.queried"
	: >"$queried"
	# The probe asks dpkg-query about every owned package in one call and reads
	# one status line per package, so the stub answers in batch.
	dpkg-query() {
		local arg
		for arg in "$@"; do
			[[ "$arg" == -* ]] && continue
			printf '%s\n' "$arg" >>"$queried"
			case "$arg" in
			core-package | cli-package | system-package) printf 'install ok installed\n' ;;
			*) printf 'unknown ok not-installed\n' ;;
			esac
		done
	}
	output="$(PKG_FILE="$pkg_file" _comp_probe_system_packages)"
	[[ "$output" == 'installed|3 apt packages' ]] || return 1
	# python-package belongs to the python component and must not be queried.
	[[ "$(sort "$queried" | tr '\n' ' ')" == 'cli-package core-package system-package ' ]] || return 1
	# and it must be one batched call, not one process per package
	[[ "$(wc -l <"$queried")" -eq 3 ]]
)

test_update_probes_find_vendor_local_bin_installations() (
	local local_bin="$HOME/.local/bin" output
	mkdir -p "$local_bin"
	printf '#!/usr/bin/env bash\nprintf "cursor-local\\n"\n' >"$local_bin/agent"
	printf '#!/usr/bin/env bash\nprintf "claude-local\\n"\n' >"$local_bin/claude"
	chmod +x "$local_bin/agent" "$local_bin/claude"
	output="$(PATH="$TEST_FAKE_BIN:/usr/bin:/bin" cursor_installed_version)"
	[[ "$output" == cursor-local ]] || return 1
	output="$(PATH="$TEST_FAKE_BIN:/usr/bin:/bin" claude_installed_version)"
	[[ "$output" == claude-local ]]
)

check 'Python probe verifies interpreter pip and venv support' test_python_probe_requires_python_pip_and_venv
check 'Go probe rejects an asdf installation without a selected Go version' test_go_probe_does_not_treat_empty_asdf_as_installed
check 'Dotfiles probe requires every managed Stow target' test_dotfiles_probe_requires_every_managed_link
check 'WSL probe verifies both required settings' test_wsl_probe_requires_both_settings
check 'absent optional components remain visible in status rollups' test_absent_optional_components_are_counted_as_missing
check 'system package status checks only the packages owned by that component' test_system_package_probe_uses_system_package_tags_only
check 'update probes find Cursor and Claude in the vendor local bin directory' test_update_probes_find_vendor_local_bin_installations

test_harness_cleanup
finish_tests
