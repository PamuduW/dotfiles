#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2317
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
source "$TEST_DIR/lib/dotfiles_env.sh"
source "$REPO_DIR/scripts/lib/installers/fonts.sh"
install_ubuntu_sans_mono_windows() { :; }
NOT_INSTALLED="not installed"

font_case() (
	local kind="$1" root="$TEST_HARNESS_ROOT/$1" output rc=0
	mkdir -p "$root/home/.local/share/fonts/ubuntu-sans-mono" "$root/tmp"
	export HOME="$root/home" TMPDIR="$root/tmp"
	printf old >"$HOME/.local/share/fonts/ubuntu-sans-mono/old.ttf"
	python3 - "$root/archive.zip" "$kind" <<'PY'
import stat, sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    if sys.argv[2] != 'variable-only':
        for style in ('Regular', 'Italic', 'Bold', 'BoldItalic'):
            z.writestr(f'Ubuntu-Sans-Mono-fonts-v1.0/fonts/ttf/UbuntuSansMono-{style}.ttf', 'new')
    z.writestr('Ubuntu-Sans-Mono-fonts-v1.0/fonts/variable/UbuntuSansMono[wght].ttf', 'variable')
    kind = sys.argv[2]
    names = {'traversal': '../escaped', 'absolute': '/escaped', 'backslash': '..\\escaped', 'drive': 'C:/escaped'}
    if kind in names:
        z.writestr(names[kind], 'bad')
    if kind in ('symlink', 'fifo'):
        info = zipfile.ZipInfo('fonts/link')
        info.create_system = 3
        info.external_attr = ((stat.S_IFLNK if kind == 'symlink' else stat.S_IFIFO) | 0o777) << 16
        z.writestr(info, 'target')
PY
	github_latest_release_version() { echo 1.0; }
	github_release_asset_sha256() {
		[[ "$1 $2" == 'canonical/Ubuntu-Sans-Mono-fonts Ubuntu-Sans-Mono-fonts-v1.0.zip' ]] || return 1
		case "$kind" in missing) return 1 ;; mismatch) printf '%064d\n' 0 ;; *) sha256sum "$root/archive.zip" | cut -d ' ' -f 1 ;; esac
	}
	github_curl() { cp "$root/archive.zip" "$3"; }
	sudo() {
		echo 'unexpected sudo' >&2
		return 1
	}
	log_step() { :; }
	log_ok() { :; }
	fc-cache() { :; }
	unzip() {
		: >"$root/unpacked"
		command unzip "$@"
	}
	mv() {
		if [[ "$kind" == rollback && ("$1" == *'.ubuntu_sans_mono.new.'* || "$1" == *'.ubuntu_sans_mono.old.'*) ]]; then return 1; fi
		command mv "$@"
	}
	output="$(install_ubuntu_sans_mono_fonts --replace 2>&1)" || rc=$?
	if [[ "$kind" == good ]]; then
		[[ $rc -eq 0 && -f "$HOME/.local/share/fonts/ubuntu-sans-mono/UbuntuSansMono-Regular.ttf" ]] || return 1
		[[ ! -e "$HOME/.local/share/fonts/ubuntu-sans-mono/UbuntuSansMono[wght].ttf" ]] || return 1
		[[ -f "$HOME/.local/share/fonts/ubuntu-sans-mono/old.ttf" ]] || return 1
	elif [[ "$kind" == variable-only ]]; then
		[[ $rc -ne 0 && -f "$HOME/.local/share/fonts/ubuntu-sans-mono/old.ttf" ]] || return 1
	elif [[ "$kind" == rollback ]]; then
		[[ $rc -ne 0 ]] || return 1
		local backup
		backup="$(find "$HOME/.local/share/fonts" -name '.ubuntu_sans_mono.old.*' -type d -print -quit)"
		[[ -n "$backup" && -f "$backup/old.ttf" && "$output" == *"$backup"* ]] || return 1
	else
		[[ $rc -ne 0 && -f "$HOME/.local/share/fonts/ubuntu-sans-mono/old.ttf" && ! -e "$root/unpacked" ]] || return 1
		[[ ! -e "$HOME/.local/share/fonts/ubuntu-sans-mono/UbuntuSansMono-Regular.ttf" ]] || return 1
		[[ -z "$(find "$root/tmp" -name escaped -print -quit)" ]]
	fi
)

cursor_names() (
	tool_resolve() { [[ "$1" == 'agent cursor-agent' ]] && printf '/fake/cursor-agent\n'; }
	tool_version_raw() { echo cli-version; }
	cursor_is_installed && [[ "$(cursor_installed_version)" == cli-version ]]
)
cursor_editor_is_not_cli() (
	tool_resolve() { [[ "$1" == 'agent cursor' ]] && printf '/fake/cursor\n'; }
	! cursor_is_installed && [[ "$(cursor_installed_version)" == "$NOT_INSTALLED" ]]
)
for kind in good variable-only missing mismatch traversal absolute backslash drive symlink fifo rollback; do
	check "Ubuntu Sans Mono safety: $kind" font_case "$kind"
done
check 'Cursor preview finds cursor-agent' cursor_names
check 'Cursor preview excludes editor launcher' cursor_editor_is_not_cli
test_harness_cleanup
finish_tests
