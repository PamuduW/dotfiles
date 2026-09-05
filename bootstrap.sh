#!/usr/bin/env bash
# Fresh-machine bootstrap.
#
#   curl -fsSL https://raw.githubusercontent.com/PamuduW/dotfiles/main/bootstrap.sh | bash
#
# This script is fetched and run before either repository exists, so it stays
# self-contained and deliberately small: preflight, ask what to install, install
# git if it is missing, obtain the repositories, then hand off to the installers
# that already live in them. It contains no component logic, no agent
# configuration, and no token handling. Its only direct sudo use is installing
# git.
#
# Design: new_setup docs/designs/bootstrap/README.md
set -euo pipefail

DOTFILES_URL="${BOOTSTRAP_DOTFILES_URL:-https://github.com/PamuduW/dotfiles}"
AGENTBOT_URL="${BOOTSTRAP_AGENTBOT_URL:-https://github.com/PamuduW/agentbot}"
DOTFILES_DIR="${BOOTSTRAP_DOTFILES_DIR:-$HOME/dotfiles}"
AGENTBOT_DIR="${BOOTSTRAP_AGENTBOT_DIR:-$HOME/agentbot}"
# `dotfiles full-update` resolves Agentbot as the sibling of the Dotfiles
# checkout, so the two destinations must share a parent.
BOOTSTRAP_SELECTION="${BOOTSTRAP_SELECTION:-}"
WANT_DOTFILES=0
WANT_AGENTBOT=0
SELECTION=1

_bold=''
_reset=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	_bold=$'\033[1m'
	_reset=$'\033[0m'
fi

msg() { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$_bold" "$*" "$_reset"; }
err() { printf 'Error: %s\n' "$*" >&2; }

# Recorded for the closing summary so the operator sees one honest list.
SUMMARY=()
record() { SUMMARY+=("$1"); }

has() { command -v "$1" >/dev/null 2>&1; }

# `curl ... | bash` makes stdin the pipe, so `-t 0` is false even though the
# operator is sitting at a terminal. That is the documented way to run this
# script, so ask whether the controlling terminal can be opened instead -- it is
# what the prompts actually read from.
interactive() {
	(exec 3</dev/tty) 2>/dev/null
}

# Answers are returned in ANSWER rather than on stdout: command substitution
# would run this in a subshell, and the scripted-answer cursor below has to
# survive between prompts.
ANSWER=''
_answer_index=0

ask() {
	local prompt="$1" default="$2" reply=''
	if [[ -n "${BOOTSTRAP_ANSWERS+x}" ]]; then
		# Test and automation seam: newline-separated answers, consumed in
		# order. An exhausted or blank entry falls back to the default.
		local -a scripted=()
		mapfile -t scripted <<<"$BOOTSTRAP_ANSWERS"
		reply="${scripted[$_answer_index]:-}"
		_answer_index=$((_answer_index + 1))
	elif interactive; then
		read -r -p "$prompt" reply </dev/tty || reply=''
	fi
	ANSWER="${reply:-$default}"
}

# --- preflight ---------------------------------------------------------------

preflight() {
	local missing=()
	step 'Preflight'
	if ! { [[ -r /etc/os-release ]] && grep -qiE 'debian|ubuntu' /etc/os-release; }; then
		missing+=('a Debian or Ubuntu userland (this setup targets WSL Ubuntu)')
	fi
	has curl || missing+=('curl')
	[[ -w "$HOME" ]] || missing+=("a writable HOME (found $HOME)")
	if ! has git; then
		has sudo || missing+=('git, and sudo to install it')
		has apt-get || missing+=('git, and apt-get to install it')
	fi
	# Report every problem at once. Failing on the first one turns a single fix
	# into a sequence of reruns.
	if ((${#missing[@]} > 0)); then
		err 'this machine is not ready:'
		printf '  - %s\n' "${missing[@]}" >&2
		return 1
	fi
	msg '  Environment looks usable.'
}

# --- selection ---------------------------------------------------------------

choose_targets() {
	local choice
	if [[ -n "$BOOTSTRAP_SELECTION" ]]; then
		choice="$BOOTSTRAP_SELECTION"
	else
		step 'What should this machine get?'
		msg ''
		msg '  1) Dotfiles and Agentbot   (recommended)'
		msg '  2) Dotfiles only'
		msg '  3) Agentbot only'
		msg ''
		ask '  Choice [1]: ' 1
		choice="$ANSWER"
	fi
	SELECTION="${choice:-1}"
	case "$choice" in
	1 | '') WANT_DOTFILES=1 WANT_AGENTBOT=1 SELECTION=1 ;;
	2) WANT_DOTFILES=1 WANT_AGENTBOT=0 ;;
	3) WANT_DOTFILES=0 WANT_AGENTBOT=1 ;;
	*)
		err "unknown choice: $choice (expected 1, 2, or 3)"
		return 1
		;;
	esac
}

# --- repository acquisition --------------------------------------------------

# Accept every spelling of the same GitHub repository, including the name it
# used before the rename: GitHub redirects the old URL, so an existing checkout
# legitimately still carries it.
remote_matches() {
	local remote="$1" url="$2" path
	path="${url#https://github.com/}"
	path="${path%.git}"
	local -a accepted=(
		# The configured URL always matches itself, whatever form it takes.
		"$url" "${url%.git}" "${url%.git}.git"
		"https://github.com/${path}" "https://github.com/${path}.git"
		"git@github.com:${path}" "git@github.com:${path}.git"
		"ssh://git@github.com/${path}" "ssh://git@github.com/${path}.git"
	)
	# legacy repository name: accepted on purpose so a checkout made before the
	# rename is adopted rather than rejected. GitHub still redirects it.
	local legacy='agent_bootstrap'
	local owner
	case "$path" in
	*/agentbot)
		owner="${path%/agentbot}"
		accepted+=(
			"https://github.com/${owner}/${legacy}" "https://github.com/${owner}/${legacy}.git"
			"git@github.com:${owner}/${legacy}" "git@github.com:${owner}/${legacy}.git"
		)
		;;
	esac
	local candidate
	for candidate in "${accepted[@]}"; do
		[[ "$remote" == "$candidate" ]] && return 0
	done
	return 1
}

# Never deletes, moves, or renames anything: an unexpected destination stops the
# run and is reported, so a rerun after a fix always makes progress.
obtain_repo() {
	local url="$1" dest="$2" label="$3" remote
	if [[ ! -e "$dest" ]]; then
		step "Clone $label into $dest"
		GIT_TERMINAL_PROMPT=0 git clone "$url" "$dest" || {
			err "could not clone $label from $url"
			return 1
		}
		record "cloned   $label -> $dest"
		return 0
	fi
	if [[ ! -d "$dest/.git" ]]; then
		err "$dest already exists and is not a Git repository. Move it aside, then rerun."
		return 1
	fi
	if ! remote="$(git -C "$dest" remote get-url origin 2>/dev/null)"; then
		err "$dest has no origin remote. Inspect it, then rerun."
		return 1
	fi
	if ! remote_matches "$remote" "$url"; then
		err "$dest points at $remote, not $url. Inspect it, then rerun."
		return 1
	fi
	if [[ -n "$(git -C "$dest" status --porcelain)" ]]; then
		err "$dest has uncommitted changes. Commit or stash them, then rerun."
		git -C "$dest" status --short >&2
		return 1
	fi
	msg "  Reusing the existing $label checkout at $dest."
	record "adopted  $label -> $dest"
}

ensure_git() {
	has git && return 0
	step 'Install git'
	sudo apt-get update -qq || {
		err 'apt-get update failed; cannot install git'
		return 1
	}
	sudo apt-get install -y git || {
		err 'could not install git'
		return 1
	}
	record 'installed git'
}

# --- handoff -----------------------------------------------------------------

agentbot_prerequisites() {
	# Agentbot's installer needs these, and Dotfiles is what provides them. Name
	# the component rather than the binary so the fix is obvious.
	local missing=()
	has python3 || missing+=('python3 (Dotfiles component: python)')
	python3 -c 'import yaml' >/dev/null 2>&1 || missing+=('PyYAML (Dotfiles component: python)')
	has node || missing+=('node (Dotfiles component: nodejs)')
	has npx || missing+=('npx (Dotfiles component: nodejs)')
	((${#missing[@]} == 0)) && return 0
	err 'Agentbot cannot be installed yet; these are missing:'
	printf '  - %s\n' "${missing[@]}" >&2
	err 'Rerun and choose "Dotfiles and Agentbot" so Dotfiles installs them first.'
	return 1
}

# Both installers return 2 to mean "the checkout moved forward, so stop and
# rerun from the new state". That is a normal outcome, not a failure: it is how
# an adopted checkout catches up. Restart from the updated script rather than
# reporting a failure the operator would have to interpret.
restart_after_repository_update() {
	local what="$1"
	if [[ -n "${BOOTSTRAP_RESTARTED:-}" ]]; then
		err "$what updated its checkout again after a restart; stopping to avoid a loop."
		err "Rerun $DOTFILES_DIR/bootstrap.sh when ready."
		return 1
	fi
	msg ''
	msg "  $what updated its checkout. Restarting from the updated script."
	BOOTSTRAP_RESTARTED=1 \
		BOOTSTRAP_SELECTION="$SELECTION" \
		exec "$DOTFILES_DIR/bootstrap.sh"
}

run_dotfiles() {
	local rc=0
	step 'Install Dotfiles'
	msg '  The component menu opens next. Nothing outside it is selected for you.'
	"$DOTFILES_DIR/install.sh" --initial || rc=$?
	if ((rc == 2)); then
		restart_after_repository_update Dotfiles
		return 1
	fi
	if ((rc != 0)); then
		record 'FAILED   dotfiles install'
		return 1
	fi
	record 'ran      dotfiles install'

	# Always update straight after install, before anything moves on. Never
	# full-update: that asserts the Agentbot sibling and delegates to
	# `agentbot full`, so it fails on a Dotfiles-only machine and duplicates the
	# Agentbot phase this script already sequences.
	step 'Update Dotfiles'
	"$DOTFILES_DIR/bin/bin/dotfiles" update || {
		record 'FAILED   dotfiles update'
		return 1
	}
	record 'ran      dotfiles update'
}

run_agentbot() {
	local rc=0
	agentbot_prerequisites || return 1
	step 'Install Agentbot'
	AGENTBOT_INSTALL_CONFIRM=yes "$AGENTBOT_DIR/install.sh" install || rc=$?
	if ((rc == 2)); then
		restart_after_repository_update Agentbot
		return 1
	fi
	if ((rc != 0)); then
		record 'FAILED   agentbot install'
		return 1
	fi
	record 'ran      agentbot install'
	step 'Update Agentbot'
	AGENTBOT_INSTALL_CONFIRM=yes "$AGENTBOT_DIR/install.sh" update || {
		record 'FAILED   agentbot update'
		return 1
	}
	record 'ran      agentbot update'
}

# --- plan and summary --------------------------------------------------------

destination_note() {
	if [[ -e "$1" ]]; then
		printf 'reuse if it matches, otherwise stop'
	else
		printf 'clone'
	fi
}

print_plan() {
	step 'Plan'
	if ((WANT_DOTFILES == 1)); then
		msg "  Dotfiles  $DOTFILES_DIR   ($(destination_note "$DOTFILES_DIR"))"
	fi
	if ((WANT_AGENTBOT == 1)); then
		msg "  Agentbot  $AGENTBOT_DIR   ($(destination_note "$AGENTBOT_DIR"))"
	fi
	msg ''
	if ((WANT_DOTFILES == 1)); then
		msg '  Then: component menu, install, update.'
	fi
	if ((WANT_AGENTBOT == 1)); then
		if ((WANT_DOTFILES == 1)); then
			msg '  Then: asks before installing Agentbot.'
		else
			msg '  Then: Agentbot install and update.'
		fi
	fi
	if [[ -n "${BOOTSTRAP_RESTARTED:-}" ]]; then
		msg '  (already confirmed before the checkout was updated)'
		return 0
	fi
	ask '  Continue? [Y/n]: ' Y
	case "$ANSWER" in
	[Yy] | [Yy][Ee][Ss] | '') ;;
	*)
		msg 'Nothing was changed.'
		exit 0
		;;
	esac
}

print_summary() {
	step 'Summary'
	if ((${#SUMMARY[@]} == 0)); then
		msg '  Nothing to do.'
	else
		printf '  %s\n' "${SUMMARY[@]}"
	fi
	msg ''
	if ((WANT_AGENTBOT == 1)); then
		msg '  Next: run "agentbot boot" inside a repository to render its agent policy.'
	else
		msg "  Next: rerun this script and choose Agentbot to add it, or clone it to $AGENTBOT_DIR."
	fi
}

main() {
	# Report whatever happened, including on failure: a run that dies with no
	# summary leaves the operator guessing which steps ran.
	trap print_summary EXIT
	preflight
	choose_targets
	print_plan
	ensure_git

	if ((WANT_DOTFILES == 1)); then
		obtain_repo "$DOTFILES_URL" "$DOTFILES_DIR" Dotfiles
	fi
	if ((WANT_AGENTBOT == 1)); then
		obtain_repo "$AGENTBOT_URL" "$AGENTBOT_DIR" Agentbot
	fi

	if ((WANT_DOTFILES == 1)); then
		run_dotfiles
	fi

	if ((WANT_AGENTBOT == 1)); then
		ANSWER=Y
		# Only ask when Dotfiles just ran. A single-repository selection already
		# answered this question.
		if ((WANT_DOTFILES == 1)); then
			msg ''
			msg 'Dotfiles setup is complete.'
			ask 'Install and update Agentbot as well? [Y/n]: ' Y
		fi
		case "$ANSWER" in
		[Yy] | [Yy][Ee][Ss] | '') run_agentbot ;;
		*)
			record "skipped  agentbot install (run $AGENTBOT_DIR/install.sh install when ready)"
			;;
		esac
	fi

}

if [[ "${BOOTSTRAP_SOURCE_ONLY:-0}" != 1 ]]; then
	main "$@"
fi
