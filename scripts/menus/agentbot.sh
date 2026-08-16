#!/usr/bin/env bash
# shellcheck shell=bash

# shellcheck source=scripts/lib/repo_update.sh
_DOTFILES_AGENTBOT_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$_DOTFILES_AGENTBOT_LIB_DIR/repo_update.sh"
# shellcheck source=scripts/lib/agent_bootstrap_paths.sh
source "$_DOTFILES_AGENTBOT_LIB_DIR/agent_bootstrap_paths.sh"

DOTFILES_AGENTBOT_URL="${DOTFILES_AGENTBOT_URL:-git@github.com:PamuduW/agent_bootstrap.git}"

dotfiles_agentbot_home() {
	resolve_agent_bootstrap_home 2>/dev/null || agent_bootstrap_clone_home
}

dotfiles_agentbot_origin_allowed() {
	local origin="$1" rewrite_rules="${2:-}"
	repo_update_origin_allowed "$origin" 'PamuduW/agent_bootstrap' "$rewrite_rules"
}

dotfiles_agentbot_validate() {
	local home="$1" origin
	[[ -x "$home/install.sh" ]] || {
		printf 'Agentbot installer is missing: %s/install.sh\n' "$home" >&2
		return 1
	}
	origin="$(git -C "$home" remote get-url origin 2>/dev/null)" || {
		printf 'Agentbot origin is unavailable: %s\n' "$home" >&2
		return 1
	}
	if ! dotfiles_agentbot_origin_allowed "$origin"; then
		local rewrite_rules
		rewrite_rules="$(git config --global --get-regexp '^url\..*\.insteadof$' 2>/dev/null || true)"
		dotfiles_agentbot_origin_allowed "$origin" "$rewrite_rules" || {
			printf 'Agentbot origin is not allowlisted: %s\n' "$origin" >&2
			return 1
		}
	fi
}

dotfiles_agentbot_update_decision() {
	local event="$1" prompt="$2" answer=''
	case "$event" in
	pull-behind | continue-ahead) ;;
	*) return 1 ;;
	esac
	if [[ -n "${DOTFILES_UPDATE_CONFIRM:-}" ]]; then
		[[ "$DOTFILES_UPDATE_CONFIRM" == yes ]]
		return
	fi
	read_tty_line answer "$prompt [y/N] " || return 1
	case "$answer" in y | Y | yes | YES) return 0 ;; esac
	return 1
}

dotfiles_agentbot_update_all() {
	local home result_name outcome dotfiles_relaunch=false
	local -A dotfiles_result=() agentbot_result=()
	home="$(dotfiles_agentbot_home)"

	# Preflight every repository before requesting approval or pulling either one.
	repo_update_preflight "$DOTFILES_DIR" 'dotfiles repo' dotfiles_result 'PamuduW/dotfiles'
	repo_update_preflight "$home" 'agentbot repo' agentbot_result 'PamuduW/agent_bootstrap'
	for result_name in dotfiles_result agentbot_result; do
		local -n result_ref="$result_name"
		if [[ "${result_ref[safe]}" != 1 ]]; then
			repo_update_print_result "$result_name"
			printf 'Repository update check stopped: %s (%s).\n' \
				"${result_ref[dir]}" "${result_ref[reason]}" >&2
			return 1
		fi
	done

	# Collect all decisions before mutating either repository.
	for result_name in dotfiles_result agentbot_result; do
		repo_update_request_approval "$result_name" dotfiles_agentbot_update_decision || return 1
	done

	# Update Agentbot first and Dotfiles last. A Dotfiles pull requires a reload so
	# the updated bridge code is used before Agentbot is launched.
	for result_name in agentbot_result dotfiles_result; do
		repo_update_apply "$result_name" || return 1
		local -n result_ref="$result_name"
		outcome="${result_ref[outcome]}"
		[[ "$result_name" == dotfiles_result && "$outcome" == relaunch_required ]] && dotfiles_relaunch=true
	done

	if [[ "$dotfiles_relaunch" == true ]]; then
		printf '%sRepository fast-forward succeeded; reloading Dotfiles.%s\n' \
			"${C_GREEN:-}" "${C_RESET:-}"
		repo_update_wait_for_reload
		repo_update_relaunch "$DOTFILES_DIR/install.sh" --agents
	fi
}

dotfiles_agentbot_confirm() {
	local answer=''
	if [[ -n "${DOTFILES_AGENTBOT_CONFIRM:-}" ]]; then
		[[ "$DOTFILES_AGENTBOT_CONFIRM" == yes ]]
		return
	fi
	read_tty_line answer "  Clone Agentbot from $DOTFILES_AGENTBOT_URL to $(dotfiles_agentbot_home)? [y/N]: " || answer=n
	case "$answer" in y | Y | yes | YES) return 0 ;; esac
	return 1
}

dotfiles_launch_agentbot() {
	local home rc=0
	declare -F start_action_log >/dev/null 2>&1 && start_action_log
	home="$(dotfiles_agentbot_home)"
	if [[ ! -e "$home/install.sh" ]]; then
		printf 'Agentbot is not cloned at %s.\n' "$home"
		dotfiles_agentbot_confirm || {
			printf 'Agentbot launch cancelled.\n'
			return 0
		}
		agent_bootstrap_repo_url_allowed "$DOTFILES_AGENTBOT_URL" || return 1
		git clone "$DOTFILES_AGENTBOT_URL" "$home" || {
			printf 'Agentbot clone failed.\n' >&2
			return 1
		}
	fi
	dotfiles_agentbot_validate "$home" || return 1
	dotfiles_agentbot_update_all || return $?
	(
		cd "$home" || exit 1
		SETUP_CALLER=dotfiles ./install.sh
	) || rc=$?
	if ((rc == 0)); then
		# shellcheck disable=SC2034  # Consumed by the parent Dotfiles menu loop.
		DOTFILES_AGENTBOT_EXITED=true
	fi
	return "$rc"
}
