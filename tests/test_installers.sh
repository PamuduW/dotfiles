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
source "$TEST_DIR/lib/runtime_failure_fixture.sh"

portainer_catalog_fixture() {
	TEST_PORTAINER_IMAGE="portainer/portainer-ce@sha256:$(printf '%064d' 0)"
	printf '%s\n' $'portainer\towner\tany\tdotfiles' $'portainer\tkind\tany\tsoftware' \
		$'portainer\tversion\tany\t2.0.0' $'portainer\tpackage\tany\tportainer/portainer-ce' \
		$'portainer\tdigest\tany\tsha256:'"$(printf '%064d' 0)" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-portainer"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-portainer"
}

test_an_unreachable_docker_does_not_accuse_the_container() (
	portainer_catalog_fixture
	# Break caught: the layout check returned 1 both when the container was
	# somebody else's and when Docker could not be queried at all, so a session
	# that merely predates the docker group was told its Portainer container had
	# a custom layout -- a claim about the container made without looking at it.
	local warnings="$TEST_HARNESS_ROOT/portainer-layout.warn"
	: >"$warnings"
	log_warn() { printf '%s\n' "$*" >>"$warnings"; }
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	_portainer_name_exists() { return 0; }
	_portainer_recover_interrupted() { return 0; }
	run_docker() {
		case "$*" in
		"pull -q"*) return 0 ;;
		"image inspect"*) printf 'sha256:target\n' ;;
		"inspect --format {{.Image}} portainer") printf 'sha256:other\n' ;;
		# Everything the layout check asks is refused, as it is before the
		# docker group takes effect in a new session.
		inspect*) return 1 ;;
		*) return 0 ;;
		esac
	}

	local rc=0
	install_portainer >/dev/null 2>&1 || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	grep -q 'Cannot inspect the Portainer container' "$warnings" || return 1
	! grep -q 'custom layout' "$warnings"
)

test_portainer_recovery_preserves_unowned_resources() (
	portainer_catalog_fixture
	local calls="$TEST_HARNESS_ROOT/portainer-recovery.calls" foreign rc
	log_step() { :; }
	log_ok() { :; }
	log_skip() { :; }
	log_warn() { :; }
	for foreign in portainer.agentbot-backup portainer; do
		: >"$calls"
		run_docker() {
			printf '%s\n' "$*" >>"$calls"
			case "$1 $2" in
			'ps -a') printf 'portainer\nportainer.agentbot-backup\n' ;;
			'image inspect') printf 'sha256:target\n' ;;
			'inspect --format')
				case "$3" in
				'{{.Image}}') printf 'sha256:legacy\n' ;;
				'{{.State.Running}}') printf 'false\n' ;;
				'{{index .Config.Labels "com.pamuduw.dotfiles.catalog"}}')
					[[ "$4" == "$foreign" ]] || printf '%064d\n' 0
					;;
				*) _portainer_managed_layout_reply "$3" || true ;;
				esac
				;;
			esac
			return 0
		}
		rc=0
		install_portainer >/dev/null 2>&1 || rc=$?
		[[ "$rc" != 0 ]] || {
			echo "FAIL: recovery accepted unowned $foreign" >&2
			return 1
		}
		! grep -Eq '^(rm|rename|start|stop|create) ' "$calls" || {
			echo "FAIL: recovery changed resources around unowned $foreign" >&2
			return 1
		}
	done
)

test_component_dispatch_preserves_reinstall_flag() (
	local calls="$TEST_HARNESS_ROOT/force.calls"
	: >"$calls"
	install_lazygit_from_github() { printf '%s\n' "${DOTFILES_FORCE_REINSTALL:-0}" >>"$calls"; }
	DOTFILES_FORCE_REINSTALL=0 _comp_install_lazygit || return 1
	DOTFILES_FORCE_REINSTALL=1 _comp_install_lazygit || return 1
	[[ "$(cat "$calls")" == $'0\n1' ]]
)

test_docker_daemon_config_is_written_one_way_only() (
	# Break caught: a fresh install emitted its own JSON literal while an
	# existing file went through the Python merge, and the two disagreed on key
	# order. The first full-update on every new machine therefore found a
	# difference, backed the file up, rewrote it without changing what the
	# configuration means, and restarted Docker to do it.
	local machine="$TEST_HARNESS_ROOT/docker-daemon"
	local fake_bin="$machine/bin" etc="$machine/etc-docker"
	mkdir -p -- "$fake_bin" "$etc"
	# sudo runs the command directly: every path here is inside the sandbox.
	printf '#!/usr/bin/env bash\nexec "$@"\n' >"$fake_bin/sudo"
	chmod +x -- "$fake_bin/sudo"

	_run_configure() (
		export PATH="$fake_bin:$PATH"
		export DOCKER_DAEMON_JSON="$etc/daemon.json"
		log_warn() { :; }
		log_step() { :; }
		log_skip() { printf 'SKIP\n'; }
		log_ok() { printf 'WROTE\n'; }
		configure_docker_daemon
	)

	local first second
	first="$(_run_configure)" || return 1
	[[ "$first" == WROTE ]] || return 1
	[[ -f "$etc/daemon.json" ]] || return 1

	# The second run is the one that used to rewrite and back up: both paths
	# must now produce the same bytes.
	second="$(_run_configure)" || return 1
	[[ "$second" == SKIP ]] || return 1
	# And nothing was backed up, because nothing changed.
	[[ -z "$(find "$etc" -name 'daemon.json.bak.*' -print -quit)" ]]
)

test_a_failed_daemon_config_write_is_not_a_change() (
	# Review 2, R2-12: the final `sudo install` was unchecked, so a failed write
	# still set DOCKER_DAEMON_CHANGED, logged success, and restarted Docker.
	local machine="$TEST_HARNESS_ROOT/docker-daemon-fail"
	local fake_bin="$machine/bin" etc="$machine/etc-docker" output rc=0
	mkdir -p -- "$fake_bin" "$etc"
	printf '#!/usr/bin/env bash\n[[ "$1" == install ]] && exit 1\nexec "$@"\n' >"$fake_bin/sudo"
	chmod +x -- "$fake_bin/sudo"

	output="$(
		export PATH="$fake_bin:$PATH"
		export DOCKER_DAEMON_JSON="$etc/daemon.json"
		DOCKER_DAEMON_CHANGED=0
		log_warn() { :; }
		log_step() { :; }
		log_ok() { printf 'WROTE\n'; }
		configure_docker_daemon || exit $?
		printf 'changed=%s\n' "$DOCKER_DAEMON_CHANGED"
	)" || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	[[ "$output" != *WROTE* ]] || return 1
	[[ ! -e "$etc/daemon.json" ]]
)

test_git_identity_without_a_name_reports_instead_of_crashing() (
	# Break caught: apply_git_config read SETUP_GIT_NAME unguarded, so a caller
	# that never collected it killed the entire run with "unbound variable"
	# instead of reporting the one component it could not do.
	local warnings="$TEST_HARNESS_ROOT/git-identity.warn" rc=0
	: >"$warnings"
	log_ok() { :; }
	log_warn() { printf '%s\n' "$*" >>"$warnings"; }
	git() { printf 'git-was-called\n' >>"$warnings"; }

	(
		set -u
		unset SETUP_GIT_NAME SETUP_GIT_EMAIL
		apply_git_config
	) || rc=$?
	[[ "$rc" -ne 0 ]] || return 1
	grep -q 'needs a name and email' "$warnings" || return 1
	# And it stopped before touching the operator's global git config.
	! grep -q 'git-was-called' "$warnings"
)

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

test_powershell_does_not_fall_back_when_approved_target_is_missing() (
	local calls="$TEST_HARNESS_ROOT/pwsh-fallback.calls"
	: >"$calls"
	apt_package_is_available() {
		printf 'feed-query\n' >>"$calls"
		return 1
	}
	install_powershell_from_github() { printf 'floating-fallback\n' >>"$calls"; }
	sudo() { printf 'sudo\n' >>"$calls"; }
	wget() { printf 'wget\n' >>"$calls"; }
	if install_powershell >/dev/null 2>&1; then return 1; fi
	[[ ! -s "$calls" ]]
)

test_tool_installers_stop_at_the_first_required_failure() (
	runtime_failure_fixture go
	local rc=0
	install_go_via_asdf >"$HOME/output" 2>&1 || rc=$?
	[[ "$rc" == 27 && "$(cat "$TEST_RUNTIME_FAILURE_CALLS")" == 'download:https://fixture.invalid/asdf' ]] || return 1
	[[ "$("$HOME/.local/bin/go" version)" == 'go 1.2.2' ]] || return 1
	codex_cli_install_state() { printf '%s\n' absent; }
	codex_sync_standalone() { return 28; }
	rc=0
	install_codex_cli >/dev/null 2>&1 || rc=$?
	[[ "$rc" == 28 ]]
)

test_container_installers_stop_at_the_first_required_failure() (
	portainer_catalog_fixture
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

test_portainer_fresh_install_uses_digest_without_starting_container() (
	portainer_catalog_fixture
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

	grep -Fxq "pull -q $TEST_PORTAINER_IMAGE" "$calls" || return 1
	grep -Fxq 'volume create portainer_data' "$calls" || return 1
	grep -Fq "create -p 8000:8000 -p 9443:9443 --name portainer --label com.pamuduw.dotfiles.catalog=$SOFTWARE_CATALOG_DIGEST --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data $TEST_PORTAINER_IMAGE" "$calls" || return 1
	! grep -Eq '^(run|start|stop) ' "$calls"
)

test_portainer_matching_digest_image_is_left_unchanged() (
	portainer_catalog_fixture
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

	grep -Fxq "pull -q $TEST_PORTAINER_IMAGE" "$calls" || return 1
	! grep -Eq '^(rm|create|stop) ' "$calls"
)

_portainer_managed_layout_reply() {
	case "$1" in
	'{{index .Config.Labels "com.pamuduw.dotfiles.catalog"}}') printf '%064d\n' 0 ;;
	'{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Name}}{{end}}{{end}}') printf 'volume:portainer_data\n' ;;
	'{{range .Mounts}}{{if eq .Destination "/var/run/docker.sock"}}{{.Type}}:{{.Source}}{{end}}{{end}}') printf 'bind:/var/run/docker.sock\n' ;;
	'{{with index .HostConfig.PortBindings "8000/tcp"}}{{(index . 0).HostPort}}{{end}}') printf '8000\n' ;;
	'{{with index .HostConfig.PortBindings "9443/tcp"}}{{(index . 0).HostPort}}{{end}}') printf '9443\n' ;;
	'{{.HostConfig.RestartPolicy.Name}}') printf 'unless-stopped\n' ;;
	*) return 1 ;;
	esac
}

test_portainer_managed_legacy_container_is_recreated_with_its_data() (
	portainer_catalog_fixture
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
	grep -Fq "create -p 8000:8000 -p 9443:9443 --name portainer --label com.pamuduw.dotfiles.catalog=$SOFTWARE_CATALOG_DIGEST --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data $TEST_PORTAINER_IMAGE" "$calls" || return 1
	grep -Fxq 'rm -f portainer.agentbot-backup' "$calls" || return 1
	! grep -Fxq 'rm -f portainer' "$calls" || return 1
	! grep -Eq '^(start|stop) ' "$calls" || return 1
	! grep -Eq 'volume (rm|create) portainer_data' "$calls" || return 1
)

test_portainer_running_container_is_stopped_before_the_replacement_starts() (
	portainer_catalog_fixture
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
	portainer_catalog_fixture
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
	portainer_catalog_fixture
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
	portainer_catalog_fixture
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
	portainer_catalog_fixture
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
	portainer_catalog_fixture
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

test_ubuntu_sans_mono_upgrade_preserves_external_fonts() (
	local directory="$HOME/.local/share/fonts/ubuntu-sans-mono" calls="$TEST_HARNESS_ROOT/font-upgrade.calls"
	mkdir -p "$directory"
	printf 'user font\n' >"$directory/External.ttf"
	printf '0.1\n' >"$directory/.version"
	printf '%s\n' $'ubuntu_sans_mono_fonts\towner\tany\tdotfiles' \
		$'ubuntu_sans_mono_fonts\tkind\tany\tsoftware' $'ubuntu_sans_mono_fonts\tversion\tany\t1.0' \
		$'ubuntu_sans_mono_fonts\tarchive\tany\tzip' | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-font-update"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-font-update"
	: >"$calls"
	curl() {
		printf 'download\n' >>"$calls"
		return 97
	}
	upgrade_result_set() { printf '%s\n' "$1" >>"$calls"; }
	upgrade_ubuntu_sans_mono || return 1
	[[ "$(cat "$directory/External.ttf")" == 'user font' && "$(cat "$directory/.version")" == 0.1 ]] || return 1
	[[ "$(cat "$calls")" == skipped && ! -e "$directory/.catalog-receipt" ]]
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

test_release_digest_must_name_the_selected_archive() (
	local calls="$TEST_HARNESS_ROOT/release-installer.calls"
	: >"$calls"
	github_api_release_json() {
		printf '{"assets":[{"name":"unrelated.tar.gz","digest":"sha256:%064d"}]}\n' 0
	}
	github_curl() {
		printf 'download\n' >>"$calls"
		return 97
	}
	if github_release_asset_sha256 example/tool selected.tar.gz >/dev/null; then return 1; fi
	[[ ! -s "$calls" ]]
)

test_wsl_config_renderer_updates_only_the_requested_section() (
	local conf="$TEST_HARNESS_ROOT/wsl-render.conf" rendered="$TEST_HARNESS_ROOT/wsl-rendered.conf"
	printf '%s\n' '[interop]' 'systemd=true' 'appendWindowsPath=false' '' '[boot]' 'appendWindowsPath=true' >"$conf"
	wsl_conf_render_required "$conf" >"$rendered"
	wsl_conf_has_setting "$rendered" boot systemd true || return 1
	wsl_conf_has_setting "$rendered" interop appendWindowsPath true || return 1
	grep -Fqx 'systemd=true' "$rendered"
)

check 'Portainer recovery preserves unowned containers and backups' test_portainer_recovery_preserves_unowned_resources
check 'an unreachable docker does not accuse the container' test_an_unreachable_docker_does_not_accuse_the_container
check 'component dispatch preserves the explicit reinstall flag' test_component_dispatch_preserves_reinstall_flag
check 'docker daemon config is written one way only' test_docker_daemon_config_is_written_one_way_only
check 'a failed daemon config write is not a change' test_a_failed_daemon_config_write_is_not_a_change
check 'git identity without a name reports instead of crashing' test_git_identity_without_a_name_reports_instead_of_crashing
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
check 'PowerShell refuses floating fallback when its approved target is missing' test_powershell_does_not_fall_back_when_approved_target_is_missing
check 'tool installers stop at the first required command failure' test_tool_installers_stop_at_the_first_required_failure
check 'container installers stop at the first required command failure' test_container_installers_stop_at_the_first_required_failure
check 'Portainer fresh installs use the approved digest and remain stopped' test_portainer_fresh_install_uses_digest_without_starting_container
check 'Portainer current digest containers are left unchanged' test_portainer_matching_digest_image_is_left_unchanged
check 'Portainer managed legacy containers retain their data' test_portainer_managed_legacy_container_is_recreated_with_its_data
check 'Portainer create failure restores the original running container' test_portainer_create_failure_restores_the_original_running_container
check 'Portainer running container is stopped before the replacement starts' test_portainer_running_container_is_stopped_before_the_replacement_starts
check 'Portainer start failure restores and restarts the original' test_portainer_start_failure_restores_and_restarts_the_original
check 'Portainer verify failure removes the partial replacement' test_portainer_verify_failure_removes_the_partial_replacement
check 'Portainer interrupted backup is restored before retry' test_portainer_interrupted_backup_is_restored_before_retry
check 'Portainer custom containers are not replaced' test_portainer_custom_container_is_not_replaced
check 'Ubuntu Sans Mono updates preserve external fonts' test_ubuntu_sans_mono_upgrade_preserves_external_fonts
check 'remote shell installers are downloaded before execution' test_remote_shell_installers_are_downloaded_before_execution
check 'remote shell installers reject insecure and empty payloads' test_remote_shell_installer_fails_closed
check 'release checksums must identify the selected archive' test_release_digest_must_name_the_selected_archive
check 'WSL config rendering updates settings only in their required sections' test_wsl_config_renderer_updates_only_the_requested_section

test_harness_cleanup
finish_tests
