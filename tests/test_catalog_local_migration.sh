#!/usr/bin/env bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$test_dir/.." && pwd)"
source "$test_dir/lib/harness.sh"
source "$test_dir/lib/catalog_fixture.sh"
test_harness_init
source "$root/scripts/lib/installers/load.sh"
artifact="$TEST_HARNESS_ROOT/uv-approved"
printf '%s\n' '#!/bin/sh' 'if [ "$1" = --version ]; then echo "uv 1.2.3"; else echo approved; fi' >"$artifact"
seal_fixture() {
	local digest
	digest="$(sha256sum "$1")"
	printf '%s\n' $'uv\towner\tany\tdotfiles' $'uv\tkind\tany\tsoftware' \
		$'uv\tversion\tany\t1.2.3' $'uv\tarchive\tany\traw' $'uv\tbinary\tany\tuv' \
		$'uv\turl\tany\thttps://fixture.invalid/uv' $'uv\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$2"
}
seal_fixture "$artifact" "$TEST_HARNESS_ROOT/catalog"

migration_case() (
	local mode="$1" status=0 old_path before version=1.2.2 source_artifact="$artifact" catalog="$TEST_HARNESS_ROOT/catalog" started elapsed
	trap 'printf "FAIL: local migration case %s at line %s\n" "$mode" "$LINENO" >&2' ERR
	export HOME="$TEST_HARNESS_ROOT/$mode/home"
	mkdir -p "$HOME/.local/bin" "$HOME/bin"
	export PATH="$HOME/bin:$HOME/.local/bin:/usr/bin:/bin"
	unset DOTFILES_MIGRATE_LOCAL_TOOLS DOTFILES_FORCE_REINSTALL DOTFILES_INTERACTIVE_TTY
	old_path="$HOME/.local/bin/uv"
	if [[ "$mode" == home-bin || "$mode" == publish-alias-failure ]]; then old_path="$HOME/bin/uv"; fi
	[[ "$mode" != newer ]] || version=9.0.0
	[[ "$mode" != unverifiable ]] || version=unknown
	[[ "$mode" != same-version ]] || version=1.2.3
	printf '%s\n' '#!/bin/sh' 'touch "$HOME/old-code-executed"' "echo 'uv $version'" >"$old_path"
	chmod +x "$old_path"
	if [[ "$mode" == nvm-global || "$mode" == multi-alias-failure ]]; then
		mkdir -p "$HOME/.nvm/versions/node/v24.22.1/bin"
		mv "$old_path" "$HOME/.nvm/versions/node/v24.22.1/bin/uv"
		old_path="$HOME/.nvm/versions/node/v24.22.1/bin/uv"
		PATH="${old_path%/*}:$PATH"
		[[ "$mode" != multi-alias-failure ]] || ln -s "$old_path" "$HOME/bin/uv"
	elif [[ "$mode" == chained-alias ]]; then
		mkdir "$HOME/tools"
		mv "$old_path" "$HOME/tools/uv"
		ln -s "$HOME/tools/uv" "$HOME/bin/uv"
		ln -s "$HOME/bin/uv" "$HOME/.local/bin/uv"
		old_path="$HOME/bin/uv"
	elif [[ "$mode" == timeout ]]; then
		printf '%s\n' '#!/bin/sh' '/usr/bin/sleep 10' 'echo "uv 1.2.2"' >"$old_path"
	elif [[ "$mode" == term-ignore ]]; then
		printf '%s\n' '#!/bin/sh' 'trap "" TERM' '/usr/bin/sleep 10' 'echo "uv 1.2.2"' >"$old_path"
	fi
	if [[ "$mode" == foreign-interactive || "$mode" == foreign-explicit ]]; then
		mkdir -p "$TEST_HARNESS_ROOT/$mode/foreign"
		cp "$old_path" "$TEST_HARNESS_ROOT/$mode/foreign/uv"
		PATH="$TEST_HARNESS_ROOT/$mode/foreign:$PATH"
	fi
	if [[ "$mode" == wrong-version ]]; then
		source_artifact="$HOME/wrong-version-payload"
		printf '%s\n' '#!/bin/sh' 'echo "uv 9.9.9"' >"$source_artifact"
		catalog="$TEST_HARNESS_ROOT/wrong-version-catalog"
		seal_fixture "$source_artifact" "$catalog"
	fi
	printf 'user setting\n' >"$HOME/.uv-user-setting"
	before="$(sha256sum "$old_path")"
	catalog_fixture_use "$catalog"
	curl() {
		printf called >>"$HOME/downloads"
		[[ "$mode" != failed-download ]] || return 71
		while (($#)); do
			if [[ "$1" == -o ]]; then
				cp "$source_artifact" "$2"
				[[ "$mode" != wrong-checksum ]] || printf '\n# changed payload\n' >>"$2"
				[[ "$mode" != changed-before-publish ]] || printf '\n# concurrent edit\n' >>"$old_path"
				return 0
			fi
			shift
		done
		return 72
	}
	mv() {
		if [[ ("$mode" == publish-alias-failure || "$mode" == multi-alias-failure) && "${!#}" == "$HOME/bin/uv" && "$*" == *'.uv.catalog.'* ]]; then return 73; fi
		if [[ "$mode" == rollback-failure && "${!#}" == "$HOME/.local/bin/uv" && "$*" == *'/previous-command '* ]]; then return 75; fi
		command mv "$@"
	}
	case "$mode" in
	default) ;;
	force) export DOTFILES_FORCE_REINSTALL=1 ;;
	foreign-interactive)
		export DOTFILES_INTERACTIVE_TTY=true
		ui_confirm_yes_no() {
			touch "$HOME/unexpected-prompt"
			return 0
		}
		;;
	declined | interactive | changed-after-consent)
		export DOTFILES_INTERACTIVE_TTY=true
		ui_confirm_yes_no() {
			[[ "$mode" != declined ]] || return 1
			[[ "$mode" != changed-after-consent ]] || printf '\n# concurrent edit\n' >>"$old_path"
			return 0
		}
		;;
	invalid-flag) export DOTFILES_MIGRATE_LOCAL_TOOLS=2 ;;
	*) export DOTFILES_MIGRATE_LOCAL_TOOLS=1 ;;
	esac
	if [[ "$mode" == post-publication-failure || "$mode" == rollback-failure ]]; then dotfiles_catalog_legacy_stamp() { return 74; }; fi
	started=$SECONDS
	dotfiles_catalog_install uv >"$HOME/install-output" 2>&1 || status=$?
	elapsed=$((SECONDS - started))
	[[ "$mode" != term-ignore || "$elapsed" -le 7 ]]
	case "$mode" in
	success | same-version | home-bin | chained-alias | nvm-global | interactive)
		[[ "$status" == 0 && "$("$HOME/.local/bin/uv" --origin)" == approved ]]
		dotfiles_catalog_owned uv
		[[ -f "$(dotfiles_catalog_root uv)/current/previous-command" || -f "$(dotfiles_catalog_root uv)/current/previous-alias-0" ]]
		[[ "$(uv --origin)" == approved ]]
		rm -f "$HOME/downloads"
		dotfiles_catalog_install uv
		[[ ! -e "$HOME/downloads" ]]
		;;
	default | force | declined | foreign-interactive)
		[[ "$status" == 0 && ! -e "$HOME/downloads" && ! -e "$HOME/old-code-executed" ]]
		[[ ! -e "$HOME/unexpected-prompt" ]]
		[[ "$(sha256sum "$old_path")" == "$before" ]]
		;;
	changed-after-consent | changed-before-publish)
		[[ "$status" != 0 && ! -L "$old_path" ]]
		grep -q 'concurrent edit' "$old_path"
		;;
	rollback-failure)
		local retained retained_digest
		[[ "$status" != 0 ]]
		retained="$(find "$(dotfiles_catalog_root uv)/releases" -name previous-command -type f)"
		[[ -x "$retained" && "$("$retained" --version)" == 'uv 1.2.2' ]]
		retained_digest="$(sha256sum "$retained")"
		[[ "${retained_digest%% *}" == "${before%% *}" ]]
		grep -q 'rollback failed; retaining release' "$HOME/install-output"
		;;
	*)
		[[ "$status" != 0 && "$(sha256sum "$old_path")" == "$before" ]]
		[[ ! -e "$(dotfiles_catalog_root uv)/current" && ! -L "$(dotfiles_catalog_root uv)/current" ]]
		;;
	esac
	[[ "$(cat "$HOME/.uv-user-setting")" == 'user setting' ]]
)
cases=(term-ignore foreign-interactive foreign-explicit success same-version home-bin chained-alias nvm-global interactive default force declined invalid-flag changed-after-consent changed-before-publish newer unverifiable timeout failed-download wrong-checksum wrong-version publish-alias-failure multi-alias-failure post-publication-failure rollback-failure)
if (($#)); then cases=("$@"); fi
for mode in "${cases[@]}"; do
	migration_case "$mode"
	printf 'ok - unreceipted local migration: %s\n' "$mode"
done
