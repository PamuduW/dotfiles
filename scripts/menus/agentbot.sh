#!/usr/bin/env bash
# shellcheck shell=bash

DOTFILES_AGENTBOT_URL="${DOTFILES_AGENTBOT_URL:-git@github.com:PamuduW/agent_bootstrap.git}"

dotfiles_agentbot_home() {
	if [[ -n "${AGENTBOT_HOME:-}" ]]; then
		printf '%s\n' "$AGENTBOT_HOME"
	else
		printf '%s\n' "$(dirname "$DOTFILES_DIR")/agent_bootstrap"
	fi
}

dotfiles_agentbot_origin_allowed() {
	local origin="$1" rewrite_rules="${2:-}"
	local key target prefix matched_prefix='' matched_target='' resolved

	case "$origin" in
	*://*@*) return 1 ;;
	git@github.com:PamuduW/agent_bootstrap.git|https://github.com/PamuduW/agent_bootstrap.git)
		return 0
		;;
	esac

	while IFS=$' \t' read -r key target; do
		[[ "$key" == url.*.insteadof ]] || continue
		prefix="${key#url.}"
		prefix="${prefix%.insteadof}"
		[[ -n "$prefix" ]] || continue
		case "$origin" in
			"$prefix"*)
				if ((${#prefix} > ${#matched_prefix})); then
					matched_prefix="$prefix"
					matched_target="$target"
				fi
				;;
		esac
	done <<<"$rewrite_rules"

	[[ -n "$matched_prefix" ]] || return 1
	resolved="${matched_target}${origin#"$matched_prefix"}"
	case "$resolved" in
	git@github.com:PamuduW/agent_bootstrap.git|https://github.com/PamuduW/agent_bootstrap.git)
		return 0
		;;
	*) return 1 ;;
	esac
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

dotfiles_agentbot_confirm() {
	local answer=''
	if [[ -n "${DOTFILES_AGENTBOT_CONFIRM:-}" ]]; then
		[[ "$DOTFILES_AGENTBOT_CONFIRM" == yes ]]
		return
	fi
	printf '  Clone Agentbot from %s to %s? [y/N]: ' "$DOTFILES_AGENTBOT_URL" "$(dotfiles_agentbot_home)" >/dev/tty
	IFS= read -r answer </dev/tty || answer=n
	case "$answer" in y|Y|yes|YES) return 0 ;; esac
	return 1
}

dotfiles_launch_agentbot() {
	local home rc=0
	home="$(dotfiles_agentbot_home)"
	if [[ ! -e "$home/install.sh" ]]; then
		printf 'Agentbot is not cloned at %s.\n' "$home"
		dotfiles_agentbot_confirm || {
			printf 'Agentbot launch cancelled.\n'
			return 0
		}
		git clone "$DOTFILES_AGENTBOT_URL" "$home" || {
			printf 'Agentbot clone failed.\n' >&2
			return 1
		}
	fi
	dotfiles_agentbot_validate "$home" || return 1
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
