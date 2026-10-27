#!/usr/bin/env python3
"""Exercise Docker and Portainer only on an explicitly disposable hosted VM."""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def smoke(context: Path, disposable: bool):
    if (
        not disposable
        or os.environ.get("GITHUB_ACTIONS") != "true"
        or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted"
        or not re.fullmatch(r"[1-9][0-9]*", os.environ.get("GITHUB_RUN_ID", ""))
        or os.geteuid() == 0
        or Path("/.dockerenv").exists()
        or platform.machine() != "x86_64"
        or "microsoft" in platform.release().lower()
        or platform.freedesktop_os_release().get("VERSION_ID") != "24.04"
        or platform.freedesktop_os_release().get("ID") != "ubuntu"
    ):
        raise ValueError(
            "Docker lifecycle requires explicit disposable GitHub-hosted Ubuntu AMD64"
        )
    workspace = Path(os.environ.get("GITHUB_WORKSPACE", "/missing")).resolve()
    if ROOT != workspace / "dotfiles" or not str(workspace).startswith(
        "/home/runner/work/"
    ):
        raise ValueError("Docker lifecycle requires the hosted workspace checkout")
    shared = workspace / "dotfiles-shared"
    sys.path.insert(0, str(shared / "scripts/lib/shared/python"))
    from catalog_context import load_qualification_context
    from software_catalog import resolve_entry

    snapshot, sources, context_digest = load_qualification_context(context)
    if sources != {
        name: workspace / name for name in ("dotfiles", "dotfiles-shared", "agentbot")
    }:
        raise ValueError("Docker lifecycle sources differ from the hosted workspace")
    selected = {
        key: resolve_entry(snapshot, key, "linux-amd64", require_approved=False)
        for key, entry in snapshot.data["components"].items()
        if entry["owner"] == "dotfiles" and key.startswith("docker.")
    }
    if not selected or any(
        value.get("archive") != "deb" for value in selected.values()
    ):
        raise ValueError("Docker lifecycle requires all selected vendor packages")
    portainer = resolve_entry(
        snapshot, "portainer", "linux-amd64", require_approved=False
    )
    if portainer.get("archive") != "oci":
        raise ValueError("Portainer lifecycle requires its frozen OCI image")
    home = Path(tempfile.mkdtemp(prefix="catalog-docker-home-", dir="/tmp"))
    environment = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(home),
        "USER": os.environ["USER"],
        "LANG": "C.UTF-8",
        "DOTFILES_SHARED_DIR": str(shared),
        "DEBIAN_FRONTEND": "noninteractive",
    }
    # The runner's preinstalled engine is external state, so it cannot satisfy fresh coverage.
    script = r"""
set -euo pipefail
source "$1/scripts/lib/docker.sh"
source "$1/scripts/lib/installers/load.sh"
software_catalog_qualification_begin "$2"
shift 2
sudo -n true
[[ -z "$(sudo docker ps -aq)" ]]
mapfile -t installed < <(dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' |
    awk '$2 == "installed" && $1 ~ /^(docker-ce|docker-ce-cli|docker-ce-rootless-extras|docker-buildx-plugin|docker-compose-plugin|docker.io|docker-buildx|docker-compose-v2|moby-engine|moby-cli|moby-buildx|moby-compose|containerd.io|containerd|runc)$/ {print $1}')
[[ "${#installed[@]}" -gt 0 ]]
sudo systemctl stop docker.service docker.socket containerd.service
sudo apt-mark unhold "${installed[@]}" >&2
sudo apt-get -o DPkg::Lock::Timeout=600 purge -y "${installed[@]}" >&2
for key in "$@"; do
    package="$(dotfiles_catalog_get "$key" package)"
    status=0
    dpkg-query -W "$package" >/dev/null 2>&1 || status=$?
    [[ "$status" == 1 ]]
done
sudo apt-get update >&2
install_docker >&2
sudo systemctl start docker.service
for ((attempt=0; attempt<30; attempt++)); do
    if sudo docker info >/dev/null 2>&1; then break; fi
    sleep 1
done
sudo docker info >/dev/null
for key in "$@"; do
    package="$(dotfiles_catalog_get "$key" package)"
    dotfiles_catalog_apt_owned "$key" "$package"
    actual="$(dpkg-query -W -f='${Version}' "$package")"
    [[ "$actual" == "$(dotfiles_catalog_get "$key" version)" ]]
    printf 'package\t%s\t%s\n' "$key" "$actual"
done
[[ "$(sudo docker version --format '{{.Server.Version}}')" == "$(dotfiles_catalog_get docker.docker-ce version | sed -E 's/^[0-9]+://; s/-.*//')" ]]
install_portainer >&2
_portainer_has_managed_layout
image="$(dotfiles_catalog_get portainer package)@$(dotfiles_catalog_get portainer digest)"
expected_image="$(run_docker image inspect --format '{{.Id}}' "$image")"
[[ "$(run_docker inspect --format '{{.Image}}' portainer)" == "$expected_image" ]]
[[ "$(run_docker inspect --format '{{.Config.Image}}' portainer)" == "$image" ]]
[[ "$(run_docker inspect --format '{{.State.Running}}' portainer)" == false ]]
volume="$(run_docker volume inspect --format '{{.Mountpoint}}' portainer_data)"
[[ "$volume" == /var/lib/docker/volumes/portainer_data/_data ]]
printf 'catalog-synthetic-data\n' | sudo tee "$volume/catalog-marker" >/dev/null
run_docker start portainer >&2
for ((attempt=0; attempt<45; attempt++)); do
    if curl --silent --show-error --insecure --max-time 3 https://127.0.0.1:9443/api/status >"$HOME/status.json" 2>/dev/null; then break; fi
    sleep 1
done
python3 - "$HOME/status.json" "$(dotfiles_catalog_get portainer version)" <<'CHECK'
import json,sys
assert json.load(open(sys.argv[1]))['Version'].removeprefix('v') == sys.argv[2].removeprefix('v')
CHECK
previous="$(run_docker inspect --format '{{.Id}}' portainer)"
daemon_pid="$(sudo systemctl show --property MainPID --value docker.service)"
install_docker >&2
[[ "$(sudo systemctl show --property MainPID --value docker.service)" == "$daemon_pid" ]]
install_portainer >&2
[[ "$(run_docker inspect --format '{{.Id}}' portainer)" == "$previous" ]]
[[ "$(sudo cat "$volume/catalog-marker")" == catalog-synthetic-data ]]
# Fault injection affects only the new create; rollback uses the real engine and old container.
eval "$(declare -f run_docker | sed '1s/run_docker/catalog_real_docker/')"
run_docker() {
    if [[ "$1" == create ]]; then
        printf 'Injected container creation failure\n' >&2
        return 73
    fi
    catalog_real_docker "$@"
}
DOTFILES_FORCE_REINSTALL=1
export DOTFILES_FORCE_REINSTALL
status=0
install_portainer >&2 || status=$?
[[ "$status" != 0 ]]
[[ "$(run_docker inspect --format '{{.Id}}' portainer)" == "$previous" ]]
[[ "$(run_docker inspect --format '{{.State.Running}}' portainer)" == true ]]
[[ "$(sudo cat "$volume/catalog-marker")" == catalog-synthetic-data ]]
! _portainer_name_exists "$(_portainer_backup_name)"
printf 'image\t%s\t%s\n' "$image" "$expected_image"
printf 'lifecycle\tfresh-repeat-failure-recovery\tsuccess\n'
"""
    result = subprocess.run(
        ["bash", "-c", script, "bash", str(ROOT), str(context), *sorted(selected)],
        cwd=ROOT,
        env=environment,
        stdout=subprocess.PIPE,
        text=True,
        check=True,
        timeout=1200,
    )
    if load_qualification_context(context)[2] != context_digest:
        raise ValueError("Docker lifecycle context changed")
    observed = {}
    image = None
    lifecycle = False
    for row in result.stdout.splitlines():
        fields = row.split("\t")
        if len(fields) != 3:
            raise ValueError("unexpected Docker lifecycle observation")
        kind, name, value = fields
        if (
            kind == "package"
            and name in selected
            and name not in observed
            and value == selected[name]["version"]
        ):
            observed[name] = value
        elif (
            kind == "image"
            and image is None
            and name == portainer["package"] + "@" + portainer["digest"]
            and re.fullmatch(r"sha256:[0-9a-f]{64}", value)
        ):
            image = {"reference": name, "image_id": value}
        elif (
            fields == ["lifecycle", "fresh-repeat-failure-recovery", "success"]
            and not lifecycle
        ):
            lifecycle = True
        else:
            raise ValueError("Docker lifecycle evidence differs from the candidate")
    if set(observed) != set(selected) or image is None or not lifecycle:
        raise ValueError("incomplete Docker lifecycle coverage")
    return {
        "schema_version": 1,
        "scope": "docker-lifecycle-smoke-only",
        "approved": False,
        "catalog_digest": snapshot.digest,
        "sources": dict(snapshot.data["sources"]),
        "packages": observed,
        "portainer": image,
        "fresh": "success",
        "repeat": "success",
        "failed_replacement_recovery": "success",
        "volume_data_preserved": True,
        "local_status_api": "success",
        "upgrade_qualified": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("context", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--disposable-host", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.output.exists() or args.output.is_symlink():
            raise ValueError("preserving existing Docker evidence")
        result = smoke(args.context.resolve(), args.disposable_host)
        with args.output.open("x") as stream:
            json.dump(result, stream, indent=2)
            stream.write("\n")
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Docker lifecycle held: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
