#!/usr/bin/env bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$test_dir/.." && pwd)"
source "$test_dir/lib/harness.sh"
source "$test_dir/lib/catalog_fixture.sh"
test_harness_init
source "$root/scripts/lib/installers/load.sh"
mkdir -p "$TEST_HARNESS_ROOT/deb/DEBIAN"
printf '%s\n' 'Package: powershell' 'Version: 1.2.3' 'Architecture: amd64' \
	'Maintainer: Test <test@example.invalid>' 'Description: migration fixture' >"$TEST_HARNESS_ROOT/deb/DEBIAN/control"
dpkg-deb --build "$TEST_HARNESS_ROOT/deb" "$TEST_HARNESS_ROOT/powershell.deb" >/dev/null
digest="$(sha256sum "$TEST_HARNESS_ROOT/powershell.deb")"
printf '%s\n' $'powershell\towner\tany\tdotfiles' $'powershell\tkind\tany\tvendor-apt' \
	$'powershell\tversion\tany\t1.2.3' $'powershell\tarchive\tany\tdeb' \
	$'powershell\tpackage\tany\tpowershell' $'powershell\tbinary\tany\tpwsh' \
	$'powershell\turl\tany\thttps://fixture.invalid/powershell.deb' \
	$'powershell\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog"

migration_case() (
	local mode="$1" status=0 receipt force=0 case_name="$1"
	export HOME="$TEST_HARNESS_ROOT/$mode/home" PATH=/usr/bin:/bin
	mkdir -p "$HOME"
	unset DOTFILES_MIGRATE_APT_PACKAGES DOTFILES_INTERACTIVE_TTY
	catalog_fixture_use "$TEST_HARNESS_ROOT/catalog"
	printf '1.2.3\n' >"$HOME/installed"
	[[ "$mode" != older ]] || printf '1.2.2\n' >"$HOME/installed"
	[[ "$mode" != newer ]] || printf '9.0.0\n' >"$HOME/installed"
	printf 'keep\n' >"$HOME/settings"
	dpkg-query() {
		if [[ "$*" == *'db:Status-Status'* ]]; then
			if [[ "$mode" == foreign ]]; then
				printf 'installed\t1.2.3\tarm64\n'
				return
			fi
			printf 'installed\t%s\tamd64\n' "$(cat "$HOME/installed")"
		else cat "$HOME/installed"; fi
	}
	curl() {
		printf download >>"$HOME/downloads"
		[[ "$mode" != download-failure ]] || return 71
		while (($#)); do
			if [[ "$1" == -o ]]; then
				cp "$TEST_HARNESS_ROOT/powershell.deb" "$2"
				[[ "$mode" != download-changed ]] || printf '1.2.2\n' >"$HOME/installed"
				return
			fi
			shift
		done
		return 72
	}
	sudo() {
		printf '%s\n' "$*" >>"$HOME/mutations"
		case "$1" in
		apt-get)
			if [[ "$(cat "$HOME/installed")" == 1.2.3 && " $* " != *' --reinstall '* ]]; then return 75; fi
			if [[ " $* " == *' -s '* ]]; then
				[[ "$mode" != simulation-changed ]] || printf '1.2.2\n' >"$HOME/installed"
				return 0
			fi
			printf '1.2.3\n' >"$HOME/installed"
			[[ "$mode" != wrong-observation ]] || printf '1.2.2\n' >"$HOME/installed"
			[[ "$mode" != apt-failure ]] || return 73
			;;
		apt-mark) [[ "$2" == hold && "$mode" != hold-failure ]] ;;
		*) return 74 ;;
		esac
	}
	case "$mode" in
	default | force) ;;
	declined | changed | interactive)
		export DOTFILES_INTERACTIVE_TTY=true
		ui_confirm_yes_no() {
			[[ "$mode" != declined ]] || return 1
			[[ "$mode" != changed ]] || printf '1.2.2\n' >"$HOME/installed"
			return 0
		}
		;;
	invalid) export DOTFILES_MIGRATE_APT_PACKAGES=2 ;;
	*) export DOTFILES_MIGRATE_APT_PACKAGES=1 ;;
	esac
	[[ "$mode" != force ]] || force=1
	DOTFILES_FORCE_REINSTALL="$force" dotfiles_catalog_install_debs powershell >"$HOME/output" 2>&1 || status=$?
	receipt="$HOME/.local/share/dotfiles-catalog/powershell.apt"
	case "$mode" in
	success | older | interactive)
		[[ "$status" == 0 && -s "$HOME/downloads" && -s "$HOME/mutations" ]]
		dotfiles_catalog_apt_owned powershell powershell
		[[ "$(cat "$HOME/installed")" == 1.2.3 ]]
		;;
	default | force | declined)
		[[ "$status" == 0 && ! -e "$receipt" && ! -e "$HOME/downloads" && ! -e "$HOME/mutations" ]]
		;;
	download-failure)
		[[ "$status" == 71 && ! -e "$receipt" && ! -e "$HOME/mutations" ]]
		;;
	apt-failure)
		[[ "$status" == 73 && ! -e "$receipt" ]]
		grep -Fq 'package-manager recovery' "$HOME/output"
		mode=retry
		dotfiles_catalog_install_debs powershell >>"$HOME/output" 2>&1
		dotfiles_catalog_apt_owned powershell powershell
		;;
	download-changed)
		[[ "$status" == 2 && -s "$HOME/downloads" && ! -e "$receipt" && ! -e "$HOME/mutations" ]]
		;;
	simulation-changed)
		[[ "$status" == 2 && ! -e "$receipt" ]]
		[[ "$(wc -l <"$HOME/mutations")" == 1 ]]
		;;
	wrong-observation | hold-failure) [[ "$status" != 0 && ! -e "$receipt" ]] ;;
	*) [[ "$status" == 2 && ! -e "$receipt" && ! -e "$HOME/downloads" && ! -e "$HOME/mutations" ]] ;;
	esac
	[[ "$(cat "$HOME/settings")" == keep ]]
	printf 'ok - explicit apt migration: %s\n' "$case_name"
)
for mode in success older interactive default force declined invalid changed newer foreign download-failure download-changed simulation-changed wrong-observation hold-failure apt-failure; do migration_case "$mode"; done
