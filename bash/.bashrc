# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# If not running interactively, don't do anything (avoid breaking scripts)
case "$-" in
*i*) ;;
*) return ;;
esac

# Ensure ~/bin is on PATH (for stowed commands like ~/bin/ex)
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"

# Ensure ~/.local/bin is on PATH (for Cursor Agent and other user installs)
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

# Use Windows browser opener from WSL-aware tools when available
if command -v wslview >/dev/null 2>&1; then
	export BROWSER=wslview
fi

# Optional: bash-completion (if available)
if [ -r /etc/bash_completion ]; then
	. /etc/bash_completion
fi

# Initialize zoxide (smart directory jumping) if installed
if command -v zoxide >/dev/null 2>&1; then
	eval "$(zoxide init bash)"
fi

# Initialize fzf keybindings (Ctrl+R history, Ctrl+T file, Alt+C cd)
eval "$(fzf --bash 2>/dev/null)" || true

# Initialize direnv (directory-based environment loader) if installed
if command -v direnv >/dev/null 2>&1; then
	eval "$(direnv hook bash)"
fi

# --- History ---
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# --- dotfiles prompt (time + blank line + git symbols + exit code) ---

# Bright colors (PS1-safe when wrapped in \[ \])
c_reset="\[\e[0m\]"
c_time="\[\e[90m\]" # gray
c_user="\[\e[32m\]" # green
c_path="\[\e[34m\]" # blue
c_git="\[\e[33m\]"  # yellow
c_err="\[\e[31m\]"  # red

__dotfiles_git() {
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

	local branch staged dirty untracked symbols
	branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)"

	# ✚ = staged, ✱ = modified, ? = untracked
	git diff --cached --quiet >/dev/null 2>&1 || staged="✚"
	git diff --quiet >/dev/null 2>&1 || dirty="✱"
	[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ] && untracked="?"

	symbols="${staged}${dirty}${untracked}"

	if [ -n "$symbols" ]; then
		printf ' %s(%s %s)%s' "$c_git" "$branch" "$symbols" "$c_reset"
	else
		printf ' %s(%s)%s' "$c_git" "$branch" "$c_reset"
	fi
}

__dotfiles_prompt() {
	local exit_code=$? # MUST be first line
	local git_part err_part

	git_part="$(__dotfiles_git)"

	if [ "$exit_code" -ne 0 ]; then
		err_part=" ${c_err}✗${exit_code}${c_reset}"
	else
		err_part=""
	fi

	PS1="\n${c_time}\t ${c_user}\u@\h${c_reset} ${c_path}\w${c_reset}${git_part}${err_part}\n\$ "
}

__dotfiles_prompt_command() {
	__dotfiles_prompt
	history -a
	history -n
}

codex-safe() {
	codex -C "$PWD" -s workspace-write -a on-request "$@"
}

codex-host() {
	codex -C "$PWD" --approve-for-me "$@"
}

# Preserve any existing PROMPT_COMMAND; keep ours first so $? is correct.
if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare \-a'; then
	_dotfiles_prompt_registered=false
	for _dotfiles_prompt_entry in "${PROMPT_COMMAND[@]}"; do
		[[ "$_dotfiles_prompt_entry" == __dotfiles_prompt_command ]] && _dotfiles_prompt_registered=true
	done
	if [[ "$_dotfiles_prompt_registered" == false ]]; then
		PROMPT_COMMAND=(__dotfiles_prompt_command "${PROMPT_COMMAND[@]}")
	fi
elif [ -n "${PROMPT_COMMAND:-}" ]; then
	case ";${PROMPT_COMMAND// /};" in
	*';__dotfiles_prompt_command;'*) ;;
	*) PROMPT_COMMAND="__dotfiles_prompt_command; ${PROMPT_COMMAND}" ;;
	esac
else
	PROMPT_COMMAND="__dotfiles_prompt_command"
fi
unset _dotfiles_prompt_registered _dotfiles_prompt_entry

# --- nvm (Node Version Manager) ---
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# --- asdf (version manager) ---
export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"

# --- Agentbot MCP credentials ---
#
# The managed MCP entries reference their credential by environment variable
# name, never by value: Claude and Cursor render `${GITHUB_MCP_TOKEN}` into a
# header and Codex names it in `bearer_token_env_var`. A client launched from
# this shell inherits the variable; nothing on disk carries the secret into a
# configuration file.
#
# The token itself lives in a mode-0600 file under ~/.config/agentbot, written
# by Token Config. Read here only when the file is safe: a regular file, not a
# symlink, mode 600, in a mode-700 directory. Anything else is left unset, and
# `agentbot mcp status` reports the reference as missing rather than a shell
# silently exporting whatever a tampered file contained.
__dotfiles_export_agentbot_token() {
	local file="$1" key="$2" name="$3" line
	[ -f "$file" ] && [ ! -L "$file" ] || return 0
	[ "$(stat -c %a -- "$file" 2>/dev/null)" = 600 ] || return 0
	[ "$(stat -c %a -- "$(dirname -- "$file")" 2>/dev/null)" = 700 ] || return 0
	IFS= read -r line <"$file" || return 0
	case "$line" in
	"$key"=?*) export "$name=${line#"$key"=}" ;;
	esac
}

__dotfiles_agentbot_config="${XDG_CONFIG_HOME:-$HOME/.config}/agentbot"
# GitHub stores one token under its own name and it serves both the skill
# installs and the MCP entry, so the value is exported under the name the
# catalog references rather than duplicated on disk.
__dotfiles_export_agentbot_token \
	"$__dotfiles_agentbot_config/github.env" GITHUB_TOKEN GITHUB_MCP_TOKEN
__dotfiles_export_agentbot_token \
	"$__dotfiles_agentbot_config/gitlab.env" GITLAB_MCP_READ_TOKEN GITLAB_MCP_READ_TOKEN
unset __dotfiles_agentbot_config
unset -f __dotfiles_export_agentbot_token

if [ -f ~/.bash_aliases ]; then
	. ~/.bash_aliases
fi
