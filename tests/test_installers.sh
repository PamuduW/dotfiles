#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317  # Loader paths and indirect test doubles.
# Individual installers: Stow, apt, remote vendor scripts, GitHub releases,
# containers, fonts, and the WSL config writer. Several of these are safety
# assertions -- payloads are verified before execution and failures must not
# be swallowed.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"

test_backup_includes_existing_dotfiles_launcher() (
	local fake_home="$TEST_HARNESS_ROOT/stow-home"
	local fake_repo="$TEST_HARNESS_ROOT/stow-repo"
	mkdir -p "$fake_home/bin" "$fake_repo"
	printf 'old launcher\n' >"$fake_home/bin/dotfiles"
	log_step() { :; }
	log_ok() { :; }
	HOME="$fake_home" DOTFILES_DIR="$fake_repo" backup_existing_dotfiles
	[[ ! -e "$fake_home/bin/dotfiles" ]]
	find "$fake_repo" -path '*/bin/dotfiles' -type f -print -quit | grep -q .
)
test_backup_includes_existing_remote_control_helpers() (
	local fake_home="$TEST_HARNESS_ROOT/stow-rc-home"
	local fake_repo="$TEST_HARNESS_ROOT/stow-rc-repo"
	mkdir -p "$fake_home/bin" "$fake_repo"
	printf 'old codex helper\n' >"$fake_home/bin/codex-rc"
	log_step() { :; }
	log_ok() { :; }
	HOME="$fake_home" DOTFILES_DIR="$fake_repo" backup_existing_dotfiles
	[[ ! -e "$fake_home/bin/codex-rc" ]] || return 1
	find "$fake_repo" -path '*/bin/codex-rc' -type f -print -quit | grep -q .
)

test_backup_includes_existing_git_wrapper() (
	local fake_home="$TEST_HARNESS_ROOT/stow-git-home"
	local fake_repo="$TEST_HARNESS_ROOT/stow-git-repo"
	mkdir -p "$fake_home/bin" "$fake_repo"
	printf 'old git wrapper\n' >"$fake_home/bin/git"
	log_step() { :; }
	log_ok() { :; }
	HOME="$fake_home" DOTFILES_DIR="$fake_repo" backup_existing_dotfiles
	[[ ! -e "$fake_home/bin/git" ]]
	find "$fake_repo" -path '*/bin/git' -type f -print -quit | grep -q .
)

test_failed_stow_restores_backed_up_user_files() (
	local fake_home="$TEST_HARNESS_ROOT/stow-rollback-home"
	local fake_repo="$TEST_HARNESS_ROOT/stow-rollback-repo"
	mkdir -p "$fake_home/bin" "$fake_repo"
	printf 'user bashrc\n' >"$fake_home/.bashrc"
	printf 'user launcher\n' >"$fake_home/bin/dotfiles"
	log_step() { :; }
	log_ok() { :; }
	stow() { return 23; }
	HOME="$fake_home" DOTFILES_DIR="$fake_repo" backup_existing_dotfiles
	if HOME="$fake_home" DOTFILES_DIR="$fake_repo" stow_dotfiles >/dev/null 2>&1; then return 1; fi
	[[ "$(<"$fake_home/.bashrc")" == 'user bashrc' ]]
	[[ "$(<"$fake_home/bin/dotfiles")" == 'user launcher' ]]
)

test_apt_install_failure_is_not_hidden_by_warning_logging() (
	local pkg_file="$TEST_HARNESS_ROOT/failing-apt-packages.txt" rc
	printf '%s\n' '# @core' 'git' >"$pkg_file"
	PKG_FILE="$pkg_file"
	_run_quiet_command() { return 26; }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	set +e
	apt_install_packages core >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" == 26 ]]
)

test_tool_installers_stop_at_the_first_required_failure() (
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	ensure_asdf_installed() { return 0; }
	asdf() { [[ "$1 $2" == 'plugin list' ]] && printf 'golang\n'; }
	local call=0 rc
	_run_quiet_command() {
		call=$((call + 1))
		[[ "$call" -ne 1 ]] || return 27
	}
	set +e
	install_go_via_asdf >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" == 27 ]] || return 1

	codex_cli_install_state() { printf '%s\n' absent; }
	codex_sync_standalone() { return 28; }
	set +e
	install_codex_cli >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" == 28 ]]
)

test_container_installers_stop_at_the_first_required_failure() (
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		[[ "$1" == ps ]] && return 0
		[[ "$1 $2" != 'image inspect' ]] || printf 'sha256:target\n'
		[[ "$1 $2" != 'volume create' ]] || return 29
		return 0
	}
	local rc
	set +e
	install_portainer >/dev/null 2>&1
	rc=$?
	set -e
	[[ "$rc" == 29 ]]
)

test_portainer_fresh_install_uses_lts_without_starting_container() (
	local calls="$TEST_HARNESS_ROOT/portainer-fresh.calls"
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		[[ "$1" != ps ]] || return 0
		[[ "$1 $2" != 'image inspect' ]] || printf 'sha256:target\n'
	}

	install_portainer >/dev/null

	grep -Fxq 'pull portainer/portainer-ce:lts' "$calls" || return 1
	grep -Fxq 'volume create portainer_data' "$calls" || return 1
	grep -Fq 'create -p 8000:8000 -p 9443:9443 --name portainer --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:lts' "$calls" || return 1
	! grep -Eq '^(run|start|stop) ' "$calls"
)

test_portainer_matching_lts_image_is_left_unchanged() (
	local calls="$TEST_HARNESS_ROOT/portainer-current.calls"
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1 $2" in
		'ps -a') printf 'portainer\n' ;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format') printf 'sha256:target\n' ;;
		esac
	}

	install_portainer >/dev/null

	grep -Fxq 'pull portainer/portainer-ce:lts' "$calls" || return 1
	! grep -Eq '^(rm|create|stop) ' "$calls"
)

_portainer_managed_layout_reply() {
	case "$1" in
	'{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Name}}{{end}}{{end}}') printf 'volume:portainer_data\n' ;;
	'{{range .Mounts}}{{if eq .Destination "/var/run/docker.sock"}}{{.Type}}:{{.Source}}{{end}}{{end}}') printf 'bind:/var/run/docker.sock\n' ;;
	'{{with index .HostConfig.PortBindings "8000/tcp"}}{{(index . 0).HostPort}}{{end}}') printf '8000\n' ;;
	'{{with index .HostConfig.PortBindings "9443/tcp"}}{{(index . 0).HostPort}}{{end}}') printf '9443\n' ;;
	'{{.HostConfig.RestartPolicy.Name}}') printf 'unless-stopped\n' ;;
	*) return 1 ;;
	esac
}

test_portainer_managed_legacy_container_is_recreated_with_its_data() (
	local calls="$TEST_HARNESS_ROOT/portainer-migrate.calls"
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1 $2" in
		'ps -a') printf 'portainer\n' ;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format')
			case "$3" in
			'{{.Image}}') printf 'sha256:legacy\n' ;;
			'{{.State.Running}}') printf 'false\n' ;;
			*) _portainer_managed_layout_reply "$3" || true ;;
			esac
			;;
		esac
	}

	install_portainer >/dev/null

	grep -Fxq 'rename portainer portainer.agentbot-backup' "$calls" || return 1
	grep -Fq 'create -p 8000:8000 -p 9443:9443 --name portainer --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:lts' "$calls" || return 1
	grep -Fxq 'rm -f portainer.agentbot-backup' "$calls" || return 1
	! grep -Fxq 'rm -f portainer' "$calls" || return 1
	! grep -Eq '^(start|stop) ' "$calls" || return 1
	! grep -Eq 'volume (rm|create) portainer_data' "$calls" || return 1
)

test_portainer_running_container_is_stopped_before_the_replacement_starts() (
	# Break caught: the renamed backup kept holding ports 8000 and 9443, so the
	# replacement could never start and every update of a running Portainer
	# rolled back and reported failure.
	local calls="$TEST_HARNESS_ROOT/portainer-running-replace.calls"
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1 $2" in
		'ps -a')
			if grep -Fxq 'rename portainer portainer.agentbot-backup' "$calls"; then
				printf 'portainer\nportainer.agentbot-backup\n'
			else
				printf 'portainer\n'
			fi
			;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format')
			case "$3" in
			'{{.Image}}') printf 'sha256:legacy\n' ;;
			'{{.State.Running}}') printf 'true\n' ;;
			*) _portainer_managed_layout_reply "$3" || true ;;
			esac
			;;
		esac
		return 0
	}

	install_portainer >/dev/null || return 1

	grep -Fxq 'stop portainer.agentbot-backup' "$calls" || return 1
	grep -Fxq 'start portainer' "$calls" || return 1
	grep -Fxq 'rm -f portainer.agentbot-backup' "$calls" || return 1
	# The backup has to be stopped before the replacement starts, and removed
	# only once that start is confirmed.
	local stop_line start_line remove_line
	stop_line="$(grep -Fxn 'stop portainer.agentbot-backup' "$calls" | head -1 | cut -d: -f1)"
	start_line="$(grep -Fxn 'start portainer' "$calls" | head -1 | cut -d: -f1)"
	remove_line="$(grep -Fxn 'rm -f portainer.agentbot-backup' "$calls" | head -1 | cut -d: -f1)"
	((stop_line < start_line)) || return 1
	((start_line < remove_line)) || return 1
	! grep -Fxq 'rm -f portainer' "$calls" || return 1
	! grep -Eq 'volume (rm|create) portainer_data' "$calls"
)

test_portainer_start_failure_restores_and_restarts_the_original() (
	local calls="$TEST_HARNESS_ROOT/portainer-start-fail.calls" rc
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1 $2" in
		'ps -a')
			if grep -Fxq 'rename portainer portainer.agentbot-backup' "$calls" &&
				! grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls"; then
				printf 'portainer\nportainer.agentbot-backup\n'
			else
				printf 'portainer\n'
			fi
			;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format')
			case "$3" in
			'{{.Image}}') printf 'sha256:legacy\n' ;;
			'{{.State.Running}}') printf 'true\n' ;;
			*) _portainer_managed_layout_reply "$3" || true ;;
			esac
			;;
		esac
		# Only the replacement's start fails; the restore path's start works.
		if [[ "$1 $2" == 'start portainer' ]] &&
			! grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls"; then
			return 45
		fi
		return 0
	}

	set +e
	install_portainer >/dev/null 2>&1
	rc=$?
	set -e

	[[ "$rc" == 45 ]] || return 1
	grep -Fxq 'stop portainer.agentbot-backup' "$calls" || return 1
	grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls" || return 1
	# The original must come back running, not left stopped by the aborted swap.
	[[ "$(grep -Fxc 'start portainer' "$calls")" == 2 ]] || return 1
	! grep -Fxq 'rm -f portainer.agentbot-backup' "$calls"
)

test_portainer_create_failure_restores_the_original_running_container() (
	local calls="$TEST_HARNESS_ROOT/portainer-create-fail.calls" rc
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1 $2" in
		'ps -a')
			if grep -Fxq 'rename portainer portainer.agentbot-backup' "$calls" &&
				! grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls"; then
				printf 'portainer.agentbot-backup\n'
			else
				printf 'portainer\n'
			fi
			;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format')
			case "$3" in
			'{{.Image}}') printf 'sha256:legacy\n' ;;
			'{{.State.Running}}') printf 'true\n' ;;
			*) _portainer_managed_layout_reply "$3" || true ;;
			esac
			;;
		esac
		[[ "$1" != create ]] || return 44
		return 0
	}

	set +e
	install_portainer >/dev/null 2>&1
	rc=$?
	set -e

	[[ "$rc" == 44 ]] || return 1
	grep -Fxq 'rename portainer portainer.agentbot-backup' "$calls" || return 1
	grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls" || return 1
	grep -Fxq 'start portainer' "$calls" || return 1
	! grep -Fxq 'rm -f portainer' "$calls" || return 1
	! grep -Eq 'volume (rm|create) portainer_data' "$calls" || return 1
)

test_portainer_verify_failure_removes_the_partial_replacement() (
	local calls="$TEST_HARNESS_ROOT/portainer-verify-fail.calls" rc created=0
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1" in
		create)
			created=1
			return 0
			;;
		esac
		case "$1 $2" in
		'ps -a') printf 'portainer\n' ;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format')
			case "$3" in
			'{{.Image}}') printf 'sha256:legacy\n' ;;
			'{{.State.Running}}') printf 'false\n' ;;
			*)
				if ((created)); then
					printf 'bind:\n'
				else
					_portainer_managed_layout_reply "$3" || true
				fi
				;;
			esac
			;;
		esac
	}

	set +e
	install_portainer >/dev/null 2>&1
	rc=$?
	set -e

	[[ "$rc" -ne 0 ]] || return 1
	grep -Fxq 'rename portainer portainer.agentbot-backup' "$calls" || return 1
	grep -Fxq 'rm -f portainer' "$calls" || return 1
	grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls" || return 1
	! grep -Eq '^start ' "$calls" || return 1
	! grep -Eq 'volume (rm|create) portainer_data' "$calls" || return 1
)

test_portainer_interrupted_backup_is_restored_before_retry() (
	local calls="$TEST_HARNESS_ROOT/portainer-interrupt.calls"
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1 $2" in
		'ps -a')
			if grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls"; then
				printf 'portainer\n'
			else
				printf 'portainer.agentbot-backup\n'
			fi
			;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format')
			case "$3" in
			'{{.Image}}') printf 'sha256:legacy\n' ;;
			'{{.State.Running}}') printf 'false\n' ;;
			*) _portainer_managed_layout_reply "$3" || true ;;
			esac
			;;
		esac
	}

	install_portainer >/dev/null

	grep -Fxq 'rename portainer.agentbot-backup portainer' "$calls" || return 1
	grep -Fxq 'rename portainer portainer.agentbot-backup' "$calls" || return 1
	! grep -Eq 'volume (rm|create) portainer_data' "$calls" || return 1
)

test_portainer_custom_container_is_not_replaced() (
	local calls="$TEST_HARNESS_ROOT/portainer-custom.calls" rc
	: >"$calls"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	run_docker() {
		printf '%s\n' "$*" >>"$calls"
		case "$1 $2" in
		'ps -a') printf 'portainer\n' ;;
		'image inspect') printf 'sha256:target\n' ;;
		'inspect --format')
			case "$3" in
			'{{.Image}}') printf 'sha256:legacy\n' ;;
			'{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Name}}{{end}}{{end}}') printf 'bind:\n' ;;
			esac
			;;
		esac
	}

	set +e
	install_portainer >/dev/null 2>&1
	rc=$?
	set -e

	[[ "$rc" -ne 0 ]] || return 1
	! grep -Eq '^(rm|create|stop) ' "$calls"
)

test_monaspace_upgrade_requests_a_replacement_install() (
	[[ "$(declare -f upgrade_monaspace)" == *'install_monaspace_fonts --replace'* ]]
)

test_remote_shell_installers_are_downloaded_before_execution() (
	! rg -n 'curl[^|]*\|[[:space:]]*(bash|sh)' "$REPO_DIR/scripts/lib/installers" "$REPO_DIR/scripts/lib/update_components.sh"
)

test_remote_shell_installer_fails_closed() (
	local calls="$TEST_HARNESS_ROOT/vendor-installer.calls" output_path=''
	: >"$calls"
	curl() {
		printf 'curl\n' >>"$calls"
		while (($#)); do
			if [[ "$1" == -o ]]; then
				output_path="$2"
				shift 2
			else shift; fi
		done
		: >"$output_path"
	}
	set +e
	run_vendor_shell_installer 'http://example.invalid/install.sh' Example >/dev/null 2>&1
	local insecure_rc=$?
	run_vendor_shell_installer 'https://example.invalid/install.sh' Example >/dev/null 2>&1
	local empty_rc=$?
	set -e
	[[ "$insecure_rc" -ne 0 && "$empty_rc" -ne 0 ]] || return 1
	[[ "$(wc -l <"$calls")" -eq 1 ]]
)

test_release_manifest_must_name_the_selected_archive() (
	local calls="$TEST_HARNESS_ROOT/release-installer.calls"
	: >"$calls"
	github_latest_release_version() { printf '1.2.3\n'; }
	_linux_github_arch_suffix() { printf 'x86_64\n'; }
	log_step() { :; }
	github_curl() {
		local output='' arg
		while (($#)); do
			arg="$1"
			shift
			if [[ "$arg" == -o ]]; then
				output="$1"
				shift
			fi
		done
		if [[ "$output" == *checksums.txt ]]; then
			printf '%064d  unrelated.tar.gz\n' 0 >"$output"
		else
			: >"$output"
		fi
	}
	sha256sum() {
		printf 'sha256sum\n' >>"$calls"
		return 0
	}
	tar() {
		printf 'tar\n' >>"$calls"
		return 0
	}
	sudo() {
		printf 'sudo\n' >>"$calls"
		return 0
	}
	set +e
	install_lazygit_from_github >/dev/null 2>&1
	local rc=$?
	set -e
	[[ "$rc" -ne 0 && ! -s "$calls" ]]
)

test_wsl_config_renderer_updates_only_the_requested_section() (
	local conf="$TEST_HARNESS_ROOT/wsl-render.conf" rendered="$TEST_HARNESS_ROOT/wsl-rendered.conf"
	printf '%s\n' '[interop]' 'systemd=true' 'appendWindowsPath=false' '' '[boot]' 'appendWindowsPath=true' >"$conf"
	wsl_conf_render_required "$conf" >"$rendered"
	wsl_conf_has_setting "$rendered" boot systemd true || return 1
	wsl_conf_has_setting "$rendered" interop appendWindowsPath true || return 1
	grep -Fqx 'systemd=true' "$rendered"
)

check 'Stow backup includes an existing dotfiles launcher' test_backup_includes_existing_dotfiles_launcher
check 'Stow backup includes an existing codex-rc helper' test_backup_includes_existing_remote_control_helpers
check 'Stow backup includes an existing Git wrapper' test_backup_includes_existing_git_wrapper
check 'failed Stow application restores backed-up user files' test_failed_stow_restores_backed_up_user_files
check 'apt installation failures are not hidden by warning logging' test_apt_install_failure_is_not_hidden_by_warning_logging
check 'tool installers stop at the first required command failure' test_tool_installers_stop_at_the_first_required_failure
check 'container installers stop at the first required command failure' test_container_installers_stop_at_the_first_required_failure
check 'Portainer fresh installs use LTS and remain stopped' test_portainer_fresh_install_uses_lts_without_starting_container
check 'Portainer current LTS containers are left unchanged' test_portainer_matching_lts_image_is_left_unchanged
check 'Portainer managed legacy containers retain their data' test_portainer_managed_legacy_container_is_recreated_with_its_data
check 'Portainer create failure restores the original running container' test_portainer_create_failure_restores_the_original_running_container
check 'Portainer running container is stopped before the replacement starts' test_portainer_running_container_is_stopped_before_the_replacement_starts
check 'Portainer start failure restores and restarts the original' test_portainer_start_failure_restores_and_restarts_the_original
check 'Portainer verify failure removes the partial replacement' test_portainer_verify_failure_removes_the_partial_replacement
check 'Portainer interrupted backup is restored before retry' test_portainer_interrupted_backup_is_restored_before_retry
check 'Portainer custom containers are not replaced' test_portainer_custom_container_is_not_replaced
check 'Monaspace upgrades replace an older installed release' test_monaspace_upgrade_requests_a_replacement_install
check 'remote shell installers are downloaded before execution' test_remote_shell_installers_are_downloaded_before_execution
check 'remote shell installers reject insecure and empty payloads' test_remote_shell_installer_fails_closed
check 'release checksums must identify the selected archive' test_release_manifest_must_name_the_selected_archive
check 'WSL config rendering updates settings only in their required sections' test_wsl_config_renderer_updates_only_the_requested_section

test_harness_cleanup
finish_tests
