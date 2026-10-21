# shellcheck shell=bash

install_ubuntu_sans_mono_windows() {
	local font_dir="$1" script windows_dir encoded rc=0
	if [[ -z "${WSL_DISTRO_NAME:-}${WSL_INTEROP:-}" ]] ||
		! command -v powershell.exe >/dev/null 2>&1 || ! command -v wslpath >/dev/null 2>&1; then
		log_warn "Windows font installation unavailable; install Ubuntu Sans Mono on Windows manually if needed"
		return 0
	fi
	script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../windows" && pwd)/install-fonts.ps1"
	windows_dir="$(wslpath -w "$font_dir")" || return 1
	encoded="$(
		python3 - "$script" "$windows_dir" <<'PYENCODE'
import base64
from pathlib import Path
import sys

script = Path(sys.argv[1]).read_text(encoding="utf-8")
path = sys.argv[2].replace("'", "''")
command = "& {\n" + script + "\n} -FontDirectory '" + path + "'"
print(base64.b64encode(command.encode("utf-16le")).decode("ascii"))
PYENCODE
	)" || return 1
	log_step "Install Ubuntu Sans Mono for the current Windows user"
	powershell.exe -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand "$encoded" || rc=$?
	if ((rc != 0)); then
		log_warn "Windows font installation failed; WSL fonts are installed. Rerun the font component to retry"
		return "$rc"
	fi
	log_ok "Ubuntu Sans Mono available to Windows apps; restart VS Code or Terminal if needed"
}

install_ubuntu_sans_mono_fonts() {
	local mode="${1:-}" font_parent="$HOME/.local/share/fonts"
	local font_dir="$font_parent/ubuntu-sans-mono"

	if [[ "$mode" != --replace && -n "$mode" ]]; then
		echo "  Unknown Ubuntu Sans Mono install option: $mode" >&2
		return 1
	fi
	if [[ "$mode" != --replace && -d "$font_dir" ]] && compgen -G "$font_dir/*.ttf" >/dev/null 2>&1 &&
		skip_unless_forced "Ubuntu Sans Mono fonts already installed in $font_dir"; then
		install_ubuntu_sans_mono_windows "$font_dir"
		return $?
	fi

	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for Ubuntu Sans Mono install." >&2
		return 1
	}
	command -v unzip >/dev/null 2>&1 || sudo apt-get -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=600 install -y unzip

	log_step "Install Ubuntu Sans Mono from GitHub"
	local ver tmp stage_dir='' backup_dir='' font_count=0 count font asset expected actual
	ver="$(github_latest_release_version canonical/Ubuntu-Sans-Mono-fonts)" || {
		echo "  Could not determine Ubuntu Sans Mono version." >&2
		return 1
	}

	asset="Ubuntu-Sans-Mono-fonts-v${ver}.zip"
	expected="$(github_release_asset_sha256 canonical/Ubuntu-Sans-Mono-fonts "$asset")" || {
		echo "  Missing published SHA-256 for Ubuntu Sans Mono archive." >&2
		return 1
	}
	[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || return 1

	tmp="$(mktemp -d)"
	trap 'rm -rf -- "${tmp:-}" "${stage_dir:-}" "${backup_dir:-}"' RETURN
	if ! github_curl -fsSL -o "$tmp/ubuntu-sans-mono.zip" \
		"https://github.com/canonical/Ubuntu-Sans-Mono-fonts/releases/download/v${ver}/Ubuntu-Sans-Mono-fonts-v${ver}.zip"; then
		echo "  Ubuntu Sans Mono download failed." >&2
		return 1
	fi
	actual="$(sha256sum "$tmp/ubuntu-sans-mono.zip")" || return 1
	if [[ "${actual%% *}" != "${expected,,}" ]]; then
		echo "  Ubuntu Sans Mono SHA-256 mismatch." >&2
		return 1
	fi
	if ! python3 - "$tmp/ubuntu-sans-mono.zip" <<'PYZIP'; then
import re
import stat
import sys
import zipfile

try:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        seen = set()
        for entry in archive.infolist():
            name = entry.orig_filename
            parts = name.rstrip("/").split("/")
            mode = entry.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if (not name or name.startswith("/") or "\\" in name
                    or re.match(r"^[A-Za-z]:", name)
                    or any(part in ("", ".", "..") for part in parts)
                    or any(ord(char) < 32 for char in name)
                    or kind not in (0, stat.S_IFREG, stat.S_IFDIR)
                    or (kind == stat.S_IFDIR and not entry.is_dir())
                    or (kind == stat.S_IFREG and entry.is_dir())
                    or name.rstrip("/") in seen):
                raise ValueError("unsafe archive member")
            seen.add(name.rstrip("/"))
except (OSError, ValueError, zipfile.BadZipFile) as error:
    print(f"Rejected Ubuntu Sans Mono archive: {error}", file=sys.stderr)
    raise SystemExit(1)
PYZIP
		return 1
	fi
	if ! unzip -qo "$tmp/ubuntu-sans-mono.zip" -d "$tmp/ubuntu_sans_mono"; then
		echo "  Ubuntu Sans Mono unzip failed." >&2
		return 1
	fi

	mkdir -p "$font_parent"
	stage_dir="$(mktemp -d "$font_parent/.ubuntu_sans_mono.new.XXXXXX")"
	if [[ -d "$font_dir" ]]; then
		cp -a "$font_dir/." "$stage_dir/" || return 1
	fi
	while IFS= read -r -d '' font; do
		cp "$font" "$stage_dir/"
		font_count=$((font_count + 1))
	done < <(find "$tmp/ubuntu_sans_mono" -path '*/fonts/ttf/UbuntuSansMono-*.ttf' -name '*.ttf' -print0)
	if [[ $font_count -eq 0 ]]; then
		echo "  No .ttf files found in Ubuntu Sans Mono archive." >&2
		return 1
	fi

	printf '%s\n' "$ver" >"${stage_dir}/.version"
	if [[ -e "$font_dir" ]]; then
		backup_dir="$(mktemp -d "$font_parent/.ubuntu_sans_mono.old.XXXXXX")"
		rmdir "$backup_dir"
		if ! mv "$font_dir" "$backup_dir"; then
			echo "  Could not stage the existing Ubuntu Sans Mono installation for replacement." >&2
			return 1
		fi
	fi
	if ! mv "$stage_dir" "$font_dir"; then
		echo "  Could not activate the new Ubuntu Sans Mono installation; restoring the previous files." >&2
		if [[ -n "$backup_dir" && -e "$backup_dir" ]]; then
			if ! mv "$backup_dir" "$font_dir"; then
				echo "  Restoration failed; previous Ubuntu Sans Mono files retained at $backup_dir" >&2
				backup_dir=''
			fi
		fi
		return 1
	fi
	stage_dir=''
	if [[ -n "$backup_dir" ]]; then
		rm -rf -- "$backup_dir"
		backup_dir=''
	fi

	fc-cache -f 2>/dev/null || true
	count="$(find "$font_dir" -name '*.ttf' | wc -l)"
	rm -rf "$tmp"
	tmp=''
	trap - RETURN
	log_ok "Ubuntu Sans Mono ${ver} installed (${count} fonts in ${font_dir})"
	install_ubuntu_sans_mono_windows "$font_dir"
}
