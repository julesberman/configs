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

# ---------------------------------------------------------------------------
# General Aliases
# ---------------------------------------------------------------------------
# Clear the terminal.
alias c='clear'

# List files in useful formats.
alias ll='ls -lah'
alias la='ls -A'


# Common directory jumps.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Show human-readable disk usage for the current directory.
alias dud='du -d 1 -h'

# Search command history case-insensitively.
alias hgrep='history 1 | grep -i'

alias src='source ~/.zshrc; echo "Reloaded ~/.zshrc"'
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
# Launch Claude Code without permission prompts by default. Use `claude-p` to
# invoke the original binary with permission prompts intact.
alias claude='claude --dangerously-skip-permissions'
alias claude-p='command claude'
for _m in h:haiku s:sonnet o:opus; do
  for _e in l:low m:medium h:high x:xhigh xx:max; do
    alias "cc${_m%:*}${_e%:*}=claude --model ${_m#*:} --effort ${_e#*:}"
  done
done
unset _m _e

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

# ---------------------------------------------------------------------------
# fzf
# ---------------------------------------------------------------------------
# Enable fzf key bindings (Ctrl+R history, Ctrl+T files, Alt+C cd) and
# fuzzy completion. Requires fzf 0.48+.
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/julesberman/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/julesberman/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/julesberman/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/julesberman/Downloads/google-cloud-sdk/completion.zsh.inc'; fi


# ─────────────────────────────────────────────────────────────────────────────
# l() — interactive ls replacement with fuzzy picker, previews, and smart open
#
# Required:   fzf  (>= 0.27 for --expect; tested on 0.44)
# Optional:   timg, jq, glow, column (bsdmainutils on Linux), GNU ls (coreutils on macOS)
#
# Install:
#   Ubuntu/Debian: sudo apt install fzf timg jq glow bsdmainutils
#   macOS:         brew install fzf timg jq glow coreutils
#
# Keys:  ↑↓ move · → into dir · ← parent · Enter open · Esc cancel
#
# Cross-shell: works in both bash and zsh. The preview helper is embedded as a
# POSIX shell string passed to fzf, so no shell-specific function-export tricks.
# ─────────────────────────────────────────────────────────────────────────────

l() {
    # In zsh, `local x` (no =value) prints x's existing value unless
    # TYPESET_SILENT is set — which dumps every local on every loop iteration.
    # LOCAL_OPTIONS scopes the setting to this function only.
    [ -n "$ZSH_VERSION" ] && setopt local_options typeset_silent

    # Prefer GNU ls (gls from coreutils) on macOS for --group-directories-first
    # and --color=always; fall back to plain ls elsewhere.
    local _ls=ls
    command -v gls >/dev/null 2>&1 && _ls=gls

    # POSIX preview script. fzf invokes this as: sh -c "<script>" _ <path>
    # Detect gls inside the subshell too, since the parent's $_ls is not exported.
    local _l_preview_script='
        LS=ls
        command -v gls >/dev/null 2>&1 && LS=gls
        p="$1"
        [ -z "$p" ] && exit 0
        if [ -d "$p" ]; then
            "$LS" -la --color=always -- "$p" 2>/dev/null
        elif [ -f "$p" ]; then
            if file --mime "$p" 2>/dev/null | grep -q "charset=binary"; then
                basename -- "$p"
                file -- "$p" 2>/dev/null
                echo "size: $(du -h -- "$p" | cut -f1)"
            else
                head -200 -- "$p" 2>/dev/null
            fi
        else
            echo "(not found: $p)"
        fi
    '

    local cur="$PWD"

    while true; do
        # Two-column TSV listing:
        #   col 1 = absolute path (clean, used by preview + outer shell)
        #   col 2 = ANSI-colored display name (rendered by fzf via --ansi)
        local listing
        listing=$(
            printf '%s\t.\n'  "$cur"
            printf '%s\t..\n' "$(cd "$cur/.." 2>/dev/null && pwd)"
            paste \
                <("$_ls" -1 --group-directories-first -- "$cur" 2>/dev/null | sed "s|^|$cur/|") \
                <("$_ls" -1 --color=always --group-directories-first -- "$cur" 2>/dev/null)
        )

        # Note: do NOT name a local "path" — zsh ties `path` to `PATH`, so
        # `local path` empties PATH for the function and breaks command lookup.
        local result key line entry target
        result=$(
            printf '%s\n' "$listing" \
            | fzf --ansi \
                  --delimiter=$'\t' \
                  --with-nth=2 \
                  --height=50% \
                  --reverse \
                  --border=rounded \
                  --prompt="${cur/#$HOME/~} ❯ " \
                  --pointer='▶' \
                  --marker='✓' \
                  --preview="sh -c '$_l_preview_script' _ {1}" \
                  --preview-window=right:50%:wrap \
                  --expect=right,left \
                  --color='fg:#c0caf5,bg:-1,hl:#7aa2f7,fg+:#c0caf5,bg+:#283457,hl+:#7dcfff,prompt:#7aa2f7,pointer:#f7768e,marker:#9ece6a,border:#414868'
        )
        [ $? -ne 0 ] && return

        key=$(printf  '%s\n' "$result" | sed -n '1p')
        line=$(printf '%s\n' "$result" | sed -n '2p')
        [ -z "$line" ] && return

        target=$(printf '%s' "$line" | cut -f1)
        entry=$(printf  '%s' "$line" | cut -f2)

        case "$key" in
            right)
                if [ "$entry" = "." ]; then
                    :
                elif [ "$entry" = ".." ] || [ -d "$target" ]; then
                    cur="$target"
                fi
                ;;
            left)
                cur=$(cd "$cur/.." && pwd)
                ;;
            "")
                if [ "$entry" = "." ]; then
                    cd "$cur" && return
                elif [ "$entry" = ".." ] || [ -d "$target" ]; then
                    cd "$target" && return
                else
                    cd "$cur"
                    case "$entry" in
                        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.pdf)
                            timg "$entry" 2>/dev/null || ${EDITOR:-vim} "$entry" ;;
                        *.csv|*.tsv)
                            column -s, -t -- "$entry" 2>/dev/null | less -S || ${EDITOR:-vim} "$entry" ;;
                        *.json)
                            jq -C . -- "$entry" 2>/dev/null | less -R || ${EDITOR:-vim} "$entry" ;;
                        *.md)
                            glow -p -- "$entry" 2>/dev/null || ${EDITOR:-vim} "$entry" ;;
                        *.parquet|*.npy|*.npz|*.pt|*.pth|*.ckpt|*.safetensors)
                            echo "$entry — binary ML file ($(du -h -- "$entry" | cut -f1))" ;;
                        *.zip)
                            unzip -l -- "$entry" 2>/dev/null | less || ${EDITOR:-vim} "$entry" ;;
                        *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tar.xz)
                            tar tvf -- "$entry" 2>/dev/null | less || ${EDITOR:-vim} "$entry" ;;
                        *)
                            ${EDITOR:-vim} "$entry" ;;
                    esac
                    return
                fi
                ;;
        esac
    done
}
