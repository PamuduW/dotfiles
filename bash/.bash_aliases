# shellcheck shell=bash

# ------------------------------------
# Navigation helpers
# ------------------------------------
alias ..='cd ..'          # go up one directory
alias ...='cd ../..'      # go up two levels
alias ....='cd ../../..'  # go up three levels
alias c='clear'           # clear the terminal screen
alias h='history'         # show shell history

# ------------------------------------
# Improved listing and stats
# ------------------------------------
alias ls='ls --color=auto'     # show colors for file types
alias ll='ls -alF'             # detailed list with types
alias la='ls -A'               # show all but . and ..
alias l='ls -CF'               # compact multi-column
alias dfh='df -h'              # disk usage, human-readable
alias duh='du -sh *'           # sizes of items here
alias tree1='tree -L 1'        # tree view, depth 1
alias tree2='tree -L 2'        # tree view, depth 2

# ------------------------------------
# Quick system info
# ------------------------------------
alias ports='ss -tulpen'       # show listening/tcp/udp with details
alias mem='free -h'            # memory usage human-readable
alias cpu='top'                # CPU usage (interactive)
alias ipinfo='ip a'            # IP configuration
alias myip='curl ifconfig.me'  # external IP

# ------------------------------------
# Search utilities
# ------------------------------------
alias grep='grep --color=auto'   # colorize grep output
alias egrep='egrep --color=auto' # colorize egrep output
alias fgrep='fgrep --color=auto' # colorize fgrep output

# ------------------------------------
# Git shortcuts
# ------------------------------------
alias gitlog='git log --oneline --graph --decorate --all'  # short visual log

# ------------------------------------
# Docker shortcuts
# ------------------------------------
alias dpot="docker start portainer && echo 'Portainer started at https://localhost:9443'"   # start portainer
alias dpotstop="docker stop portainer && echo 'Portainer stopped'"  # stop portainer

# ------------------------------------
# Shell productivity
# ------------------------------------
alias reload='source ~/.bashrc'            # reload shell config
alias shfmt-format='shfmt -i 2 -bn -ci -sr -w .'  # format shell scripts

# ------------------------------------
# System maintenance
# ------------------------------------
alias aptup='sudo apt update && sudo apt upgrade -y'  # full update
alias aptclean='sudo apt autoremove -y && sudo apt autoclean'  # cleanup

# ------------------------------------
# Utilities
# ------------------------------------
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'  # desktop notification
alias cleanzone='find . -name "*Zone.Identifier" -delete'  # remove Windows Zone.Identifier files

# ------------------------------------
# Safety wrappers
# ------------------------------------
alias cp='cp -i'     # prompt before overwrite
alias mv='mv -i'     # prompt before overwrite
alias rm='rm -i'     # prompt before removal
