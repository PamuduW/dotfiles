# shellcheck shell=bash
# Read-only catalog paths and ownership, also used before installers are loaded.
dotfiles_catalog_root() { printf '%s\n' "$HOME/.local/share/dotfiles-catalog/$1"; }

dotfiles_catalog_has_current() {
	local current
	if [[ -e "$HOME/.local/share/dotfiles-catalog/$1.native" || -L "$HOME/.local/share/dotfiles-catalog/$1.native" ]]; then return 0; fi
	current="$(dotfiles_catalog_root "$1")/current"
	[[ -e "$current" || -L "$current" ]]
}

dotfiles_catalog_command_name() {
	case "$1" in
	cursor_cli) echo agent ;;
	codex_cli) echo codex ;;
	claude_cli) echo claude ;;
	antigravity_cli) echo agy ;;
	graphify_cli) echo graphify ;;
	boost_cli) echo boost ;;
	chrome_headless) echo chrome-headless-shell ;;
	nodejs) echo node ;;
	go) echo go ;;
	powershell) echo pwsh ;;
	yt_dlp) echo yt-dlp ;;
	markdownlint_cli2) echo markdownlint-cli2 ;;
	mermaid_cli) echo mmdc ;;
	*) printf '%s\n' "$1" ;;
	esac
}

dotfiles_catalog_owned() {
	local key="$1" root command_name link release resolved
	if [[ -e "$HOME/.local/share/dotfiles-catalog/$key.native" || -L "$HOME/.local/share/dotfiles-catalog/$key.native" ]]; then
		dotfiles_catalog_native_owned "$key"
		return $?
	fi
	root="$(dotfiles_catalog_root "$key")"
	command_name="$(dotfiles_catalog_command_name "$key")"
	link="$HOME/.local/bin/$command_name"
	[[ ! -L "$root" && ! -L "$root/releases" && -L "$root/current" &&
		-f "$root/current/.catalog-receipt" && ! -L "$root/current/.catalog-receipt" &&
		-O "$root/current/.catalog-receipt" && -L "$link" && -x "$link" ]] || return 1
	dotfiles_catalog_receipt_valid "$root/current/.catalog-receipt" || return 1
	[[ "$(readlink -- "$link")" == "$root/current/command" ]] || return 1
	release="$(readlink -f -- "$root/current")" || return 1
	resolved="$(readlink -f -- "$root/releases")" || return 1
	[[ "$release" == "$resolved/"* ]] || return 1
	resolved="$(readlink -f -- "$link")" || return 1
	[[ "$resolved" == "$release/"* ]]
}

dotfiles_catalog_receipt_valid() {
	local receipt="$1" receipt_size
	local -a proof=()
	[[ -f "$receipt" && ! -L "$receipt" && -O "$receipt" ]] || return 1
	receipt_size="$(stat -c %s -- "$receipt")" || return 1
	[[ "$receipt_size" =~ ^[0-9]+$ && "$receipt_size" -le 512 ]] || return 1
	mapfile -t proof <"$receipt"
	[[ "${#proof[@]}" == 3 ]] || return 1
	[[ "${proof[0]}" =~ ^[A-Za-z0-9][A-Za-z0-9._+:-]*$ &&
		"${proof[1]}" =~ ^[0-9a-f]{64}$ && "${proof[2]}" =~ ^[0-9a-f]{40}$ ]] || return 1
}

dotfiles_catalog_native_owned() {
	local key="$1" receipt="$HOME/.local/share/dotfiles-catalog/$1.native" size prefix binary resolved
	local -a proof=() node_proof=()
	[[ -f "$receipt" && ! -L "$receipt" && -O "$receipt" ]] || return 1
	size="$(stat -c %s -- "$receipt")" || return 1
	[[ "$size" =~ ^[0-9]+$ && "$size" -le 4096 ]] || return 1
	mapfile -t proof <"$receipt"
	[[ "${#proof[@]}" == 7 ]] || return 1
	[[ "${proof[0]}" == native-runtime-v1 &&
		"${proof[2]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ &&
		"${proof[3]}" =~ ^[0-9a-f]{64}$ && "${proof[4]}" =~ ^[0-9a-f]{40}$ &&
		"${proof[6]}" =~ ^[0-9a-f]{64}$ ]] || return 1
	prefix="${proof[5]}"
	case "$key" in
	nodejs)
		[[ "${proof[1]}" == nvm && "$prefix" == "${NVM_DIR:-$HOME/.nvm}/versions/node/v${proof[2]}" ]] || return 1
		binary=node
		;;
	npm)
		[[ "${proof[1]}" == nvm ]] || return 1
		dotfiles_catalog_native_owned nodejs || return 1
		mapfile -t node_proof <"$HOME/.local/share/dotfiles-catalog/nodejs.native"
		[[ "$prefix" == "${node_proof[5]}" ]] || return 1
		binary=npm
		;;
	go)
		[[ "${proof[1]}" == asdf && "$prefix" == "${ASDF_DATA_DIR:-$HOME/.asdf}/installs/golang/${proof[2]}/go" ]] || return 1
		binary=go
		;;
	*) return 1 ;;
	esac
	if [[ "$key" == go ]]; then
		local wrapper="$HOME/.local/share/dotfiles-catalog/go.command"
		[[ -d "$prefix" && ! -L "$prefix" && "$(realpath -- "$prefix")" == "$prefix" &&
		-x "$prefix/bin/go" && "$(realpath -- "$prefix/bin/go")" == "$prefix/bin/go" &&
		-f "$wrapper" && ! -L "$wrapper" && -O "$wrapper" && -x "$wrapper" &&
		-L "$HOME/.local/bin/go" && "$(readlink -- "$HOME/.local/bin/go")" == "$wrapper" ]] || return 1
		[[ "$(cat "$wrapper")" == "$(dotfiles_catalog_native_go_command "$prefix")" ]]
		return $?
	fi
	[[ -d "$prefix" && ! -L "$prefix" && "$(realpath -- "$prefix")" == "$prefix" &&
	-L "$HOME/.local/bin/$binary" && "$(readlink -- "$HOME/.local/bin/$binary")" == "$prefix/bin/$binary" &&
	-x "$HOME/.local/bin/$binary" ]] || return 1
	resolved="$(realpath -- "$HOME/.local/bin/$binary")" || return 1
	if [[ "$key" == npm ]]; then
		[[ "$resolved" == "$prefix/lib/node_modules/npm/bin/npm-cli.js" ]]
	else
		[[ "$resolved" == "$prefix/bin/$binary" ]]
	fi
}

dotfiles_catalog_native_go_command() {
	printf '%s\n' '#!/usr/bin/env bash' 'export GOTOOLCHAIN=local'
	# shellcheck disable=SC2016  # The generated wrapper forwards runtime arguments.
	printf 'exec %q "$@"\n' "$1/bin/go"
}

dotfiles_catalog_native_go_shim_owned() {
	local path="$1" receipt="$HOME/.local/share/dotfiles-catalog/go.shims" size expected actual
	[[ "$path" == "${ASDF_DATA_DIR:-$HOME/.asdf}/shims/go" && -f "$path" && ! -L "$path" && -O "$path" &&
		-f "$receipt" && ! -L "$receipt" && -O "$receipt" ]] || return 1
	size="$(stat -c %s -- "$receipt")" || return 1
	[[ "$size" =~ ^[0-9]+$ && "$size" -le 65536 ]] || return 1
	expected="$(awk -F '\t' '$1=="go" {value=$2; count++} END {if(count!=1) exit 1; print value}' "$receipt")" || return 1
	[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
	actual="$(sha256sum -- "$path")" || return 1
	[[ "${actual%% *}" == "$expected" ]]
}
