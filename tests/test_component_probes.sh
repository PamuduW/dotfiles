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
test_dotfiles_probe_requires_remote_control_helper_links() (
	local fake_home="$TEST_HARNESS_ROOT/remote-control-links-home"
	local target
	mkdir -p "$fake_home/bin"
	ln -s "$REPO_DIR/bash/.bashrc" "$fake_home/.bashrc"
	ln -s "$REPO_DIR/bash/.bash_aliases" "$fake_home/.bash_aliases"
	ln -s "$REPO_DIR/readline/.inputrc" "$fake_home/.inputrc"
	for target in ex clip dotfiles; do
		ln -s "$REPO_DIR/bin/bin/$target" "$fake_home/bin/$target"
	done
	local output
	output="$(HOME="$fake_home" _comp_probe_dotfiles)"
	[[ "$output" == 'missing|2 managed stow target(s) missing or incorrect' ]]
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
			# The probe asks for `${Package} ${Status}` so it can match an
			# installed name back to the entry that offered it.
			case "$arg" in
			core-package | cli-package | system-package) printf '%s install ok installed\n' "$arg" ;;
			*) printf '%s unknown ok not-installed\n' "$arg" ;;
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

test_python_probe_checks_every_owned_apt_package() (
	local pkg_file="$TEST_HARNESS_ROOT/python-packages.txt" output
	printf '%s\n' \
		'# @python' python3 python3-pip python3-venv python3-pil >"$pkg_file"
	dpkg-query() {
		local arg
		for arg in "$@"; do
			[[ "$arg" == -* ]] && continue
			case "$arg" in
			python3-pil) printf '%s unknown ok not-installed\n' "$arg" ;;
			*) printf '%s install ok installed\n' "$arg" ;;
			esac
		done
	}
	python3() { return 0; }
	output="$(PKG_FILE="$pkg_file" _comp_probe_python)"
	[[ "$output" == 'missing|1 of 4 Python packages not installed' ]]
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

test_portainer_classification_covers_every_state() (
	# ADR-0001's second amendment: a classification must be reachable without
	# its interrogation. The integration test below builds a fake docker binary
	# per state, which is why two states have never been covered -- producing a
	# timeout means having a docker that times out.
	#
	# Split out, the reading is a pure function and every state is one call.
	# Defect 5 in docs/history/bootstrap-clean-machine-testing.md lived here.
	local got

	# docker absent entirely: not a judgement about the container.
	got="$(_comp_classify_portainer 0 0 '')"
	[[ "$got" == 'missing|docker is not installed' ]] || return 1

	# Timed out: says nothing either way. Never covered before this test.
	got="$(_comp_classify_portainer 1 124 '')"
	[[ "$got" == 'check|portainer probe timed out' ]] || return 1

	# The daemon refused the query -- the defect-5 case. "check", never
	# "missing": the docker group is granted during the same run and is not
	# active until the next session.
	got="$(_comp_classify_portainer 1 1 '')"
	[[ "$got" == check\|*'new docker group'* ]] || return 1

	# Found, and found despite a non-zero status, which a daemon can return
	# alongside usable output.
	got="$(_comp_classify_portainer 1 0 portainer)"
	[[ "$got" == 'installed|container exists (stopped by default)' ]] || return 1
	got="$(_comp_classify_portainer 1 1 portainer)"
	[[ "$got" == 'installed|container exists (stopped by default)' ]] || return 1

	# Reachable, answered, and the container genuinely is not there.
	got="$(_comp_classify_portainer 1 0 '')"
	[[ "$got" == 'missing|portainer container not found' ]] || return 1

	# A timeout outranks a name that arrived anyway: partial output from a
	# timed-out query is not evidence.
	got="$(_comp_classify_portainer 1 124 portainer)"
	[[ "$got" == 'check|portainer probe timed out' ]]
)

test_portainer_probe_separates_an_unreachable_daemon_from_a_missing_container() (
	# Break caught: the probe ran `docker ps -a` as the current user and read any
	# failure as "container not found". The docker group is granted during the
	# same install run and is not active until the next session, so a Portainer
	# that had just been created reported missing.
	local fake_bin="$TEST_HARNESS_ROOT/portainer-probe-bin"
	mkdir -p -- "$fake_bin"
	cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'permission denied while trying to connect to the Docker daemon socket
' >&2
exit 1
EOF
	chmod +x -- "$fake_bin/docker"

	local output
	output="$(PATH="$fake_bin:/usr/bin:/bin" _comp_probe_portainer)"
	[[ "$output" == check\|* ]] || return 1
	[[ "$output" == *'new docker group'* ]] || return 1

	# A reachable daemon with no such container still reports missing.
	cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x -- "$fake_bin/docker"
	output="$(PATH="$fake_bin:/usr/bin:/bin" _comp_probe_portainer)"
	[[ "$output" == missing\|*'not found'* ]] || return 1

	# And a reachable daemon that has it reports installed.
	cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'portainer
'
EOF
	chmod +x -- "$fake_bin/docker"
	output="$(PATH="$fake_bin:/usr/bin:/bin" _comp_probe_portainer)"
	[[ "$output" == installed\|* ]]
)

test_codex_installed_but_not_on_path_is_not_shadowed() (
	# Break caught: a standalone Codex at the managed path with nothing else
	# claiming the name was reported "shadowed", which routed the component into
	# the npm migration. That found no npm Codex and failed the component --
	# right after a successful install, because ~/.local/bin was not yet on the
	# PATH of the session doing the installing.
	local root="$TEST_HARNESS_ROOT/codex-state"
	local bin="$root/.local/bin"
	local pkg="$root/.codex/packages/standalone/releases/1.0.0/bin"
	mkdir -p -- "$bin" "$pkg"
	printf '#!/usr/bin/env bash\nprintf "codex 1.0.0\\n"\n' >"$pkg/codex"
	chmod +x -- "$pkg/codex"
	ln -sfn "$pkg/codex" "$bin/codex"

	local state
	# Nothing named codex on PATH: installed, just not reachable yet.
	state="$(HOME="$root" CODEX_HOME="$root/.codex" CODEX_INSTALL_DIR="$bin" \
		PATH="/usr/bin:/bin" codex_cli_install_state)"
	[[ "$state" == standalone-not-on-path ]] || return 1

	# On PATH: fully active.
	state="$(HOME="$root" CODEX_HOME="$root/.codex" CODEX_INSTALL_DIR="$bin" \
		PATH="$bin:/usr/bin:/bin" codex_cli_install_state)"
	[[ "$state" == standalone ]] || return 1

	# A different codex winning on PATH is still a genuine shadow.
	local foreign="$root/foreign"
	mkdir -p -- "$foreign"
	printf '#!/usr/bin/env bash\nprintf "other\\n"\n' >"$foreign/codex"
	chmod +x -- "$foreign/codex"
	state="$(HOME="$root" CODEX_HOME="$root/.codex" CODEX_INSTALL_DIR="$bin" \
		PATH="$foreign:/usr/bin:/bin" codex_cli_install_state)"
	[[ "$state" == standalone-shadowed ]]
)

check 'Codex installed but not on PATH is not reported as shadowed' test_codex_installed_but_not_on_path_is_not_shadowed
test_package_probe_counts_a_renamed_package_as_present() (
	# Break caught: the probe passed the raw `preferred|fallback` entry to
	# dpkg-query, which knows no such package, so a package installed under its
	# current name was still counted missing.
	local pkg_file="$TEST_HARNESS_ROOT/probe-renamed-packages.txt"
	printf '%s\n' '# @system' 'bind9-dnsutils|dnsutils  # dns tools' 'git  # vcs' >"$pkg_file"

	local fake_bin="$TEST_HARNESS_ROOT/probe-dpkg-bin"
	mkdir -p -- "$fake_bin"
	# Only the new name is installed on this imaginary release.
	cat >"$fake_bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
	case "$arg" in
	bind9-dnsutils | git) printf '%s install ok installed
' "$arg" ;;
	esac
done
EOF
	chmod +x -- "$fake_bin/dpkg-query"

	comp_package_tags() { printf 'system
'; }
	local checked=0 output
	output="$(PATH="$fake_bin:$PATH" PKG_FILE="$pkg_file" \
		_comp_probe_apt_packages_for_component system_packages packages checked && printf 'all-present\n')"
	[[ "$output" == all-present ]]
)

check 'package probe counts a renamed package as present' test_package_probe_counts_a_renamed_package_as_present
test_tool_resolution_ignores_windows_binaries_reached_through_interop() (
	# Break caught: appendWindowsPath puts the Windows PATH on ours, so
	# `command -v cursor` returned the Windows editor. The installer skipped as
	# though the Linux CLI were present, and the probe then invoked a Windows
	# binary through interop and timed out -- on every single run.
	local root="$TEST_HARNESS_ROOT/interop"
	rm -rf -- "$root"
	mkdir -p -- "$root/win" "$root/linux"
	printf '#!/bin/sh\necho windows\n' >"$root/win/cursor"
	printf '#!/bin/sh\necho linux\n' >"$root/linux/agent"
	chmod +x -- "$root/win/cursor" "$root/linux/agent"

	# Only a Windows cursor on PATH: nothing usable.
	local resolved rc=0
	resolved="$(PATH="$root/win:/usr/bin:/bin" HOME="$root" \
		DOTFILES_WINDOWS_MOUNT_ROOT="$root/win" tool_resolve 'agent cursor')" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1

	# A Linux one is still found, and preferred over the Windows name.
	resolved="$(PATH="$root/linux:$root/win:/usr/bin:/bin" HOME="$root" \
		DOTFILES_WINDOWS_MOUNT_ROOT="$root/win" tool_resolve 'agent cursor')" || return 1
	[[ "$resolved" == "$root/linux/agent" ]]
)

check 'tool resolution ignores Windows binaries reached through interop' test_tool_resolution_ignores_windows_binaries_reached_through_interop
check 'Portainer probe separates an unreachable daemon from a missing container' test_portainer_probe_separates_an_unreachable_daemon_from_a_missing_container
check 'Python probe verifies interpreter pip and venv support' test_python_probe_requires_python_pip_and_venv
check 'Go probe rejects an asdf installation without a selected Go version' test_go_probe_does_not_treat_empty_asdf_as_installed
check 'Dotfiles probe requires every managed Stow target' test_dotfiles_probe_requires_every_managed_link
check 'Dotfiles probe requires the Codex Remote Control helper link' test_dotfiles_probe_requires_remote_control_helper_links
check 'WSL probe verifies both required settings' test_wsl_probe_requires_both_settings
check 'absent optional components remain visible in status rollups' test_absent_optional_components_are_counted_as_missing
check 'system package status checks only the packages owned by that component' test_system_package_probe_uses_system_package_tags_only
check 'Python package status checks every apt package owned by the component' test_python_probe_checks_every_owned_apt_package
check 'portainer classification covers every state without a docker' test_portainer_classification_covers_every_state
check 'update probes find Cursor and Claude in the vendor local bin directory' test_update_probes_find_vendor_local_bin_installations

test_harness_cleanup
finish_tests
