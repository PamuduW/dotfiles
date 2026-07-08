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
alias dpot="docker start portainer && echo 'Portainer started at https://localhost:9443'" # start portainer
alias dpotstop="docker stop portainer && echo 'Portainer stopped'"                        # stop portainer
dclean() {
	echo "This will remove ALL unused Docker data (images, containers, networks) AND volumes."
	read -r -p "Are you sure? [y/N] " _reply
	case "$_reply" in
		[yY][eE][sS]|[yY]) docker system prune -a --volumes -f ;;
		*) echo "Aborted." ;;
	esac
}

# ------------------------------------
# Shell productivity
# ------------------------------------
alias reload='source ~/.bashrc'                  # reload shell config
alias shfmt-format='shfmt -i 2 -bn -ci -sr -w .' # format shell scripts

# ------------------------------------
# System maintenance
# ------------------------------------
alias aptup='sudo apt update && sudo apt upgrade -y'
alias aptclean='sudo apt autoremove -y && sudo apt autoclean'

# ------------------------------------
# System/CLI updates — see also: dotfiles update | dotfiles upgrade
# ------------------------------------
alias update-cursor='agent update'
alias update-codex='npm i -g @openai/codex@latest'
alias update-claude='claude update'
alias update-copilot='copilot update'

update-all() {
	dotfiles upgrade
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
