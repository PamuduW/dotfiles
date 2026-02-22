#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"

# Ensure the helper script is executable in the repo so the symlink is executable too
chmod +x "$DOTFILES_DIR/bin/bin/ex" || true
chmod +x "$DOTFILES_DIR/install.sh" || true

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y stow git bash-completion
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "Error: 'stow' is not installed (and apt-get install didn't succeed)."
  exit 1
fi

# Stow into $HOME explicitly, regardless of where this repo lives.
stow --dir "$DOTFILES_DIR" --target "$HOME" bash bin

echo "Done."
echo "Open a new terminal, or run: source ~/.bashrc"