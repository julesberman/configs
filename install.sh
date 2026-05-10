#!/usr/bin/env bash
# Stop on errors, unset variables, and failed pipeline commands.
set -euo pipefail

# Resolve the repo path from this script's location, so it can be run from
# anywhere with `./install.sh` or `/path/to/install.sh`.
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Existing files are copied here before being overwritten.
backup_root="$HOME/.config-backups/$(date +%Y%m%d-%H%M%S)"

# Ask a yes/no question. The default is "yes" — empty input accepts.
confirm() {
  local prompt="$1"
  local answer

  read -r -p "$prompt [Y/n] " answer
  case "$answer" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

# Return success when a command is available on PATH.
have_command() {
  command -v "$1" >/dev/null 2>&1
}

# Copy an existing target file or directory into the backup folder before
# replacing it. This preserves the same path relative to $HOME.
backup_existing() {
  local target="$1"

  if [[ -e "$target" || -L "$target" ]]; then
    local relative="${target#$HOME/}"
    local backup_path="$backup_root/$relative"

    mkdir -p "$(dirname "$backup_path")"
    cp -pR "$target" "$backup_path"
    printf 'Backed up %s to %s\n' "$target" "$backup_path"
  fi
}

# Install one config file from the repo into its expected home-directory path.
# If the target already matches the repo copy, nothing is changed.
install_file() {
  local source="$1"
  local target="$2"
  local label="$3"

  if [[ ! -f "$source" ]]; then
    printf 'Skipping %s: missing %s\n' "$label" "$source"
    return
  fi

  printf '\n%s\n' "$label"
  printf '  source: %s\n' "$source"
  printf '  target: %s\n' "$target"

  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    printf 'Already installed; files match.\n'
    return
  fi

  if confirm "Install this config file?"; then
    backup_existing "$target"
    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"
    printf 'Installed %s\n' "$target"
  else
    printf 'Skipped %s\n' "$label"
  fi
}

# Install a Homebrew formula, such as a CLI tool. The command_name check lets
# us skip installation when the tool already exists, even if Homebrew did not
# install it originally.
brew_install_formula() {
  local formula="$1"
  local command_name="$2"
  local label="$3"

  printf '\n%s\n' "$label"

  if have_command "$command_name"; then
    printf 'Already available: %s\n' "$command_name"
    return
  fi

  if ! have_command brew; then
    printf 'Homebrew is required to install %s, but brew was not found.\n' "$label"
    return
  fi

  if confirm "Install $label with Homebrew?"; then
    brew install "$formula"
  else
    printf 'Skipped %s\n' "$label"
  fi
}

# Install a group of Homebrew formulas in a single prompt. `brew install` is
# idempotent, so already-installed formulas are skipped automatically.
brew_install_formulas() {
  local label="$1"
  shift
  local formulas=("$@")

  printf '\n%s\n' "$label"

  if ! have_command brew; then
    printf 'Homebrew is required to install %s, but brew was not found.\n' "$label"
    return
  fi

  if confirm "Install $label (${formulas[*]}) with Homebrew?"; then
    brew install "${formulas[@]}"
  else
    printf 'Skipped %s\n' "$label"
  fi
}

# Install a Homebrew cask, such as a macOS application. The app_path check is a
# simple way to avoid reinstalling apps that are already present.
brew_install_cask() {
  local cask="$1"
  local app_path="$2"
  local label="$3"

  printf '\n%s\n' "$label"

  if [[ -e "$app_path" ]]; then
    printf 'Already installed: %s\n' "$app_path"
    return
  fi

  if ! have_command brew; then
    printf 'Homebrew is required to install %s, but brew was not found.\n' "$label"
    return
  fi

  if confirm "Install $label with Homebrew?"; then
    brew install --cask "$cask"
  else
    printf 'Skipped %s\n' "$label"
  fi
}

# Return success when a Homebrew cask is already installed.
brew_cask_installed() {
  local cask="$1"

  have_command brew && brew list --cask "$cask" >/dev/null 2>&1
}

# Install a font cask. Fonts can be installed into different folders, so this
# checks both Homebrew's cask state and a file glob in the user's font folder.
brew_install_font_cask() {
  local cask="$1"
  local font_glob="$2"
  local label="$3"

  printf '\n%s\n' "$label"

  if brew_cask_installed "$cask"; then
    printf 'Already installed with Homebrew: %s\n' "$cask"
    return
  fi

  if compgen -G "$font_glob" >/dev/null; then
    printf 'Font files already found for %s\n' "$label"
    return
  fi

  if ! have_command brew; then
    printf 'Homebrew is required to install %s, but brew was not found.\n' "$label"
    return
  fi

  if confirm "Install $label with Homebrew?"; then
    brew install --cask "$cask"
  else
    printf 'Skipped %s\n' "$label"
  fi
}

main() {
  # Print enough context before prompting so it is clear what repo and backup
  # location this run will use.
  printf 'Config installer\n'
  printf 'Repo: %s\n' "$repo_dir"
  printf 'Backups will be written under: %s\n' "$backup_root"

  # The config-file copies are mostly portable, but the app/font installation
  # steps below use macOS Homebrew casks.
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '\nThis script is intended for macOS. File installs may still work, but app/font installs use Homebrew casks.\n'
  fi

  # Install the tools needed by the configs in this repo.
  brew_install_cask "ghostty" "/Applications/Ghostty.app" "Ghostty"
  brew_install_font_cask "font-monaspace" "$HOME/Library/Fonts/Monaspace*.otf" "Monaspace fonts"
  brew_install_formula "starship" "starship" "Starship prompt"
  brew_install_formulas "CLI utilities" fzf timg jq glow coreutils

  # Restore each tracked config file to the location where the corresponding
  # tool expects to find it.
  install_file "$repo_dir/.zshrc" "$HOME/.zshrc" "zsh config"
  install_file "$repo_dir/.gitconfig" "$HOME/.gitconfig" "Git config"
  install_file "$repo_dir/starship.toml" "$HOME/.config/starship.toml" "Starship config"
  install_file "$repo_dir/config.ghostty" "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" "Ghostty config"

  printf '\nDone.\n'
}

main "$@"
