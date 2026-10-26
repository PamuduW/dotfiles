# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/../catalog_load.sh"

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
	dotfiles_catalog_fonts
}
