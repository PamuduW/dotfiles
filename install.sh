#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------
# WSL/Debian/Ubuntu interactive bootstrap
# - Prompts for git identity
# - Toggle menu to select components
# - Shows execution plan for review
# - Installs only selected components
# --------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"
PKG_FILE="$DOTFILES_DIR/packages/packages.txt"

# --- Logging: mirror all output to a timestamped log file ---
LOG_DIR="$DOTFILES_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d_%H-%M-%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# Component registry
# ============================================================
COMP_KEYS=(
  git_identity
  system_packages
  python
  go
  nodejs
  docker
  portainer
  lazygit
  lazydocker
  cursor_cli
  codex_cli
  claude_cli
  monaspace_fonts
  ssh_key
  dotfiles
  wsl_conf
  git_credential
)

COMP_LABELS=(
  "Git identity (global user.name / email)"
  "System packages"
  "Python (python3, pip, venv)"
  "Go (golang-go)"
  "Node.js 22 (nvm)"
  "Docker Engine"
  "Portainer CE"
  "lazygit (git TUI)"
  "lazydocker (docker TUI)"
  "Cursor CLI"
  "Codex CLI"
  "Claude CLI"
  "Monaspace fonts (Nerd Fonts)"
  "Generate SSH key"
  "Apply dotfiles (stow)"
  "WSL config (systemd, clean PATH)"
  "Git credential helper (Windows)"
)

# Dependency: index of required component, -1 = none
#              gid sys py  go  njs doc por lg  ld  cur cdx cla mon ssh dot wsl gcr
COMP_DEPS=(    -1  -1  -1  -1  -1  -1  5   -1  5   -1  4   -1  -1  -1  1   -1  -1 )

declare -A COMP_ON
for _key in "${COMP_KEYS[@]}"; do COMP_ON["$_key"]=1; done

# Auto-detect conditional git includes (multi-identity setup) and default OFF
if git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
  COMP_ON[git_identity]=0
fi

# Git identity (populated by prompt)
SETUP_GIT_NAME=""
SETUP_GIT_EMAIL=""

# Status message from toggle_component (avoids echo which breaks in-place redraw)
TOGGLE_MSG=""

# ============================================================
# packages.txt parser
# ============================================================

read_packages_by_tags() {
  # Usage: read_packages_by_tags tag1 tag2 ...
  # Outputs package names under matching @tag sections.
  [[ -f "$PKG_FILE" ]] || { echo "Error: $PKG_FILE not found" >&2; return 1; }

  local -A wanted
  local tag
  for tag in "$@"; do wanted["$tag"]=1; done

  local current_tag="" active=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^#[[:space:]]*@([a-zA-Z_]+) ]]; then
      current_tag="${BASH_REMATCH[1]}"
      [[ -n "${wanted[$current_tag]+_}" ]] && active=1 || active=0
      continue
    fi
    [[ "$active" -eq 0 ]] && continue
    local pkg="${line%%#*}"
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"
    pkg="${pkg%"${pkg##*[![:space:]]}"}"
    [[ -n "$pkg" ]] && echo "$pkg"
  done < "$PKG_FILE"
}

# ============================================================
# Interactive UI
# ============================================================

is_on() { [[ "${COMP_ON[$1]}" -eq 1 ]]; }

prompt_git_identity() {
  local current_name current_email
  current_name="$(git config --global user.name 2>/dev/null || true)"
  current_email="$(git config --global user.email 2>/dev/null || true)"

  echo ""
  echo "Git identity (press Enter to keep default):"
  read -rp "  Name [${current_name:-Pamudu Wijesingha}]: " SETUP_GIT_NAME < /dev/tty
  SETUP_GIT_NAME="${SETUP_GIT_NAME:-${current_name:-Pamudu Wijesingha}}"

  read -rp "  Email [${current_email:-pamuduwijesingha2k20@gmail.com}]: " SETUP_GIT_EMAIL < /dev/tty
  SETUP_GIT_EMAIL="${SETUP_GIT_EMAIL:-${current_email:-pamuduwijesingha2k20@gmail.com}}"
}

toggle_component() {
  local idx="$1"
  local key="${COMP_KEYS[$idx]}"
  TOGGLE_MSG=""

  if [[ "${COMP_ON[$key]}" -eq 1 ]]; then
    COMP_ON["$key"]=0
    local i
    for i in "${!COMP_DEPS[@]}"; do
      if [[ "${COMP_DEPS[$i]}" -eq "$idx" ]]; then
        local dep_key="${COMP_KEYS[$i]}"
        if [[ "${COMP_ON[$dep_key]}" -eq 1 ]]; then
          COMP_ON["$dep_key"]=0
          TOGGLE_MSG+="auto-disabled: ${COMP_LABELS[$i]}  "
        fi
      fi
    done
  else
    COMP_ON["$key"]=1
    local req="${COMP_DEPS[$idx]}"
    if [[ "$req" -ne -1 ]]; then
      local req_key="${COMP_KEYS[$req]}"
      if [[ "${COMP_ON[$req_key]}" -eq 0 ]]; then
        COMP_ON["$req_key"]=1
        TOGGLE_MSG+="auto-enabled: ${COMP_LABELS[$req]}"
      fi
    fi
  fi
}

_comp_description() {
  local idx=$1
  case "${COMP_KEYS[$idx]}" in
    git_identity)
      echo "Set global git user.name and user.email."
      echo "Skip this if you use includeIf for per-directory identities."
      ;;
    system_packages)
      local pkgs
      pkgs="$(read_packages_by_tags core cli system | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
      echo "Installs via apt: ${pkgs}"
      ;;
    python)
      echo "Installs python3, pip, and venv via apt."
      ;;
    go)
      echo "Installs golang-go via apt."
      ;;
    nodejs)
      echo "Installs Node.js v22 via nvm (Node Version Manager)."
      echo "Also provides npm for global packages like Codex CLI."
      ;;
    docker)
      echo "Installs Docker Engine CE from the official Docker apt repo."
      echo "Adds your user to the docker group for rootless access."
      ;;
    portainer)
      echo "Deploys the Portainer CE container (web UI for Docker)."
      echo "Container is stopped by default — start with 'dpot'."
      ;;
    lazygit)
      echo "Terminal UI for git. Downloaded from GitHub releases."
      ;;
    lazydocker)
      echo "Terminal UI for Docker. Downloaded from GitHub releases."
      ;;
    cursor_cli)
      echo "Installs Cursor editor CLI from cursor.com."
      echo "Update later with 'update-cursor' or 'update-all'."
      ;;
    codex_cli)
      echo "Installs OpenAI Codex CLI via npm (requires Node.js)."
      echo "Update later with 'update-codex' or 'update-all'."
      ;;
    claude_cli)
      echo "Installs Anthropic Claude CLI from claude.ai."
      echo "Update later with 'update-claude' or 'update-all'."
      ;;
    monaspace_fonts)
      echo "Downloads GitHub Monaspace Nerd Fonts to ~/.local/share/fonts/."
      echo "Includes all 5 variants with Powerline glyphs and dev icons."
      ;;
    ssh_key)
      echo "Generates an ed25519 SSH key and adds it to ssh-agent."
      echo "Saves public key and GitHub setup steps to ~/.ssh/github-setup.txt."
      ;;
    dotfiles)
      echo "Uses GNU Stow to symlink bash, bin, and readline configs into \$HOME."
      echo "Backs up existing .bashrc, .bash_aliases, .inputrc first."
      ;;
    wsl_conf)
      echo "Sets systemd=true and appendWindowsPath=false in /etc/wsl.conf."
      echo "Requires 'wsl --shutdown' from Windows to take effect."
      ;;
    git_credential)
      echo "Configures git to use Windows Git Credential Manager for HTTPS auth."
      echo "Searches common install paths for git-credential-manager.exe."
      ;;
  esac
}

# Fixed number of description lines rendered (padded/truncated to this)
_DESC_LINES=2

_draw_menu() {
  local cur=$1 status=$2
  local count="${#COMP_KEYS[@]}"
  local i key mark note

  printf "\n  \e[1m=== Select Components ===\e[0m\n"
  printf "  ↑/↓ navigate   Space toggle   a all   n none   Enter confirm\n\n"

  for i in "${!COMP_KEYS[@]}"; do
    key="${COMP_KEYS[$i]}"
    mark="x"; [[ "${COMP_ON[$key]}" -eq 0 ]] && mark=" "
    note=""
    [[ "${COMP_DEPS[$i]}" -ne -1 ]] && note="  (requires: ${COMP_LABELS[${COMP_DEPS[$i]}]})"

    if [[ $i -eq $cur ]]; then
      printf "\e[7m  %2d. [%s] %s%s \e[0m\e[K\n" "$((i + 1))" "$mark" "${COMP_LABELS[$i]}" "$note"
    else
      printf "  %2d. [%s] %s%s\e[K\n" "$((i + 1))" "$mark" "${COMP_LABELS[$i]}" "$note"
    fi
  done

  # Status line (toggle feedback)
  if [[ -n "$status" ]]; then
    printf "\n  \e[33m%s\e[0m\e[K\n" "$status"
  else
    printf "\n\e[K\n"
  fi

  # Description area for the highlighted component
  local desc_lines=()
  mapfile -t desc_lines < <(_comp_description "$cur")
  for i in $(seq 0 $((_DESC_LINES - 1))); do
    if [[ $i -lt ${#desc_lines[@]} ]]; then
      printf "  \e[36m%s\e[0m\e[K\n" "${desc_lines[$i]}"
    else
      printf "\e[K\n"
    fi
  done
}

component_menu() {
  local count="${#COMP_KEYS[@]}"
  local cursor=0
  local status_msg=""
  # 4 header + count items + 2 status + _DESC_LINES description
  local menu_lines=$((count + 6 + _DESC_LINES))

  tput civis 2>/dev/null || true
  _draw_menu 0 ""

  while true; do
    local key seq
    IFS= read -rsn1 key < /dev/tty

    case "$key" in
      $'\e')
        IFS= read -rsn2 -t 0.1 seq < /dev/tty
        case "$seq" in
          '[A') [[ $cursor -gt 0 ]] && cursor=$((cursor - 1)) ;;
          '[B') [[ $cursor -lt $((count - 1)) ]] && cursor=$((cursor + 1)) ;;
        esac
        status_msg=""
        ;;
      ' ')
        toggle_component "$cursor"
        status_msg="$TOGGLE_MSG"
        ;;
      '')
        break
        ;;
      a|A)
        for k in "${COMP_KEYS[@]}"; do COMP_ON["$k"]=1; done
        status_msg="All components enabled"
        ;;
      n|N)
        for k in "${COMP_KEYS[@]}"; do COMP_ON["$k"]=0; done
        status_msg="All components disabled"
        ;;
      *)
        continue
        ;;
    esac

    printf "\e[%dA" "$menu_lines"
    _draw_menu "$cursor" "$status_msg"
  done

  tput cnorm 2>/dev/null || true
}

show_plan() {
  echo ""
  echo "=== Execution Plan ==="
  echo ""

  if is_on git_identity; then
    printf "  %-18s: %s <%s>\n" "Git identity" "$SETUP_GIT_NAME" "$SETUP_GIT_EMAIL"
  elif git config --global --list 2>/dev/null | grep -q '^includeif\.'; then
    printf "  %-18s: skip (conditional includes detected)\n" "Git identity"
  else
    printf "  %-18s: skip\n" "Git identity"
  fi

  if is_on system_packages; then
    local pkg_count
    pkg_count="$(read_packages_by_tags core cli system | wc -l)"
    printf "  %-18s: %d packages (@core @cli @system)\n" "System packages" "$pkg_count"
  else
    printf "  %-18s: skip\n" "System packages"
  fi

  if is_on python; then
    printf "  %-18s: python3, pip, venv\n" "Python"
  else
    printf "  %-18s: skip\n" "Python"
  fi

  if is_on go; then
    printf "  %-18s: golang-go\n" "Go"
  else
    printf "  %-18s: skip\n" "Go"
  fi

  if is_on nodejs; then
    printf "  %-18s: v22 via nvm\n" "Node.js"
  else
    printf "  %-18s: skip\n" "Node.js"
  fi

  if is_on docker; then
    printf "  %-18s: Docker Engine CE + docker group\n" "Docker"
  else
    printf "  %-18s: skip\n" "Docker"
  fi

  if is_on portainer; then
    printf "  %-18s: Portainer CE (stopped by default)\n" "Portainer"
  else
    printf "  %-18s: skip\n" "Portainer"
  fi

  if is_on lazygit; then
    printf "  %-18s: latest from GitHub\n" "lazygit"
  else
    printf "  %-18s: skip\n" "lazygit"
  fi

  if is_on lazydocker; then
    printf "  %-18s: latest from GitHub\n" "lazydocker"
  else
    printf "  %-18s: skip\n" "lazydocker"
  fi

  if is_on cursor_cli; then
    printf "  %-18s: cursor.com installer\n" "Cursor CLI"
  else
    printf "  %-18s: skip\n" "Cursor CLI"
  fi

  if is_on codex_cli; then
    printf "  %-18s: npm @openai/codex\n" "Codex CLI"
  else
    printf "  %-18s: skip\n" "Codex CLI"
  fi

  if is_on claude_cli; then
    printf "  %-18s: claude.ai installer\n" "Claude CLI"
  else
    printf "  %-18s: skip\n" "Claude CLI"
  fi

  if is_on monaspace_fonts; then
    printf "  %-18s: Monaspace Nerd Fonts -> ~/.local/share/fonts/\n" "Monaspace fonts"
  else
    printf "  %-18s: skip\n" "Monaspace fonts"
  fi

  if is_on ssh_key; then
    if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
      printf "  %-18s: already exists, will skip\n" "SSH key"
    else
      printf "  %-18s: generate ed25519 -> ~/.ssh/github-setup.txt\n" "SSH key"
    fi
  else
    printf "  %-18s: skip\n" "SSH key"
  fi

  if is_on dotfiles; then
    printf "  %-18s: stow bash, bin, readline\n" "Dotfiles"
  else
    printf "  %-18s: skip\n" "Dotfiles"
  fi

  if is_on wsl_conf; then
    printf "  %-18s: systemd=true, appendWindowsPath=false\n" "WSL config"
  else
    printf "  %-18s: skip\n" "WSL config"
  fi

  if is_on git_credential; then
    printf "  %-18s: Windows Credential Manager\n" "Git credential"
  else
    printf "  %-18s: skip\n" "Git credential"
  fi

  echo ""
}

confirm_loop() {
  local need_git_prompt=true
  while true; do
    if is_on git_identity && [[ "$need_git_prompt" == "true" ]]; then
      prompt_git_identity
      need_git_prompt=false
    fi
    show_plan
    read -rp "  [c]onfirm  [e]dit  [q]uit: " answer < /dev/tty
    case "$answer" in
      c|C) return 0 ;;
      e|E) component_menu; need_git_prompt=true ;;
      q|Q) echo "Aborted."; exit 0 ;;
      *)   echo "    Invalid choice." ;;
    esac
  done
}

# ============================================================
# Installer functions
# ============================================================

apt_install_packages() {
  local pkgs
  mapfile -t pkgs < <(read_packages_by_tags "$@")
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    echo "  No packages for tags: $*"
    return 0
  fi
  echo "Installing packages ($*)..."
  sudo apt-get install -y "${pkgs[@]}" || true
}

install_lazygit_from_github() {
  command -v curl >/dev/null 2>&1 || { echo "  curl required for lazygit install." >&2; return 1; }
  command -v tar  >/dev/null 2>&1 || { echo "  tar required for lazygit install." >&2; return 1; }

  echo "Installing lazygit from GitHub releases..."
  local ver tmp
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
    | grep -Po '"tag_name":\s*"v\K[^"]*' | head -n1)"
  [[ -n "$ver" ]] || { echo "  Could not determine lazygit version." >&2; return 1; }

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/lazygit.tar.gz" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_x86_64.tar.gz"
  tar -C "$tmp" -xzf "$tmp/lazygit.tar.gz" lazygit
  sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmp"
  trap - RETURN
  echo "  ✓ lazygit v${ver} installed"
}

install_lazydocker_from_github() {
  command -v curl >/dev/null 2>&1 || { echo "  curl required for lazydocker install." >&2; return 1; }
  command -v tar  >/dev/null 2>&1 || { echo "  tar required for lazydocker install." >&2; return 1; }

  echo "Installing lazydocker from GitHub releases..."
  local ver tmp
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest \
    | grep -Po '"tag_name":\s*"v\K[^"]*' | head -n1)"
  [[ -n "$ver" ]] || { echo "  Could not determine lazydocker version." >&2; return 1; }

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/lazydocker.tar.gz" \
    "https://github.com/jesseduffield/lazydocker/releases/download/v${ver}/lazydocker_${ver}_Linux_x86_64.tar.gz"
  tar -C "$tmp" -xzf "$tmp/lazydocker.tar.gz"

  if [[ ! -f "$tmp/lazydocker" ]]; then
    local binpath
    binpath="$(find "$tmp" -maxdepth 3 -type f -name lazydocker | head -n1 || true)"
    [[ -n "$binpath" ]] && cp "$binpath" "$tmp/lazydocker"
  fi

  sudo install -m 0755 "$tmp/lazydocker" /usr/local/bin/lazydocker
  rm -rf "$tmp"
  trap - RETURN
  echo "  ✓ lazydocker v${ver} installed"
}

install_node_via_nvm() {
  local NVM_DIR="${HOME}/.nvm"
  local NVM_MIN_NODE="22"

  if command -v node >/dev/null 2>&1; then
    local current_major
    current_major="$(node --version | grep -oP '^v\K[0-9]+')"
    if [[ "$current_major" -ge "$NVM_MIN_NODE" ]]; then
      echo "  Node.js v$(node --version | tr -d 'v') already installed. Skipping."
      return 0
    fi
  fi

  if [[ ! -d "$NVM_DIR" ]]; then
    echo "Installing nvm (Node Version Manager)..."
    local wsl_clean_path
    wsl_clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':' | sed 's/:$//')"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh \
      | PROFILE=/dev/null PATH="$wsl_clean_path" bash
  fi

  export NVM_DIR
  # shellcheck source=/dev/null
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

  echo "Installing Node.js ${NVM_MIN_NODE} via nvm..."
  nvm install "$NVM_MIN_NODE"
  nvm alias default "$NVM_MIN_NODE"
  echo "  ✓ Node.js $(node --version) installed via nvm"
}

# Run docker with sudo fallback if user isn't in the docker group yet
run_docker() {
  if groups 2>/dev/null | grep -qw docker; then
    command docker "$@"
  else
    sudo docker "$@"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "  Docker already installed ($(docker --version 2>/dev/null || echo 'unknown')). Skipping."
  else
    echo "Installing Docker Engine from official repo..."
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    local codename
    # shellcheck disable=SC1091
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

  if ! groups "$USER" | grep -qw docker; then
    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"
    echo "  ✓ Added $USER to docker group (log out/in or 'newgrp docker' to activate)"
  fi
}

install_portainer() {
  if run_docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qw portainer; then
    echo "  Portainer container already exists. Skipping."
    return 0
  fi

  echo "Installing Portainer CE..."
  run_docker volume create portainer_data
  run_docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name portainer \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:sts
  run_docker stop portainer
  echo "  ✓ Portainer installed (stopped — use 'dpot' to start, 'dpotstop' to stop)"
}

apply_git_config() {
  git config --global user.name "$SETUP_GIT_NAME"
  git config --global user.email "$SETUP_GIT_EMAIL"
  echo "  ✓ Git configured: $SETUP_GIT_NAME <$SETUP_GIT_EMAIL>"
}

generate_ssh_key() {
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    echo "  SSH key ~/.ssh/id_ed25519 already exists. Skipping."
    return 0
  fi

  echo "Generating SSH key (ed25519)..."
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$SETUP_GIT_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null

  local pub_key
  pub_key="$(cat "$HOME/.ssh/id_ed25519.pub")"

  cat > "$HOME/.ssh/github-setup.txt" <<EOF
SSH Key Setup Notes
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Public key:
  ${pub_key}

Next steps:
  1. Copy the public key above
  2. Go to https://github.com/settings/keys
  3. Click "New SSH key"
  4. Paste the key, give it a title (e.g. "WSL - $(hostname)")
  5. Test with: ssh -T git@github.com
EOF

  echo "  ✓ SSH key generated"
  echo "  ✓ Details saved to ~/.ssh/github-setup.txt"
}

configure_wsl() {
  local conf="/etc/wsl.conf"
  local needs_systemd=true
  local needs_interop=true

  if [[ -f "$conf" ]]; then
    grep -q 'systemd\s*=\s*true' "$conf" 2>/dev/null && needs_systemd=false
    grep -q 'appendWindowsPath\s*=\s*false' "$conf" 2>/dev/null && needs_interop=false
  fi

  if [[ "$needs_systemd" == "false" && "$needs_interop" == "false" ]]; then
    echo "  /etc/wsl.conf already configured. Skipping."
    return 0
  fi

  echo "Configuring /etc/wsl.conf..."
  [[ -f "$conf" ]] && sudo cp "$conf" "${conf}.bak"

  if [[ "$needs_systemd" == "true" ]]; then
    if [[ -f "$conf" ]] && grep -qP '^\s*systemd\s*=' "$conf"; then
      sudo sed -i 's/^\(\s*\)systemd\s*=.*/\1systemd=true/' "$conf"
    elif [[ -f "$conf" ]] && grep -q '^\[boot\]' "$conf"; then
      sudo sed -i '/^\[boot\]/a systemd=true' "$conf"
    else
      printf '\n[boot]\nsystemd=true\n' | sudo tee -a "$conf" >/dev/null
    fi
  fi

  if [[ "$needs_interop" == "true" ]]; then
    if [[ -f "$conf" ]] && grep -qP '^\s*appendWindowsPath\s*=' "$conf"; then
      sudo sed -i 's/^\(\s*\)appendWindowsPath\s*=.*/\1appendWindowsPath=false/' "$conf"
    elif [[ -f "$conf" ]] && grep -q '^\[interop\]' "$conf"; then
      sudo sed -i '/^\[interop\]/a appendWindowsPath=false' "$conf"
    else
      printf '\n[interop]\nappendWindowsPath=false\n' | sudo tee -a "$conf" >/dev/null
    fi
  fi

  echo "  ✓ WSL config updated (restart WSL to apply: wsl --shutdown)"
}

configure_git_credential_helper() {
  local gcm_path=""
  local -a candidates=(
    "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
    "/mnt/c/Program Files (x86)/Git/mingw64/bin/git-credential-manager.exe"
    "/mnt/c/Program Files/Git/mingw64/libexec/git-core/git-credential-manager.exe"
  )

  for path in "${candidates[@]}"; do
    if [[ -f "$path" ]]; then
      gcm_path="$path"
      break
    fi
  done

  if [[ -n "$gcm_path" ]]; then
    git config --global credential.helper "$gcm_path"
    echo "  ✓ Git credential helper: $gcm_path"
  else
    echo "  Warning: Windows Git Credential Manager not found."
    echo "    Install Git for Windows, then re-run or set manually."
  fi
}

install_cursor_cli() {
  if command -v cursor >/dev/null 2>&1; then
    echo "  Cursor CLI already installed. Skipping."
    return 0
  fi
  echo "Installing Cursor CLI..."
  curl -fsSL https://cursor.com/install | bash
  echo "  ✓ Cursor CLI installed"
}

install_codex_cli() {
  if command -v codex >/dev/null 2>&1; then
    echo "  Codex CLI already installed. Skipping."
    return 0
  fi
  command -v npm >/dev/null 2>&1 || { echo "  npm not found. Install Node.js first." >&2; return 1; }
  echo "Installing Codex CLI..."
  npm i -g @openai/codex
  echo "  ✓ Codex CLI installed"
}

install_claude_cli() {
  if command -v claude >/dev/null 2>&1; then
    echo "  Claude CLI already installed. Skipping."
    return 0
  fi
  echo "Installing Claude CLI..."
  curl -fsSL https://claude.ai/install.sh | bash
  echo "  ✓ Claude CLI installed"
}

install_monaspace_fonts() {
  local font_dir="$HOME/.local/share/fonts/monaspace"

  if [[ -d "$font_dir" ]] && compgen -G "$font_dir/*.otf" >/dev/null 2>&1; then
    echo "  Monaspace fonts already installed in $font_dir. Skipping."
    return 0
  fi

  command -v curl >/dev/null 2>&1 || { echo "  curl required for Monaspace install." >&2; return 1; }
  command -v unzip >/dev/null 2>&1 || sudo apt-get install -y unzip

  echo "Installing Monaspace Nerd Fonts from GitHub..."
  local ver tmp
  ver="$(curl -fsSL https://api.github.com/repos/githubnext/monaspace/releases/latest \
    | grep -Po '"tag_name":\s*"\K[^"]*' | head -n1)"
  [[ -n "$ver" ]] || { echo "  Could not determine Monaspace version." >&2; return 1; }

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/monaspace-nerdfonts.zip" \
    "https://github.com/githubnext/monaspace/releases/download/${ver}/monaspace-nerdfonts-${ver}.zip"
  unzip -qo "$tmp/monaspace-nerdfonts.zip" -d "$tmp/monaspace"

  mkdir -p "$font_dir"
  find "$tmp/monaspace" -name '*.otf' -exec cp {} "$font_dir/" \;

  fc-cache -f 2>/dev/null || true

  local count
  count="$(find "$font_dir" -name '*.otf' | wc -l)"
  rm -rf "$tmp"
  trap - RETURN
  echo "  ✓ Monaspace Nerd Fonts ${ver} installed (${count} fonts in ${font_dir})"
}

post_install_fixes() {
  mkdir -p "$HOME/bin"
  if command -v fdfind >/dev/null 2>&1 && [[ ! -e "$HOME/bin/fd" ]]; then
    ln -s "$(command -v fdfind)" "$HOME/bin/fd"
  fi
}

backup_existing_dotfiles() {
  local backup_dir="$DOTFILES_DIR/old_bash"
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local files_backed_up=0

  local needs_backup=false
  [[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]] && needs_backup=true
  [[ -f "$HOME/.bash_aliases" && ! -L "$HOME/.bash_aliases" ]] && needs_backup=true
  [[ -f "$HOME/.inputrc" && ! -L "$HOME/.inputrc" ]] && needs_backup=true
  [[ -f "$HOME/bin/ex" && ! -L "$HOME/bin/ex" ]] && needs_backup=true
  [[ -f "$HOME/bin/clip" && ! -L "$HOME/bin/clip" ]] && needs_backup=true

  if [[ "$needs_backup" == "false" ]]; then return 0; fi

  backup_dir="${backup_dir}_${timestamp}"
  mkdir -p "$backup_dir"
  echo "Backing up existing dotfiles to: $backup_dir"

  if [[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]]; then
    mv "$HOME/.bashrc" "$backup_dir/.bashrc"
    echo "  ✓ Backed up .bashrc"
    ((++files_backed_up))
  fi

  if [[ -f "$HOME/.bash_aliases" && ! -L "$HOME/.bash_aliases" ]]; then
    mv "$HOME/.bash_aliases" "$backup_dir/.bash_aliases"
    echo "  ✓ Backed up .bash_aliases"
    ((++files_backed_up))
  fi

  if [[ -f "$HOME/.inputrc" && ! -L "$HOME/.inputrc" ]]; then
    mv "$HOME/.inputrc" "$backup_dir/.inputrc"
    echo "  ✓ Backed up .inputrc"
    ((++files_backed_up))
  fi

  if [[ -f "$HOME/bin/ex" && ! -L "$HOME/bin/ex" ]]; then
    mkdir -p "$backup_dir/bin"
    mv "$HOME/bin/ex" "$backup_dir/bin/ex"
    echo "  ✓ Backed up bin/ex"
    ((++files_backed_up))
  fi

  if [[ -f "$HOME/bin/clip" && ! -L "$HOME/bin/clip" ]]; then
    mkdir -p "$backup_dir/bin"
    mv "$HOME/bin/clip" "$backup_dir/bin/clip"
    echo "  ✓ Backed up bin/clip"
    ((++files_backed_up))
  fi

  if [[ $files_backed_up -gt 0 ]]; then
    echo "Backed up $files_backed_up file(s) in: $backup_dir"
  fi
}

stow_dotfiles() {
  if ! command -v stow >/dev/null 2>&1; then
    echo "Error: 'stow' is not installed." >&2
    exit 1
  fi

  echo "Applying stow packages: bash, bin, readline"
  if stow --dir "$DOTFILES_DIR" --target "$HOME" bash bin readline; then
    echo "  ✓ Dotfiles stowed successfully"
  else
    echo "Error: stow failed. See output above." >&2
    exit 1
  fi
}

# ============================================================
# Main
# ============================================================

main() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Error: apt-get not found. This installer targets Debian/Ubuntu." >&2
    exit 1
  fi

  echo ""
  echo "=== WSL Dotfiles Setup ==="
  echo "Log file: $LOG_FILE"

  # Phase 1: Component selection
  component_menu

  # Phase 2: Plan preview + confirmation (prompts for git identity if enabled)
  confirm_loop

  echo ""
  echo "=== Installing ==="
  echo ""

  # Default branch name (always safe regardless of identity setup)
  git config --global init.defaultBranch main

  # Git identity (only if selected -- skipped when conditional includes are in use)
  is_on git_identity && apply_git_config

  # apt update once if any apt packages are selected
  if is_on system_packages || is_on python || is_on go; then
    echo "Updating apt indexes..."
    sudo apt-get update -qq
  fi

  # apt packages by tag
  is_on system_packages && apt_install_packages core cli system
  is_on python          && apt_install_packages python
  is_on go              && apt_install_packages go

  # GitHub-installed tools
  if is_on lazygit; then
    if command -v lazygit >/dev/null 2>&1; then
      echo "  lazygit already installed. Skipping."
    else
      install_lazygit_from_github || echo "  Warning: lazygit install failed."
    fi
  fi

  if is_on lazydocker; then
    if command -v lazydocker >/dev/null 2>&1; then
      echo "  lazydocker already installed. Skipping."
    else
      install_lazydocker_from_github || echo "  Warning: lazydocker install failed."
    fi
  fi

  # WSL config
  is_on wsl_conf && configure_wsl

  # Git credential helper
  is_on git_credential && configure_git_credential_helper

  # Docker
  is_on docker && install_docker

  # Portainer
  is_on portainer && install_portainer

  # Node.js
  is_on nodejs && install_node_via_nvm

  # AI CLI tools
  if is_on cursor_cli; then
    install_cursor_cli || echo "  Warning: Cursor CLI install failed."
  fi
  if is_on codex_cli; then
    install_codex_cli || echo "  Warning: Codex CLI install failed."
  fi
  if is_on claude_cli; then
    install_claude_cli || echo "  Warning: Claude CLI install failed."
  fi

  # Monaspace fonts
  if is_on monaspace_fonts; then
    install_monaspace_fonts || echo "  Warning: Monaspace fonts install failed."
  fi

  # SSH key
  is_on ssh_key && generate_ssh_key

  # Post-install fixes (fd symlink, ~/bin)
  is_on system_packages && post_install_fixes

  # Dotfiles (stow)
  if is_on dotfiles; then
    backup_existing_dotfiles
    stow_dotfiles
  fi

  echo ""
  echo "Done. Log saved to: $LOG_FILE"
  echo "Open a new terminal, or run: source ~/.bashrc"
}

main "$@"
