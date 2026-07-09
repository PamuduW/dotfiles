# shellcheck shell=bash

install_monaspace_fonts() {
	local font_dir="$HOME/.local/share/fonts/monaspace"

	if [[ -d "$font_dir" ]] && compgen -G "$font_dir/*.otf" >/dev/null 2>&1; then
		log_skip "Monaspace fonts already installed in $font_dir"
		return 0
	fi

	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for Monaspace install." >&2
		return 1
	}
	command -v unzip >/dev/null 2>&1 || sudo apt-get -o Dpkg::Use-Pty=0 install -y unzip

	log_step "Install Monaspace Nerd Fonts from GitHub"
	local ver tmp
	ver="$(curl -fsSL https://api.github.com/repos/githubnext/monaspace/releases/latest |
		grep -Po '"tag_name":\s*"\K[^"]*' | head -n1)"
	[[ -n "$ver" ]] || {
		echo "  Could not determine Monaspace version." >&2
		return 1
	}

	tmp="$(mktemp -d)"
	trap "rm -rf '${tmp}'" RETURN
	if ! curl -fsSL -o "$tmp/monaspace-nerdfonts.zip" \
		"https://github.com/githubnext/monaspace/releases/download/${ver}/monaspace-nerdfonts-${ver}.zip"; then
		echo "  Monaspace download failed." >&2
		return 1
	fi
	if ! unzip -qo "$tmp/monaspace-nerdfonts.zip" -d "$tmp/monaspace"; then
		echo "  Monaspace unzip failed." >&2
		return 1
	fi

	local extracted_path
	while IFS= read -r -d '' extracted_path; do
		if [[ "$extracted_path" == *".."* ]]; then
			echo "  Rejected suspicious path in Monaspace archive." >&2
			return 1
		fi
	done < <(find "$tmp/monaspace" -print0)

	mkdir -p "$font_dir"
	local otf_count=0
	while IFS= read -r -d '' otf; do
		cp "$otf" "$font_dir/"
		otf_count=$((otf_count + 1))
	done < <(find "$tmp/monaspace" -name '*.otf' -print0)
	if [[ $otf_count -eq 0 ]]; then
		echo "  No .otf files found in Monaspace archive." >&2
		return 1
	fi

	fc-cache -f 2>/dev/null || true

	local count
	count="$(find "$font_dir" -name '*.otf' | wc -l)"
	printf '%s\n' "$ver" >"${font_dir}/.version"
	rm -rf "$tmp"
	trap - RETURN
	log_ok "Monaspace Nerd Fonts ${ver} installed (${count} fonts in ${font_dir})"
}
