# shellcheck shell=bash

install_monaspace_fonts() {
	local mode="${1:-}" font_parent="$HOME/.local/share/fonts"
	local font_dir="$font_parent/monaspace"

	if [[ "$mode" != --replace && -n "$mode" ]]; then
		echo "  Unknown Monaspace install option: $mode" >&2
		return 1
	fi
	if [[ "$mode" != --replace && -d "$font_dir" ]] && compgen -G "$font_dir/*.otf" >/dev/null 2>&1; then
		log_skip "Monaspace fonts already installed in $font_dir"
		return 0
	fi

	command -v curl >/dev/null 2>&1 || {
		echo "  curl required for Monaspace install." >&2
		return 1
	}
	command -v unzip >/dev/null 2>&1 || sudo apt-get -o Dpkg::Use-Pty=0 install -y unzip

	log_step "Install Monaspace Nerd Fonts from GitHub"
	local ver tmp stage_dir='' backup_dir='' otf_count=0 count otf
	ver="$(github_latest_release_version githubnext/monaspace)" || {
		echo "  Could not determine Monaspace version." >&2
		return 1
	}

	tmp="$(mktemp -d)"
	trap 'rm -rf -- "${tmp:-}" "${stage_dir:-}" "${backup_dir:-}"' RETURN
	if ! github_curl -fsSL -o "$tmp/monaspace-nerdfonts.zip" \
		"https://github.com/githubnext/monaspace/releases/download/v${ver}/monaspace-nerdfonts-v${ver}.zip"; then
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

	mkdir -p "$font_parent"
	stage_dir="$(mktemp -d "$font_parent/.monaspace.new.XXXXXX")"
	while IFS= read -r -d '' otf; do
		cp "$otf" "$stage_dir/"
		otf_count=$((otf_count + 1))
	done < <(find "$tmp/monaspace" -name '*.otf' -print0)
	if [[ $otf_count -eq 0 ]]; then
		echo "  No .otf files found in Monaspace archive." >&2
		return 1
	fi

	printf '%s\n' "$ver" >"${stage_dir}/.version"
	if [[ -e "$font_dir" ]]; then
		backup_dir="$(mktemp -d "$font_parent/.monaspace.old.XXXXXX")"
		rmdir "$backup_dir"
		if ! mv "$font_dir" "$backup_dir"; then
			echo "  Could not stage the existing Monaspace installation for replacement." >&2
			return 1
		fi
	fi
	if ! mv "$stage_dir" "$font_dir"; then
		echo "  Could not activate the new Monaspace installation; restoring the previous files." >&2
		if [[ -n "$backup_dir" && -e "$backup_dir" ]]; then
			mv "$backup_dir" "$font_dir" || true
		fi
		return 1
	fi
	stage_dir=''
	if [[ -n "$backup_dir" ]]; then
		rm -rf -- "$backup_dir"
		backup_dir=''
	fi

	fc-cache -f 2>/dev/null || true
	count="$(find "$font_dir" -name '*.otf' | wc -l)"
	rm -rf "$tmp"
	tmp=''
	trap - RETURN
	log_ok "Monaspace Nerd Fonts ${ver} installed (${count} fonts in ${font_dir})"
}
