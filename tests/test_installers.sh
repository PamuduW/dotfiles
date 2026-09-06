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

test_unavailable_packages_do_not_block_the_available_ones() (
	# Break caught: apt-get install is all-or-nothing, so one package dropped
	# from a new Ubuntu release left all 53 uninstalled -- which then failed the
	# dotfiles component, because stow was among the casualties.
	local pkg_file="$TEST_HARNESS_ROOT/mixed-apt-packages.txt"
	local calls="$TEST_HARNESS_ROOT/mixed-apt.calls" warnings="$TEST_HARNESS_ROOT/mixed-apt.warn"
	printf '%s\n' '# @core' 'git' 'gone-from-this-release' 'stow' >"$pkg_file"
	: >"$calls"
	: >"$warnings"
	PKG_FILE="$pkg_file"
	apt_package_is_available() { [[ "$1" != 'gone-from-this-release' ]]; }
	_run_quiet_command() {
		shift
		printf '%s\n' "$*" >>"$calls"
	}
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { printf '%s\n' "$*" >>"$warnings"; }

	apt_install_packages core >/dev/null 2>&1 || return 1

	grep -q 'git' "$calls" || return 1
	grep -q 'stow' "$calls" || return 1
	! grep -q 'gone-from-this-release' "$calls" || return 1
	grep -q 'gone-from-this-release' "$warnings"
)

test_all_packages_unavailable_is_reported_not_installed() (
	local pkg_file="$TEST_HARNESS_ROOT/absent-apt-packages.txt"
	local calls="$TEST_HARNESS_ROOT/absent-apt.calls" rc=0
	printf '%s\n' '# @core' 'gone-one' 'gone-two' >"$pkg_file"
	: >"$calls"
	PKG_FILE="$pkg_file"
	apt_package_is_available() { return 1; }
	_run_quiet_command() { printf 'called\n' >>"$calls"; }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }

	apt_install_packages core >/dev/null 2>&1 || rc=$?
	[[ "$rc" -eq 0 ]] || return 1
	# apt is never invoked with an empty package list.
	[[ ! -s "$calls" ]]
)

test_a_new_repository_refreshes_only_its_own_source_list() (
	# A bare `apt-get update` re-fetches every configured index. On a cold
	# machine that was the dominant cost of adding one vendor repository, and
	# the preamble had already refreshed everything else moments earlier.
	local calls="$TEST_HARNESS_ROOT/apt-refresh.calls"
	local list="$TEST_HARNESS_ROOT/vendor.sources"
	: >"$calls"
	: >"$list"
	sudo() { printf '%s\n' "$*" >>"$calls"; }

	apt_refresh_source_list "$list" || return 1
	grep -q "Dir::Etc::sourcelist=$list" "$calls" || return 1
	grep -q 'sourceparts=-' "$calls" || return 1
	[[ "$(grep -c 'apt-get update' "$calls")" -eq 1 ]]
)

test_a_missing_source_list_still_refreshes_everything() (
	# Never leave a component installing against an index that does not list
	# what it is about to ask for.
	local calls="$TEST_HARNESS_ROOT/apt-refresh-missing.calls"
	: >"$calls"
	sudo() { printf '%s\n' "$*" >>"$calls"; }

	apt_refresh_source_list "$TEST_HARNESS_ROOT/not-there.sources" \
		"$TEST_HARNESS_ROOT/also-not-there.list" || return 1
	grep -q 'apt-get update' "$calls" || return 1
	! grep -q 'Dir::Etc::sourcelist' "$calls"
)

test_renamed_packages_fall_back_to_the_available_name() (
	# Break caught: `dnsutils` became `bind9-dnsutils` and the transitional name
	# was dropped in a later release, so the tool went missing on new machines
	# even though the package was right there under its current name.
	local pkg_file="$TEST_HARNESS_ROOT/renamed-apt-packages.txt"
	local calls="$TEST_HARNESS_ROOT/renamed-apt.calls"
	printf '%s\n' '# @core' 'bind9-dnsutils|dnsutils' 'git' >"$pkg_file"
	: >"$calls"
	PKG_FILE="$pkg_file"
	# Only the new name exists on this imaginary release.
	apt_package_is_available() { [[ "$1" != dnsutils ]]; }
	_run_quiet_command() {
		shift
		printf '%s\n' "$*" >>"$calls"
	}
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }

	apt_install_packages core >/dev/null 2>&1 || return 1
	grep -q 'bind9-dnsutils' "$calls" || return 1
	! grep -qw 'dnsutils$' "$calls"
)

test_a_rename_falls_back_to_the_older_name_when_needed() (
	local pkg_file="$TEST_HARNESS_ROOT/renamed-old-apt.txt"
	local calls="$TEST_HARNESS_ROOT/renamed-old-apt.calls"
	printf '%s\n' '# @core' 'bind9-dnsutils|dnsutils' >"$pkg_file"
	: >"$calls"
	PKG_FILE="$pkg_file"
	# Only the transitional name exists on this older release.
	apt_package_is_available() { [[ "$1" == dnsutils ]]; }
	_run_quiet_command() {
		shift
		printf '%s\n' "$*" >>"$calls"
	}
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }

	apt_install_packages core >/dev/null 2>&1 || return 1
	grep -qw 'dnsutils' "$calls"
)

test_powershell_skips_a_release_with_no_microsoft_feed() (
	local warnings="$TEST_HARNESS_ROOT/pwsh.warn" rc=0
	: >"$warnings"
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { printf '%s\n' "$*" >>"$warnings"; }
	command() {
		[[ "$*" == '-v pwsh' ]] && return 1
		builtin command "$@"
	}
	apt_package_is_available() { [[ "$1" != powershell ]]; }
	sudo() { :; }
	wget() { :; }
	# Runs the command, like the real wrapper: this test is about the feed
	# fallback, not about where apt's output goes.
	_run_quiet_command() {
		shift
		"$@"
	}

	install_powershell_from_github() {
		printf 'github-fallback\n' >>"$warnings"
		return 0
	}
	install_powershell >/dev/null 2>&1 || rc=$?
	# Not in the feed is not the end of the road: fall back to the upstream
	# release rather than leaving the component uninstalled.
	grep -q 'not in the Microsoft feed' "$warnings" || return 1
	grep -q 'github-fallback' "$warnings"
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

	grep -Fxq 'pull -q portainer/portainer-ce:lts' "$calls" || return 1
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

	grep -Fxq 'pull -q portainer/portainer-ce:lts' "$calls" || return 1
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
check 'unavailable packages do not block the available ones' test_unavailable_packages_do_not_block_the_available_ones
check 'all packages unavailable is reported, not installed' test_all_packages_unavailable_is_reported_not_installed
check 'a new repository refreshes only its own source list' test_a_new_repository_refreshes_only_its_own_source_list
check 'a missing source list still refreshes everything' test_a_missing_source_list_still_refreshes_everything
check 'renamed packages fall back to the available name' test_renamed_packages_fall_back_to_the_available_name
check 'a rename falls back to the older name when needed' test_a_rename_falls_back_to_the_older_name_when_needed
check 'PowerShell falls back to the upstream release' test_powershell_skips_a_release_with_no_microsoft_feed
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
