# shellcheck shell=bash
# run_docker() is provided by scripts/lib/docker.sh (sourced via load.sh before installers).

configure_docker_daemon() {
	local daemon_json="/etc/docker/daemon.json"
	local tmp_file backup_file merge_status

	command -v python3 >/dev/null 2>&1 || {
		log_warn "Python 3 is required to safely merge /etc/docker/daemon.json; leaving it unchanged"
		return 1
	}

	# The merge runs under sudo because daemon.json may be readable only by root.
	# Keep its temporary destination in that same ownership boundary: a user-owned
	# 0600 mktemp file can reject the root-run Python writer on constrained WSL
	# mounts.
	tmp_file="$(sudo mktemp)"

	sudo install -d -m 0755 /etc/docker

	if sudo test -f "$daemon_json"; then
		# Do not replace a user's daemon configuration. Merge only our logging
		# defaults, preserve unrelated keys, and refuse conflicting log settings.
		if sudo python3 - "$daemon_json" "$tmp_file" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
try:
    with open(source, encoding="utf-8") as handle:
        config = json.load(handle)
except (OSError, json.JSONDecodeError) as error:
    print(f"cannot parse existing Docker JSON: {error}", file=sys.stderr)
    raise SystemExit(2)

if not isinstance(config, dict):
    print("existing Docker configuration must be a JSON object", file=sys.stderr)
    raise SystemExit(2)

defaults = {
    "log-driver": "json-file",
    "log-opts": {"max-size": "10m", "max-file": "3"},
}
for key in ("log-driver",):
    if key in config and config[key] != defaults[key]:
        print(f"existing {key!r} conflicts with requested default {defaults[key]!r}", file=sys.stderr)
        raise SystemExit(3)

existing_options = config.get("log-opts", {})
if not isinstance(existing_options, dict):
    print("existing 'log-opts' must be a JSON object", file=sys.stderr)
    raise SystemExit(2)
for key, value in defaults["log-opts"].items():
    if key in existing_options and existing_options[key] != value:
        print(f"existing log-opts.{key!r} conflicts with requested default {value!r}", file=sys.stderr)
        raise SystemExit(3)

config.setdefault("log-driver", defaults["log-driver"])
config["log-opts"] = {**defaults["log-opts"], **existing_options}
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
		then
			:
		else
			merge_status=$?
			sudo rm -f "$tmp_file"
			if [[ "$merge_status" -eq 3 ]]; then
				log_warn "Existing Docker daemon settings conflict with dotfiles defaults; leaving $daemon_json unchanged"
				return 1
			fi
			log_warn "Existing Docker daemon config is invalid or cannot be safely read; leaving it unchanged"
			return 1
		fi
		if sudo cmp -s "$tmp_file" "$daemon_json"; then
			log_skip "Docker daemon config already contains the dotfiles defaults"
			sudo rm -f "$tmp_file"
			return 0
		fi
		backup_file="/etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)"
		sudo cp "$daemon_json" "$backup_file"
		log_step "Backed up existing Docker daemon config to $backup_file"
	else
		sudo tee "$tmp_file" >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
	fi

	# Modern Docker selects its storage driver automatically. Validate the exact
	# merged configuration before changing the live daemon file when dockerd is
	# available; older/minimal environments simply retain the safe merge above.
	if command -v dockerd >/dev/null 2>&1; then
		if ! sudo dockerd --validate --config-file "$tmp_file"; then
			log_warn "Docker rejected the proposed daemon configuration; leaving $daemon_json unchanged"
				sudo rm -f "$tmp_file"
			return 1
		fi
	else
		log_warn "dockerd is unavailable; unable to validate the proposed daemon config before writing it"
	fi

	sudo install -m 0644 "$tmp_file" "$daemon_json"
	sudo rm -f "$tmp_file"
	log_ok "Docker daemon logging config safely written to /etc/docker/daemon.json"
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

	if ! configure_docker_daemon; then
		log_warn "Docker daemon configuration was not applied; refusing to restart Docker"
		return 1
	fi
	if ! restart_docker_service; then
		log_warn "Docker restart failed after daemon config update"
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
