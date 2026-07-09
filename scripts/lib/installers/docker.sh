# shellcheck shell=bash
# run_docker() is provided by scripts/lib/docker.sh (sourced via load.sh before installers).

configure_docker_daemon() {
	local daemon_json="/etc/docker/daemon.json"
	local tmp_file backup_file

	tmp_file="$(mktemp)"
	cat >"$tmp_file" <<'EOF'
{
	"storage-driver": "overlay2",
	"log-driver": "json-file",
	"log-opts": {
		"max-size": "10m",
		"max-file": "3"
	}
}
EOF

	sudo install -d -m 0755 /etc/docker

	if sudo test -f "$daemon_json" && sudo cmp -s "$tmp_file" "$daemon_json"; then
		log_skip "Docker daemon config already set in /etc/docker/daemon.json"
		rm -f "$tmp_file"
		return 0
	fi

	if sudo test -f "$daemon_json"; then
		backup_file="/etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)"
		sudo cp "$daemon_json" "$backup_file"
		log_step "Backed up existing Docker daemon config to $backup_file"
	fi

	sudo install -m 0644 "$tmp_file" "$daemon_json"
	rm -f "$tmp_file"
	log_ok "Docker daemon config written to /etc/docker/daemon.json"
}

restart_docker_service() {
	if command -v systemctl >/dev/null 2>&1 && sudo systemctl status docker >/dev/null 2>&1; then
		log_step "Restart Docker service (systemctl)"
		sudo systemctl restart docker
		return 0
	fi

	if command -v service >/dev/null 2>&1; then
		log_step "Restart Docker service (service)"
		sudo service docker restart
		return 0
	fi

	log_warn "Could not determine how to restart Docker service"
	return 1
}

verify_docker_storage_driver() {
	local driver
	driver="$(run_docker info --format '{{.Driver}}' 2>/dev/null || true)"

	if [[ -z "$driver" ]]; then
		driver="$(run_docker info 2>/dev/null | awk -F': ' '/^ Storage Driver:/ {print $2; exit}' || true)"
	fi

	if [[ "$driver" == "overlay2" ]]; then
		log_ok "Docker storage driver verified: overlay2"
		return 0
	fi

	if [[ -n "$driver" ]]; then
		log_warn "Docker storage driver is '$driver' (expected: overlay2)"
	else
		log_warn "Unable to determine Docker storage driver"
	fi

	return 1
}

install_docker() {
	if command -v docker >/dev/null 2>&1; then
		log_skip "Docker already installed ($(docker --version 2>/dev/null || echo 'unknown'))"
	else
		log_step "Install Docker Engine from official repo"
		local docker_distro codename
		# shellcheck disable=SC1091
		. /etc/os-release
		docker_distro="ubuntu"
		[[ "${ID:-}" == "debian" ]] && docker_distro="debian"
		codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

		sudo apt-get -o Dpkg::Use-Pty=0 install -y ca-certificates curl
		sudo install -m 0755 -d /etc/apt/keyrings
		sudo curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" -o /etc/apt/keyrings/docker.asc
		sudo chmod a+r /etc/apt/keyrings/docker.asc

		sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<DOCKEREOF
Types: deb
URIs: https://download.docker.com/linux/${docker_distro}
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKEREOF

		sudo apt-get update -qq
		sudo apt-get -o Dpkg::Use-Pty=0 install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
		log_ok "Docker Engine installed"
	fi

	if ! groups "$USER" | grep -qw docker; then
		sudo groupadd -f docker
		sudo usermod -aG docker "$USER"
		log_ok "Added $USER to docker group (log out/in or 'newgrp docker' to activate)"
	fi

	configure_docker_daemon
	if ! restart_docker_service; then
		log_warn "Docker restart failed after daemon config update"
	fi
	if ! verify_docker_storage_driver; then
		log_warn "Please check: docker info | grep \"Storage Driver\""
	fi
}

install_portainer() {
	if run_docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qw portainer; then
		log_skip "Portainer container already exists"
		return 0
	fi

	log_step "Install Portainer CE"
	run_docker volume create portainer_data
	run_docker run -d \
		-p 8000:8000 \
		-p 9443:9443 \
		--name portainer \
		--restart unless-stopped \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v portainer_data:/data \
		portainer/portainer-ce:latest
	run_docker stop portainer
	log_ok "Portainer installed (stopped — use 'dpot' to start, 'dpotstop' to stop)"
}
