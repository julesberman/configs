# Configs

Personal development config files and a small installer for setting up a new
macOS machine.

## Install

Run:

```sh
./install.sh
```

The script asks before installing anything. It can install Ghostty, Monaspace
fonts, and Starship with Homebrew, then copy the config files into place.
Existing files are backed up under `~/.config-backups/`.

The Homebrew installs performed by the script are:

```sh
brew install --cask ghostty
brew install --cask font-monaspace
brew install starship
```

## Manual Install

Copy files to these locations:

```text
.zshrc          -> ~/.zshrc
.gitconfig      -> ~/.gitconfig
starship.toml   -> ~/.config/starship.toml
config.ghostty  -> ~/Library/Application Support/com.mitchellh.ghostty/config.ghostty
```
