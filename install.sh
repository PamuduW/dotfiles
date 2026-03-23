#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------
# WSL/Debian/Ubuntu bootstrap (dotfiles + packages)
# - Installs baseline packages from packages/packages.txt
# - Installs GNU Stow + applies stow packages: bash, bin
# - Adds small compatibility links (e.g., fd -> fdfind)
# --------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"
PKG_FILE="$DOTFILES_DIR/packages/packages.txt"

# --- Logging: mirror all output to a timestamped log file ---
LOG_DIR="$DOTFILES_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d_%H-%M-%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Log file: $LOG_FILE"

# Read package list (ignoring blank lines and comments)
read_packages() {
  if [[ ! -f "$PKG_FILE" ]]; then
    echo "Error: package list not found at: $PKG_FILE" >&2
    exit 1
  fi
  # Strip comments and whitespace-only lines
  sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$PKG_FILE"
}

apt_install_packages() {
  local pkgs
  mapfile -t pkgs < <(read_packages)

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    echo "No packages listed in $PKG_FILE"
    return 0
  fi

  echo "Updating apt indexes..."
  sudo apt-get update -qq

  echo "Installing packages from $PKG_FILE ..."
  # Allow this to fail - some packages may not be in default repos
  # We have GitHub fallback installers for tools like lazygit/lazydocker
  sudo apt-get install -y "${pkgs[@]}" || true
}

install_lazygit_from_github() {
  # Fallback installer if lazygit isn't available in your apt repos.
  # Source: official lazygit GitHub releases.
  command -v curl >/dev/null 2>&1 || { echo "curl is required for lazygit fallback install." >&2; return 1; }
  command -v tar  >/dev/null 2>&1 || { echo "tar is required for lazygit fallback install." >&2; return 1; }

  echo "Installing lazygit from GitHub releases..."
  local ver
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -Po '"tag_name":\s*"v\K[^"]*' | head -n1)"
  [[ -n "$ver" ]] || { echo "Could not determine latest lazygit version." >&2; return 1; }

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  curl -fsSL -o "$tmp/lazygit.tar.gz" "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_x86_64.tar.gz"
  tar -C "$tmp" -xzf "$tmp/lazygit.tar.gz" lazygit
  sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  echo "  ✓ lazygit v${ver} installed successfully"
  trap - RETURN
}

install_lazydocker_from_github() {
  # Fallback installer if lazydocker isn't available in your apt repos.
  # Source: official lazydocker GitHub releases.
  command -v curl >/dev/null 2>&1 || { echo "curl is required for lazydocker fallback install." >&2; return 1; }
  command -v tar  >/dev/null 2>&1 || { echo "tar is required for lazydocker fallback install." >&2; return 1; }

  echo "Installing lazydocker from GitHub releases..."
  local ver
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name":\s*"v\K[^"]*' | head -n1)"
  [[ -n "$ver" ]] || { echo "Could not determine latest lazydocker version." >&2; return 1; }

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  curl -fsSL -o "$tmp/lazydocker.tar.gz" "https://github.com/jesseduffield/lazydocker/releases/download/v${ver}/lazydocker_${ver}_Linux_x86_64.tar.gz"
  tar -C "$tmp" -xzf "$tmp/lazydocker.tar.gz"

  if [[ ! -f "$tmp/lazydocker" ]]; then
    local binpath
    binpath="$(find "$tmp" -maxdepth 3 -type f -name lazydocker | head -n1 || true)"
    [[ -n "$binpath" ]] && cp "$binpath" "$tmp/lazydocker"
  fi

  sudo install -m 0755 "$tmp/lazydocker" /usr/local/bin/lazydocker
  echo "  ✓ lazydocker v${ver} installed successfully"
  trap - RETURN
}

install_node_via_nvm() {
  # Install Node.js via nvm (Node Version Manager)
  # Required by many modern CLI tools (e.g., Codex CLI)
  local NVM_DIR="${HOME}/.nvm"
  local NVM_MIN_NODE="22"

  # Skip if node >= 22 is already available
  if command -v node >/dev/null 2>&1; then
    local current_major
    current_major="$(node --version | grep -oP '^v\K[0-9]+')"
    if [[ "$current_major" -ge "$NVM_MIN_NODE" ]]; then
      echo "Node.js v$(node --version | tr -d 'v') already installed. Skipping nvm setup."
      return 0
    fi
  fi

  # Install nvm if not already present
  if [[ ! -d "$NVM_DIR" ]]; then
    echo "Installing nvm (Node Version Manager)..."
    # Strip Windows paths from PATH so nvm's installer doesn't invoke Windows npm via WSL interop
    local wsl_clean_path
    wsl_clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':' | sed 's/:$//')"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh \
      | PROFILE=/dev/null PATH="$wsl_clean_path" bash
  fi

  # Load nvm into the current shell
  export NVM_DIR
  # shellcheck source=/dev/null
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

  echo "Installing Node.js ${NVM_MIN_NODE} via nvm..."
  nvm install "$NVM_MIN_NODE"
  nvm alias default "$NVM_MIN_NODE"
  echo "  ✓ Node.js $(node --version) installed via nvm"
}

install_docker() {
  # Skip if Docker is already installed
  if command -v docker >/dev/null 2>&1; then
    echo "Docker already installed ($(docker --version)). Skipping."
  else
    echo "Installing Docker Engine from official repo..."

    # Prerequisites
    sudo apt-get install -y ca-certificates curl

    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the Docker apt repository (DEB822 format)
    # shellcheck disable=SC1091
    local codename
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<DOCKEREOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKEREOF

    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo "  ✓ Docker Engine installed"
  fi

  # Ensure current user can run docker without sudo
  if ! groups "$USER" | grep -qw docker; then
    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"
    echo "  ✓ Added $USER to docker group (log out/in or run 'newgrp docker' to activate)"
  fi
}

install_portainer() {
  if docker ps -a --format '{{.Names}}' | grep -qw portainer; then
    echo "Portainer container already exists. Skipping."
    return 0
  fi

  echo "Installing Portainer CE..."
  docker volume create portainer_data
  docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name portainer \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:sts
  docker stop portainer
  echo "  ✓ Portainer installed (stopped — use 'dpot' to start, 'dpotstop' to stop)"
}

post_install_fixes() {
  # Ensure ~/bin exists (for your stowed commands and convenience links)
  mkdir -p "$HOME/bin"

  # fd on Debian/Ubuntu is packaged as fd-find and the binary is 'fdfind'
  # Create a convenience link so you can use 'fd' like upstream docs.
  if command -v fdfind >/dev/null 2>&1 && [[ ! -e "$HOME/bin/fd" ]]; then
    ln -s "$(command -v fdfind)" "$HOME/bin/fd"
  fi
}

backup_existing_dotfiles() {
  local backup_dir="$DOTFILES_DIR/old_bash"
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local files_backed_up=0

  # Check if any files need backing up
  local needs_backup=false
  [[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]] && needs_backup=true
  [[ -f "$HOME/.bash_aliases" && ! -L "$HOME/.bash_aliases" ]] && needs_backup=true
  [[ -f "$HOME/bin/ex" && ! -L "$HOME/bin/ex" ]] && needs_backup=true

  if [[ "$needs_backup" == "false" ]]; then
    return 0
  fi

  # Create timestamped backup directory
  backup_dir="${backup_dir}_${timestamp}"
  mkdir -p "$backup_dir"
  echo "Backing up existing dotfiles to: $backup_dir"

  # Backup .bashrc if it exists and is not a symlink
  if [[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]]; then
    mv "$HOME/.bashrc" "$backup_dir/.bashrc"
    echo "  ✓ Backed up .bashrc"
    ((++files_backed_up))
  fi

  # Backup .bash_aliases if it exists and is not a symlink
  if [[ -f "$HOME/.bash_aliases" && ! -L "$HOME/.bash_aliases" ]]; then
    mv "$HOME/.bash_aliases" "$backup_dir/.bash_aliases"
    echo "  ✓ Backed up .bash_aliases"
    ((++files_backed_up))
  fi

  # Backup bin/ex if it exists and is not a symlink
  if [[ -f "$HOME/bin/ex" && ! -L "$HOME/bin/ex" ]]; then
    mkdir -p "$backup_dir/bin"
    mv "$HOME/bin/ex" "$backup_dir/bin/ex"
    echo "  ✓ Backed up bin/ex"
    ((++files_backed_up))
  fi

  if [[ $files_backed_up -gt 0 ]]; then
    echo "Backed up $files_backed_up file(s). Review them later in: $backup_dir"
  fi
}

stow_dotfiles() {
  if ! command -v stow >/dev/null 2>&1; then
    echo "Error: 'stow' is not installed. Check packages/packages.txt includes 'stow'." >&2
    exit 1
  fi

  echo "Applying stow packages: bash, bin"
  if stow --dir "$DOTFILES_DIR" --target "$HOME" bash bin; then
    echo "  ✓ Dotfiles stowed successfully"
  else
    echo "Error: stow failed with exit code $?. See output above." >&2
    exit 1
  fi
}

main() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Error: apt-get not found. This installer targets Debian/Ubuntu." >&2
    exit 1
  fi

  apt_install_packages

  # Optional fallbacks for tools that may not be in default repos on some distros.
  if ! command -v lazygit >/dev/null 2>&1; then
    echo "Note: 'lazygit' not found after apt install. Attempting GitHub fallback..."
    install_lazygit_from_github || echo "Warning: lazygit fallback install failed."
  fi

  if ! command -v lazydocker >/dev/null 2>&1; then
    echo "Note: 'lazydocker' not found after apt install. Attempting GitHub fallback..."
    install_lazydocker_from_github || echo "Warning: lazydocker fallback install failed."
  fi

  install_docker
  install_portainer
  install_node_via_nvm
  post_install_fixes
  backup_existing_dotfiles
  
  # Stow the dotfiles (create symlinks)
  stow_dotfiles

  echo ""
  echo "Done."
  echo "Open a new terminal, or run: source ~/.bashrc"
}

main "$@"
