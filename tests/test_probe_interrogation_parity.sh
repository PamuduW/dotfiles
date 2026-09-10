#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# Interrogation exists twice, and unlike the readings it cannot be compared by
# enumerating states in the abstract: it asks the machine, so the states have to
# be built. Every case below builds one -- a HOME with or without a key, a fonts
# directory with and without its version file, a stow link pointing into the
# wrong checkout, a wsl.conf whose value is commented out -- and runs both
# implementations against it.
#
# The Bash side is not scaffolding and this test is not temporary: `python3`
# belongs to the optional `python` component, so a first setup that deselects it
# prints its install summary with no interpreter. The two stay in step.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1

if ! command -v python3 >/dev/null 2>&1; then
	printf 'ok - probe interrogation parity skipped; python3 unavailable\n'
	exit 0
fi

# The harness replaces PATH with fake binaries and blocks any that a test has
# not configured, which is right for everything else here and wrong for the Git
# probes: what they are being compared on is what real `git config` reports.
# Captured before the harness takes over, and used only for those cases.
TEST_REAL_PATH="$PATH"

# shellcheck source=tests/lib/harness.sh
source "$TEST_DIR/lib/harness.sh"
test_harness_init
test_harness_report_init
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/wsl_conf.sh"
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/components/probes.sh"

PY_DIR="$REPO_DIR/scripts/lib/shared/python"
failures=0
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# py_probe <key> [repo]
py_probe() {
	python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PY_DIR')
import probes
print(probes.probe(sys.argv[1], Path(sys.argv[2])))
" "$1" "${2:-$REPO_DIR}"
}

compare() {
	local label="$1" want="$2" got="$3"
	if [[ "$want" == "$got" ]]; then
		return 0
	fi
	printf '   %s\n     bash:   %s\n     python: %s\n' "$label" "$want" "$got" >&2
	failures=$((failures + 1))
}

test_monaspace_states() {
	local before=$failures home fonts case_name
	for case_name in absent empty fonts-no-version fonts-with-version; do
		home="$work/fonts-$case_name"
		fonts="$home/.local/share/fonts/monaspace"
		mkdir -p "$home"
		[[ "$case_name" == absent ]] || mkdir -p "$fonts"
		case "$case_name" in
		fonts-no-version | fonts-with-version)
			: >"$fonts/Neon-Regular.otf"
			: >"$fonts/Argon-Regular.otf"
			;;
		esac
		[[ "$case_name" == fonts-with-version ]] && printf '1.400\n' >"$fonts/.version"
		compare "monaspace $case_name" \
			"$(HOME="$home" _comp_probe_monaspace_fonts)" \
			"$(HOME="$home" py_probe monaspace_fonts)"
	done
	((failures == before))
}

test_stow_states() {
	local before=$failures home repo case_name
	repo="$work/stow-repo"
	mkdir -p "$repo/bash" "$repo/readline" "$repo/bin/bin"
	: >"$repo/bash/.bashrc"
	: >"$repo/bash/.bash_aliases"
	: >"$repo/readline/.inputrc"
	local name
	for name in ex clip codex-rc git dotfiles; do : >"$repo/bin/bin/$name"; done

	for case_name in none all partial wrong-target dangling; do
		home="$work/stow-$case_name"
		mkdir -p "$home/bin"
		case "$case_name" in
		all | partial)
			ln -sf "$repo/bash/.bashrc" "$home/.bashrc"
			ln -sf "$repo/bash/.bash_aliases" "$home/.bash_aliases"
			ln -sf "$repo/readline/.inputrc" "$home/.inputrc"
			for name in ex clip codex-rc git dotfiles; do
				[[ "$case_name" == partial && "$name" == dotfiles ]] && continue
				ln -sf "$repo/bin/bin/$name" "$home/bin/$name"
			done
			;;
		wrong-target)
			# A link into another checkout is as missing as no link: it is not
			# this repository's file, and following it silently would report a
			# machine set up from somewhere else as correct.
			mkdir -p "$work/other/bash"
			: >"$work/other/bash/.bashrc"
			ln -sf "$work/other/bash/.bashrc" "$home/.bashrc"
			;;
		dangling)
			ln -sf "$repo/bash/gone" "$home/.bashrc"
			;;
		esac
		compare "stow $case_name" \
			"$(HOME="$home" DOTFILES_DIR="$repo" _comp_probe_dotfiles)" \
			"$(HOME="$home" py_probe dotfiles "$repo")"
	done
	((failures == before))
}

test_wsl_conf_states() {
	local before=$failures conf case_name
	for case_name in absent empty both boot-only commented wrong-section duplicate-last-wins trailing-space; do
		conf="$work/wsl-$case_name.conf"
		case "$case_name" in
		absent) rm -f -- "$conf" ;;
		empty) : >"$conf" ;;
		both) printf '[boot]\nsystemd=true\n\n[interop]\nappendWindowsPath=true\n' >"$conf" ;;
		boot-only) printf '[boot]\nsystemd=true\n' >"$conf" ;;
		commented) printf '[boot]\nsystemd=true # on\n\n[interop]\nappendWindowsPath=true\n' >"$conf" ;;
		wrong-section) printf '[interop]\nsystemd=true\nappendWindowsPath=true\n' >"$conf" ;;
		duplicate-last-wins) printf '[boot]\nsystemd=false\nsystemd=true\n\n[interop]\nappendWindowsPath=true\n' >"$conf" ;;
		trailing-space) printf '[boot]\n  systemd = true  \n\n[interop]\n appendWindowsPath = true \n' >"$conf" ;;
		esac
		compare "wsl.conf $case_name" \
			"$(DOTFILES_WSL_CONF="$conf" _comp_probe_wsl_conf)" \
			"$(DOTFILES_WSL_CONF="$conf" py_probe wsl_conf)"
	done
	((failures == before))
}

test_git_states() {
	local before=$failures config case_name
	for case_name in empty name-only both-identity helper-only defaults-only complete; do
		config="$work/git-$case_name.config"
		: >"$config"
		local -a settings=()
		case "$case_name" in
		name-only) settings=('user.name' 'Ada Lovelace') ;;
		both-identity) settings=('user.name' 'Ada Lovelace' 'user.email' 'ada@example.com') ;;
		helper-only) settings=('credential.helper' 'store') ;;
		defaults-only) settings=(
			'submodule.recurse' 'true' 'fetch.recurseSubmodules' 'on-demand'
			'push.recurseSubmodules' 'check' 'status.submoduleSummary' 'true'
		) ;;
		complete) settings=(
			'user.name' 'Ada Lovelace' 'user.email' 'ada@example.com'
			'credential.helper' 'store'
			'submodule.recurse' 'true' 'fetch.recurseSubmodules' 'on-demand'
			'push.recurseSubmodules' 'check' 'status.submoduleSummary' 'true'
		) ;;
		esac
		local index
		for ((index = 0; index < ${#settings[@]}; index += 2)); do
			PATH="$TEST_REAL_PATH" GIT_CONFIG_GLOBAL="$config" GIT_CONFIG_NOSYSTEM=1 \
				git config --global "${settings[$index]}" "${settings[$index + 1]}"
		done

		compare "git identity $case_name" \
			"$(PATH="$TEST_REAL_PATH" GIT_CONFIG_GLOBAL="$config" GIT_CONFIG_NOSYSTEM=1 _comp_probe_git_identity)" \
			"$(PATH="$TEST_REAL_PATH" GIT_CONFIG_GLOBAL="$config" GIT_CONFIG_NOSYSTEM=1 py_probe git_identity)"
		compare "git credential $case_name" \
			"$(PATH="$TEST_REAL_PATH" GIT_CONFIG_GLOBAL="$config" GIT_CONFIG_NOSYSTEM=1 _comp_probe_git_credential)" \
			"$(PATH="$TEST_REAL_PATH" GIT_CONFIG_GLOBAL="$config" GIT_CONFIG_NOSYSTEM=1 py_probe git_credential)"
	done
	((failures == before))
}

# Layer two of the oracle ADR-0001 names: both implementations against the state
# this machine is actually in. It proves nothing about states this machine is
# not in, which is what every case above is for.
test_this_machine() {
	local before=$failures key
	for key in monaspace_fonts wsl_conf; do
		compare "live $key" "$("_comp_probe_$key")" "$(py_probe "$key")"
	done
	for key in git_identity git_credential; do
		compare "live $key" \
			"$(PATH="$TEST_REAL_PATH" "_comp_probe_$key")" \
			"$(PATH="$TEST_REAL_PATH" py_probe "$key")"
	done
	compare "live dotfiles" "$(_comp_probe_dotfiles)" "$(py_probe dotfiles "$REPO_DIR")"
	((failures == before))
}

check 'the fonts probe agrees on absent, empty, and versioned installs' test_monaspace_states
check 'the stow probe agrees on missing, wrong, and dangling links' test_stow_states
check 'the wsl.conf probe agrees on every shape of that file' test_wsl_conf_states
check 'the Git probes agree across identity and submodule defaults' test_git_states
check 'both implementations agree about this machine' test_this_machine

test_harness_cleanup
finish_tests
