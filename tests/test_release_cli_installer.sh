#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
source "$TEST_DIR/lib/catalog_fixture.sh"
test_harness_init
test_harness_report_init

# A real kubeconform, tflint or zizmor on the machine running the tests must
# never stand in for the fixture.
PATH="$TEST_FAKE_BIN:/usr/bin:/bin"

source "$ROOT/scripts/lib/installers/logging.sh"
# shellcheck source=scripts/lib/installers/release_cli.sh
source "$ROOT/scripts/lib/installers/release_cli.sh"

declare -A FIXTURE_VERSION_LINE=(
	[kubeconform]='v%s'
	[tflint]='TFLint version %s'
	[zizmor]='zizmor %s'
)
declare -A FIXTURE_ASSET=(
	[kubeconform]='kubeconform-linux-amd64.tar.gz'
	[tflint]='tflint_linux_amd64.zip'
	[zizmor]='zizmor-x86_64-unknown-linux-gnu.tar.gz'
)

uname() {
	case "$1" in
	-s) printf 'Linux\n' ;;
	-m) printf 'x86_64\n' ;;
	*) command uname "$@" ;;
	esac
}

# make_archive <key> <version> [member...]: the fixture archive for <key>, whose
# binary prints <version> in the tool's own format. Extra members are added
# beside it; a member named ESCAPE becomes ../escape.
make_archive() {
	local key="$1" version="$2" binary dir archive line
	shift 2
	binary="$(release_cli_field "$key" binary)"
	dir="$TEST_HARNESS_ROOT/fixture-$key"
	rm -rf -- "$dir"
	mkdir -p "$dir"
	# shellcheck disable=SC2059  # The table holds the format.
	line="$(printf "${FIXTURE_VERSION_LINE[$key]:-$key %s}" "$version")"
	printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' '$line'" >"$dir/$binary"
	chmod +x "$dir/$binary"
	printf 'license\n' >"$dir/LICENSE"
	archive="$TEST_HARNESS_ROOT/$(release_cli_asset_name "$key" "$version")"
	rm -f -- "$archive"
	local -a members=("$@")
	((${#members[@]})) || members=("$binary" LICENSE)
	if [[ "$(release_cli_field "$key" archive)" == raw ]]; then
		cp -- "$dir/$binary" "$archive"
	elif [[ "$(release_cli_field "$key" archive)" == zip ]]; then
		(cd "$dir" && python3 -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for name in sys.argv[2:]:
        z.write(name if name != "ESCAPE" else "LICENSE", "../escape" if name == "ESCAPE" else name)
' "$archive" "${members[@]}")
	else
		local -a transform=()
		[[ " ${members[*]} " == *' ESCAPE '* ]] && {
			cp "$dir/LICENSE" "$dir/ESCAPE"
			transform=(--transform 's|^ESCAPE|../escape|')
		}
		tar -czf "$archive" -C "$dir" "${transform[@]}" "${members[@]}"
	fi
	printf '%s\n' "$archive"
}

# serve <key> <version> <archive> [digest]: the release API and the download.
serve() {
	local key="$1" version="$2" archive="$3" digest="${4:-}"
	[[ -n "$digest" ]] || digest="$(sha256sum "$archive" | awk '{print $1}')"
	local repository asset tag="v$version" binary archive_type version_args
	repository="$(release_cli_field "$key" repository)"
	asset="$(release_cli_asset_name "$key" "$version")"
	binary="$(release_cli_field "$key" binary)"
	archive_type="$(release_cli_field "$key" archive)"
	version_args="$(release_cli_field "$key" version-args)"
	[[ "$key" != yt_dlp ]] || tag="$version"
	printf '%s\n' "$key"$'\towner\tany\tdotfiles' "$key"$'\tkind\tany\tsoftware' \
		"$key"$'\tversion\tany\t'"$version" "$key"$'\tarchive\tany\t'"$archive_type" \
		"$key"$'\tbinary\tany\t'"$binary" "$key"$'\tdiscovery.version_arg\tany\t'"$version_args" \
		"$key"$'\turl\tany\thttps://github.com/'"$repository/releases/download/$tag/$asset" \
		"$key"$'\tdigest\tany\tsha256:'"$digest" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-release"
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-release"
	SERVED_ARCHIVE="$archive"
	release_cli_latest_release_metadata() { printf 'v%s\n%s\n' "$SERVED_VERSION" "$SERVED_DIGEST"; }
	SERVED_VERSION="$version"
	SERVED_DIGEST="$digest"
	github_curl() {
		printf 'download:%s\n' "${*: -1}" >>"$TEST_URL_LOG"
		cp -- "$SERVED_ARCHIVE" "$3"
	}
}

reset_home() {
	rm -rf -- "$HOME/.local" "$TEST_URL_LOG"
	mkdir -p "$(dirname -- "$TEST_URL_LOG")"
	: >"$TEST_URL_LOG"
}

own() {
	local key="$1" version="$2" binary
	binary="$(release_cli_field "$key" binary)"
	mkdir -p "$HOME/.local/bin" "$HOME/.local/share/dotfiles"
	cp "$(make_archive "$key" "$version" >/dev/null && printf '%s' "$TEST_HARNESS_ROOT/fixture-$key/$binary")" "$HOME/.local/bin/$binary"
	printf 'v%s\n' "$version" >"$HOME/.local/share/dotfiles/$key.version"
}

test_fresh_install_of_each_tool_installs_only_its_verified_binary() (
	local row key binary repository asset tag
	((${#RELEASE_CLI_TOOLS[@]} > 0)) || return 1
	for row in "${RELEASE_CLI_TOOLS[@]}"; do
		key="${row%%|*}"
		reset_home
		binary="$(release_cli_field "$key" binary)"
		repository="$(release_cli_field "$key" repository)"
		asset="${FIXTURE_ASSET[$key]:-$(release_cli_asset_name "$key" 1.2.3)}"
		tag=v1.2.3
		[[ "$key" != yt_dlp ]] || tag=1.2.3
		serve "$key" 1.2.3 "$(make_archive "$key" 1.2.3)"

		install_release_cli "$key" >/dev/null || return 1

		[[ -x "$HOME/.local/bin/$binary" ]] || return 1
		[[ "$(release_cli_installed_tag "$key")" == v1.2.3 ]] || return 1
		[[ "$(<"$HOME/.local/share/dotfiles/$key.version")" == v1.2.3 ]] || return 1
		[[ ! -e "$HOME/.local/bin/LICENSE" ]] || return 1
		grep -Fqx "download:https://github.com/${repository}/releases/download/${tag}/${asset}" \
			"$TEST_URL_LOG" || return 1
		release_cli_is_dotfiles_owned "$key" || return 1
	done
)

test_checksum_mismatch_installs_nothing() (
	reset_home
	serve tflint 1.2.3 "$(make_archive tflint 1.2.3)" "$(printf '%064d' 0)"

	! install_release_cli tflint >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/tflint" && ! -e "$HOME/.local/share/dotfiles/tflint.version" ]]
)

test_unavailable_approved_pin_installs_nothing() (
	reset_home
	catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-release" </dev/null
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-release"
	TEST_APPROVED_CATALOG="$TEST_HARNESS_ROOT/missing-release-catalog"
	release_cli_latest_release_metadata() { return 1; }
	github_curl() { printf 'download\n' >>"$TEST_URL_LOG"; }

	! install_release_cli zizmor >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/zizmor" && ! -s "$TEST_URL_LOG" ]]
)

test_archive_without_the_binary_is_refused() (
	reset_home
	serve kubeconform 1.2.3 "$(make_archive kubeconform 1.2.3 LICENSE)"

	! install_release_cli kubeconform >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/kubeconform" ]]
)

test_archive_member_escaping_the_directory_is_refused() (
	local key
	for key in kubeconform tflint; do
		reset_home
		serve "$key" 1.2.3 "$(make_archive "$key" 1.2.3 "$(release_cli_field "$key" binary)" ESCAPE)"
		! install_release_cli "$key" >/dev/null 2>&1 || return 1
		[[ ! -e "$HOME/.local/bin/$(release_cli_field "$key" binary)" ]] || return 1
	done
)

test_binary_reporting_another_version_is_refused() (
	reset_home
	serve zizmor 1.2.4 "$(make_archive zizmor 1.2.3)"

	! install_release_cli zizmor >/dev/null 2>&1 || return 1
	[[ ! -e "$HOME/.local/bin/zizmor" ]]
	! compgen -G "$HOME/.local/bin/.zizmor.candidate.*" >/dev/null
)

test_external_binary_is_preserved_even_when_forced() (
	reset_home
	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'echo "TFLint version 9.9.9"' >"$HOME/.local/bin/tflint"
	chmod +x "$HOME/.local/bin/tflint"
	serve tflint 1.2.3 "$(make_archive tflint 1.2.3)"

	install_release_cli tflint >/dev/null || return 1
	DOTFILES_FORCE_REINSTALL=1 install_release_cli tflint >/dev/null || return 1

	[[ "$("$HOME/.local/bin/tflint" --version)" == 'TFLint version 9.9.9' && ! -s "$TEST_URL_LOG" ]]
)

test_owned_binary_is_skipped_unless_forced() (
	reset_home
	own kubeconform 1.2.3
	serve kubeconform 1.2.3 "$(make_archive kubeconform 1.2.3)"

	install_release_cli kubeconform >/dev/null || return 1
	[[ -L "$HOME/.local/bin/kubeconform" && -f "$HOME/.local/share/dotfiles-catalog/kubeconform/current/.catalog-receipt" ]] || return 1
	: >"$TEST_URL_LOG"
	install_release_cli kubeconform >/dev/null || return 1
	[[ ! -s "$TEST_URL_LOG" ]] || return 1

	DOTFILES_FORCE_REINSTALL=1 install_release_cli kubeconform >/dev/null || return 1
	grep -q '^download:' "$TEST_URL_LOG"
)

test_update_advances_an_owned_binary_and_its_stamp() (
	reset_home
	own zizmor 1.2.3
	serve zizmor 1.3.0 "$(make_archive zizmor 1.3.0)"
	upgrade_result_set() { printf '%s\n' "$1" >"$TEST_HARNESS_ROOT/result"; }

	upgrade_zizmor >/dev/null || return 1

	[[ "$(release_cli_installed_tag zizmor)" == v1.3.0 ]] || return 1
	[[ "$(<"$HOME/.local/share/dotfiles/zizmor.version")" == v1.3.0 ]] || return 1
	[[ "$(<"$TEST_HARNESS_ROOT/result")" == updated ]] || return 1
	upgrade_zizmor >/dev/null || return 1
	[[ "$(<"$TEST_HARNESS_ROOT/result")" == already-current ]]
)

test_update_without_approved_pin_preserves_the_binary() (
	reset_home
	own tflint 1.2.3
	catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog-release" </dev/null
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog-release"
	TEST_APPROVED_CATALOG="$TEST_HARNESS_ROOT/missing-release-catalog"
	release_cli_latest_release_metadata() { return 1; }

	! upgrade_tflint >/dev/null 2>&1 || return 1
	[[ "$(release_cli_installed_tag tflint)" == v1.2.3 ]]
)

test_update_skips_missing_and_external_tools() (
	reset_home
	serve kubeconform 1.2.3 "$(make_archive kubeconform 1.2.3)"
	upgrade_result_set() { printf '%s\n' "$1" >>"$TEST_HARNESS_ROOT/results"; }
	: >"$TEST_HARNESS_ROOT/results"
	github_curl() { printf 'download\n' >>"$TEST_URL_LOG"; }
	upgrade_kubeconform >/dev/null || return 1
	mkdir -p "$HOME/.local/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'echo v9.9.9' >"$HOME/.local/bin/kubeconform"
	chmod +x "$HOME/.local/bin/kubeconform"
	upgrade_kubeconform >/dev/null || return 1

	[[ "$(<"$TEST_HARNESS_ROOT/results")" == $'skipped\nskipped' && ! -s "$TEST_URL_LOG" ]]
)

test_update_check_reports_installed_available_and_action() (
	reset_home
	local row
	serve kubeconform 1.3.0 "$(make_archive kubeconform 1.3.0)"
	row="$(check_kubeconform || true)"
	[[ "$row" == 'Kubeconform|not installed|1.3.0|skip' ]] || return 1

	own kubeconform 1.2.3
	serve kubeconform 1.3.0 "$(make_archive kubeconform 1.3.0)"
	row="$(check_kubeconform)" || return 1
	[[ "$row" == 'Kubeconform|1.2.3|1.3.0|upgrade' ]] || return 1

	serve kubeconform 1.2.3 "$(make_archive kubeconform 1.2.3)"
	row="$(check_kubeconform || true)"
	[[ "$row" == 'Kubeconform|1.2.3|1.2.3|upgrade' ]] || return 1
	install_release_cli kubeconform >/dev/null || return 1
	row="$(check_kubeconform || true)"
	[[ "$row" == 'Kubeconform|1.2.3|1.2.3|current' ]] || return 1

	rm -f -- "$HOME/.local/share/dotfiles/kubeconform.version"
	row="$(check_kubeconform || true)"
	[[ "$row" == 'Kubeconform|1.2.3|1.2.3|current' ]] || return 1
	rm -- "$(dotfiles_catalog_root kubeconform)/current/.catalog-receipt"
	row="$(check_kubeconform || true)"
	[[ "$row" == 'Kubeconform|external installation|1.2.3|external' ]]
)

test_metadata_picks_the_asset_for_this_architecture() (
	local output
	github_api_release_json() {
		[[ "$1" == zizmorcore/zizmor ]] || return 97
		printf '%s\n' '{"tag_name":"v1.30.1","assets":[{"name":"zizmor-aarch64-unknown-linux-gnu.tar.gz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"name":"zizmor-x86_64-unknown-linux-gnu.tar.gz","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}'
	}

	output="$(release_cli_latest_release_metadata zizmor)" || return 1
	[[ "$output" == $'v1.30.1\naaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ]] || return 1

	github_api_release_json() {
		printf '%s\n' '{"tag_name":"v1.30.1","assets":[{"name":"zizmor-x86_64-unknown-linux-gnu.tar.gz"}]}'
	}
	! release_cli_latest_release_metadata zizmor >/dev/null
)

test_unsupported_architecture_fails_closed() (
	reset_home
	serve tflint 1.2.3 "$(make_archive tflint 1.2.3)"
	uname() {
		case "$1" in
		-s) printf 'Linux\n' ;;
		-m) printf 'riscv64\n' ;;
		esac
	}
	! release_cli_asset_name tflint >/dev/null || return 1
	! install_release_cli tflint >/dev/null 2>&1
)

# Vale names its asset after the version; yt-dlp's asset is the binary itself.
test_vale_asset_carries_the_release_version() (
	reset_home
	local dir="$TEST_HARNESS_ROOT/fixture-vale" archive
	rm -rf -- "$dir"
	mkdir -p "$dir"
	printf '%s\n' '#!/usr/bin/env bash' "printf 'vale version 3.24.0\\n'" >"$dir/vale"
	chmod +x "$dir/vale"
	printf 'license\n' >"$dir/LICENSE"
	archive="$TEST_HARNESS_ROOT/vale.tar.gz"
	tar -czf "$archive" -C "$dir" vale LICENSE
	serve vale 3.24.0 "$archive"

	install_release_cli vale >/dev/null || return 1
	grep -Fqx 'download:https://github.com/vale-cli/vale/releases/download/v3.24.0/vale_3.24.0_Linux_64-bit.tar.gz' \
		"$TEST_URL_LOG" || return 1
	[[ "$(release_cli_installed_tag vale)" == v3.24.0 && ! -e "$HOME/.local/bin/LICENSE" ]] || return 1

	local output
	github_api_release_json() {
		printf '%s\n' '{"tag_name":"v3.24.0","assets":[{"name":"vale_3.24.0_Linux_64-bit.tar.gz","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}'
	}
	unset -f release_cli_latest_release_metadata
	source "$ROOT/scripts/lib/installers/release_cli.sh"
	output="$(release_cli_latest_release_metadata vale)" || return 1
	[[ "$output" == $'v3.24.0\naaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ]]
)

test_yt_dlp_raw_binary_installs_without_extraction() (
	reset_home
	local binary="$TEST_HARNESS_ROOT/yt-dlp_linux"
	printf '%s\n' '#!/usr/bin/env bash' "printf '2026.08.19\\n'" >"$binary"
	chmod +x "$binary"
	serve yt_dlp 2026.08.19 "$binary"
	# yt-dlp's tags have no v, unlike the other tools' tags that serve imitates.
	release_cli_latest_release_metadata() { printf '%s\n%s\n' "$SERVED_VERSION" "$SERVED_DIGEST"; }

	install_release_cli yt_dlp >/dev/null || return 1
	grep -Fqx 'download:https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_linux' \
		"$TEST_URL_LOG" || return 1
	[[ -x "$HOME/.local/bin/yt-dlp" ]] || return 1
	[[ "$(release_cli_installed_tag yt_dlp)" == v2026.08.19 ]] || return 1
	release_cli_is_dotfiles_owned yt_dlp || return 1

	uname() {
		case "$1" in
		-s) printf 'Linux\n' ;;
		-m) printf 'aarch64\n' ;;
		esac
	}
	[[ "$(release_cli_asset_name yt_dlp)" == yt-dlp_linux_aarch64 ]] || return 1
	[[ "$(release_cli_asset_name trivy v0.76.0)" == trivy_0.76.0_Linux-ARM64.tar.gz ]] || return 1
	[[ "$(release_cli_asset_name infracost)" == infracost-linux-arm64.tar.gz ]]
)

test_wrappers_route_to_each_tool() (
	local name
	for name in check_kubeconform check_tflint check_zizmor check_vale check_yt_dlp check_trivy check_infracost \
		upgrade_kubeconform upgrade_tflint upgrade_zizmor upgrade_vale upgrade_yt_dlp upgrade_trivy upgrade_infracost; do
		declare -F "$name" >/dev/null || return 1
	done
)

expect_success 'each release CLI installs only its verified binary on a fresh machine' test_fresh_install_of_each_tool_installs_only_its_verified_binary
expect_success 'a checksum mismatch installs nothing' test_checksum_mismatch_installs_nothing
expect_success 'an unavailable approved pin installs nothing' test_unavailable_approved_pin_installs_nothing
expect_success 'an archive without the binary is refused' test_archive_without_the_binary_is_refused
expect_success 'an archive member escaping the directory is refused (tar and zip)' test_archive_member_escaping_the_directory_is_refused
expect_success 'a binary reporting another version is refused' test_binary_reporting_another_version_is_refused
expect_success 'an external binary is preserved, forced or not' test_external_binary_is_preserved_even_when_forced
expect_success 'an owned binary is skipped unless forced, then reinstalled' test_owned_binary_is_skipped_unless_forced
expect_success 'update advances an owned binary and its stamp' test_update_advances_an_owned_binary_and_its_stamp
expect_success 'update without an approved pin preserves the binary' test_update_without_approved_pin_preserves_the_binary
expect_success 'update skips missing and external tools' test_update_skips_missing_and_external_tools
expect_success 'update check reports installed, available and action' test_update_check_reports_installed_available_and_action
expect_success 'release metadata picks the asset for this architecture' test_metadata_picks_the_asset_for_this_architecture
expect_success 'an unsupported architecture fails closed' test_unsupported_architecture_fails_closed
expect_success 'Vale downloads the asset named after its release version' test_vale_asset_carries_the_release_version
expect_success 'yt-dlp installs its raw release binary without extraction' test_yt_dlp_raw_binary_installs_without_extraction
expect_success 'per-tool wrappers exist for the update registry' test_wrappers_route_to_each_tool

finish_tests
