# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091

# If not running interactively, don't do anything (avoid breaking scripts)
case "$-" in
  *i*) ;;
  *) return ;;
esac

# Ensure ~/bin is on PATH (for stowed commands like ~/bin/ex)
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"

# Optional: bash-completion (if available)
if [ -r /etc/bash_completion ]; then
  . /etc/bash_completion
fi

# Initialize zoxide (smart directory jumping) if installed
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

# --- dotfiles prompt (time + blank line + git symbols + exit code) ---

# Bright colors (PS1-safe when wrapped in \[ \])
c_reset="\[\e[0m\]"
c_time="\[\e[90m\]"     # gray
c_user="\[\e[32m\]"     # green
c_path="\[\e[34m\]"     # cyan
c_git="\[\e[33m\]"      # yellow
c_err="\[\e[31m\]"      # red

__dotfiles_git() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local branch staged dirty untracked symbols
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)"

  # ✚ = staged, ✱ = modified, ? = untracked
  git diff --cached --quiet >/dev/null 2>&1 || staged="✚"
  git diff        --quiet >/dev/null 2>&1 || dirty="✱"
  [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ] && untracked="?"

  symbols="${staged}${dirty}${untracked}"

  if [ -n "$symbols" ]; then
    printf ' %s(%s %s)%s' "$c_git" "$branch" "$symbols" "$c_reset"
  else
    printf ' %s(%s)%s' "$c_git" "$branch" "$c_reset"
  fi
}

__dotfiles_prompt() {
  local exit_code=$?   # MUST be first line
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

# Preserve any existing PROMPT_COMMAND; keep ours first so $? is correct.
if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare \-a'; then
  PROMPT_COMMAND=(__dotfiles_prompt_command "${PROMPT_COMMAND[@]}")
elif [ -n "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="__dotfiles_prompt_command; ${PROMPT_COMMAND}"
else
  PROMPT_COMMAND="__dotfiles_prompt_command"
fi

# --- nvm (Node Version Manager) ---
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi