# ~/.zshrc
# Global interactive shell config for zsh.

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
# Keep a large command history across terminal sessions.
export HISTSIZE=100000
export SAVEHIST=200000
export HISTFILE="${HISTFILE:-$HOME/.zsh_history}"

# Make history more useful:
# - share commands across open shells
# - append instead of rewriting the history file
# - ignore duplicate commands and commands that start with a space
setopt share_history
setopt append_history
setopt inc_append_history
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt hist_ignore_space

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# Prefer user-installed binaries and Homebrew tools before system defaults.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

# Remove duplicate PATH entries while preserving order.
typeset -U path PATH

# ---------------------------------------------------------------------------
# Editor Defaults
# ---------------------------------------------------------------------------
# SVN still reads SVN_EDITOR. Keeping this explicit avoids editor surprises.
export SVN_EDITOR=vim

# ---------------------------------------------------------------------------
# Zsh Behavior
# ---------------------------------------------------------------------------
# Initialize completion if zsh's completion system is available.
autoload -Uz compinit
compinit

# Quality-of-life shell behavior:
# - auto_cd lets you type a directory name to cd into it
# - correct_all offers spelling corrections for commands and paths
# - interactive_comments lets comments work in pasted interactive commands
setopt auto_cd
setopt correct_all
setopt interactive_comments

# ---------------------------------------------------------------------------
# General Aliases
# ---------------------------------------------------------------------------
# Clear the terminal.
alias c='clear'

# List files in useful formats.
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# Common directory jumps.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Show human-readable disk usage for the current directory.
alias dud='du -d 1 -h'

# Search command history case-insensitively.
alias hgrep='history 1 | grep -i'

# ---------------------------------------------------------------------------
# Git Aliases
# ---------------------------------------------------------------------------
# Short aliases for common Git workflows.
alias gs='git status --short'
alias gst='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcam='git commit -am'
alias gp='git push'
alias gpl='git pull --ff-only'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --decorate --graph -20'
alias gb='git branch'
alias gco='git checkout'

# ---------------------------------------------------------------------------
# AI / Coding Tools
# ---------------------------------------------------------------------------
# Launch Claude Code without permission prompts when you intentionally want
# that mode. Use with care because it grants broader file/command access.
alias claude-dsp='claude --dangerously-skip-permissions'

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------
# Activate a virtual environment. Defaults to .venv when no path is provided.
aa() {
  local venv_path="${1:-.venv}"

  if [[ -d "$venv_path/bin" ]]; then
    source "$venv_path/bin/activate"
  else
    printf 'Error: virtual environment not found at %s\n' "$venv_path"
    printf 'Usage: aa [path_to_venv]\n'
    return 1
  fi
}

# Create a virtual environment and activate it. Defaults to .venv.
mkvenv() {
  local venv_path="${1:-.venv}"

  python3 -m venv "$venv_path" && source "$venv_path/bin/activate"
}

# Make a directory and cd into it.
mkcd() {
  if [[ -z "${1:-}" ]]; then
    printf 'Usage: mkcd <directory>\n'
    return 1
  fi

  mkdir -p "$1" && cd "$1"
}

# Jump to the root of the current Git repo.
croot() {
  local root

  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'Not inside a Git repository.\n'
    return 1
  }

  cd "$root"
}

# Kill Python processes only after an explicit confirmation.
killpy() {
  local pattern='python|python3'

  printf 'Matching Python processes:\n'
  pgrep -af "$pattern" || {
    printf 'No matching Python processes found.\n'
    return 0
  }

  read -r -p 'Kill these Python processes? [y/N] ' answer
  case "$answer" in
    [yY]|[yY][eE][sS]) pkill -f "$pattern" ;;
    *) printf 'Skipped.\n' ;;
  esac
}

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------
# Starship prompt. The command check keeps new machines from erroring before
# Starship has been installed.
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
