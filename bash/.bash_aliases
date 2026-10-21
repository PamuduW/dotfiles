# shellcheck shell=bash

# ------------------------------------
# Navigation helpers
# ------------------------------------
alias ..='cd ..'         # go up one directory
alias ...='cd ../..'     # go up two levels
alias ....='cd ../../..' # go up three levels
alias c='clear'          # clear the terminal screen
alias h='history'        # show shell history

# ------------------------------------
# Improved listing and stats (eza)
# ------------------------------------
if command -v eza >/dev/null 2>&1; then
	alias ls='eza --color=auto'
	alias ll='eza -alF --git'
	alias la='eza -a'
	alias l='eza -F'
	alias tree1='eza --tree --level=1'
	alias tree2='eza --tree --level=2'
else
	alias ls='ls --color=auto'
	alias ll='ls -alF'
	alias la='ls -A'
	alias l='ls -CF'
	alias tree1='tree -L 1'
	alias tree2='tree -L 2'
fi
alias dfh='df -h'
alias duh='du -sh *'

# ------------------------------------
# Quick system info
# ------------------------------------
alias ports='ss -tulpen'      # show listening/tcp/udp with details
alias mem='free -h'           # memory usage human-readable
alias cpu='top'               # CPU usage (interactive)
alias ipinfo='ip a'           # IP configuration
alias myip='curl ifconfig.me' # external IP

# ------------------------------------
# Search utilities
# ------------------------------------
alias grep='grep --color=auto'   # colorize grep output
alias egrep='egrep --color=auto' # colorize egrep output
alias fgrep='fgrep --color=auto' # colorize fgrep output

# ------------------------------------
# Git shortcuts
# ------------------------------------
alias gitlog='git log --oneline --graph --decorate --all' # short visual log

# ------------------------------------
# Docker shortcuts
# ------------------------------------
if [[ -z "${DOTFILES_DIR:-}" ]]; then
	_dotfiles_aliases="${BASH_SOURCE[0]}"
	if [[ -L "$_dotfiles_aliases" ]]; then
		_dotfiles_aliases="$(readlink -f "$_dotfiles_aliases")"
	fi
	DOTFILES_DIR="$(cd "$(dirname "$_dotfiles_aliases")/.." && pwd)"
fi
# shellcheck source=scripts/lib/docker.sh
if [[ -f "$DOTFILES_DIR/scripts/lib/docker.sh" ]]; then
	# shellcheck disable=SC1091
	source "$DOTFILES_DIR/scripts/lib/docker.sh"
fi

dpot() {
	run_docker start portainer || return $?
	local started_at logs token attempt
	if started_at="$(run_docker inspect --format '{{.State.StartedAt}}' portainer 2>/dev/null)" && [[ -n "$started_at" ]]; then
		for ((attempt = 0; attempt < 10; attempt++)); do
			# Docker sends container stderr logs to stderr too; run_docker hides it.
			if ! logs="$(docker logs --since "$started_at" --tail 200 portainer 2>&1)"; then
				logs="$(sudo docker logs --since "$started_at" --tail 200 portainer 2>&1)" || break
			fi
			token="$(sed -nE 's/^[[:space:]]*setup_token=([^[:space:]]+)[[:space:]]*$/\1/p' <<<"$logs" | tail -n 1)"
			if [[ -n "$token" ]]; then
				printf 'Setup token: %s\n' "$token"
				echo 'Portainer started at https://localhost:9443'
				return 0
			fi
			if [[ "$logs" == *'starting HTTPS server'* ]]; then
				echo 'Portainer started at https://localhost:9443'
				return 0
			fi
			sleep 0.5
		done
	fi
	echo 'If first-time setup asks for a token, check: docker logs portainer'
	echo 'Portainer started at https://localhost:9443'
}
dpotstop() {
	run_docker stop portainer && echo 'Portainer stopped'
}
dclean() {
	echo "This will remove ALL unused Docker data (images, containers, networks) AND volumes."
	read -r -p "Are you sure? [y/N] " _reply
	case "$_reply" in
	[yY][eE][sS] | [yY]) docker system prune -a --volumes -f ;;
	*) echo "Aborted." ;;
	esac
}

# ------------------------------------
# Shell productivity
# ------------------------------------
alias reload='source ~/.bashrc' # reload shell config
shfmt_format() {
	if (($# == 0)); then
		echo 'Usage: shfmt_format FILE...'
		return 2
	fi
	shfmt -w "$@"
}
alias shfmt-format='shfmt_format'

# ------------------------------------
# System maintenance
# ------------------------------------
alias aptup='sudo apt update && sudo apt upgrade -y'
alias aptclean='sudo apt autoremove -y && sudo apt autoclean'

# ------------------------------------
# System/CLI updates — see also: dotfiles update | dotfiles fu
# ------------------------------------
alias update-cursor='agent update'
alias update-codex='dotfiles update'
alias update-claude='claude update'

update-all() {
	dotfiles update
}

# ------------------------------------
# Utilities
# ------------------------------------
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'     # desktop notification
alias cleanzone='find . -type f \( -name "*Zone.Identifier*" -o -name "*:Zone.Identifier*" -o -name "*sec.endpointdlp*" -o -name "*:sec.endpointdlp*" \) -print -delete' # remove Windows metadata stream sidecar files

# ------------------------------------
# Safety wrappers
# ------------------------------------
alias cp='cp -i' # prompt before overwrite
alias mv='mv -i' # prompt before overwrite
alias rm='rm -i' # prompt before removal
