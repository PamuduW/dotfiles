#!/usr/bin/env python3
"""Run package-only vendor qualification in a disposable hosted CI container."""

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


def select_packages(snapshot):
    from software_catalog import CatalogError, resolve_entry

    selected = {}
    packages = set()
    for key, entry in sorted(snapshot.data["components"].items()):
        if entry["owner"] != "dotfiles":
            continue
        is_deb = entry["discovery"].get("archive") == "deb" or any(
            artifact.get("archive") == "deb" for artifact in entry["targets"].values()
        )
        if entry["kind"] != "vendor-apt" and not (
            entry["kind"] == "software" and is_deb
        ):
            continue
        artifact = resolve_entry(snapshot, key, "linux-amd64", require_approved=False)
        package = artifact.get("package", "")
        if (
            artifact.get("archive") != "deb"
            or not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", package)
            or package in packages
        ):
            raise CatalogError(f"unsupported or duplicate vendor package: {key}")
        packages.add(package)
        selected[key] = artifact
    if not {"powershell", "obsidian"} <= selected.keys():
        raise CatalogError(
            "vendor smoke requires nonempty package and application coverage"
        )
    for key, binary in (("powershell", "pwsh"), ("obsidian", "obsidian")):
        if selected[key].get("binary") != binary:
            raise CatalogError(f"unsupported vendor application probe: {key}")
    return selected


def install_packages(context, selected, environment, context_digest):
    script = r"""
set -euo pipefail
source "$1/scripts/lib/installers/load.sh"
root="$1"; context="$2"; expected_context="$3"; shift 3
[[ "$(sha256sum -- "$context")" == "$expected_context "* ]]
software_catalog_qualification_begin "$context"
[[ "$(software_catalog_qualification_source dotfiles)" == "$root" ]]
dotfiles_catalog_begin
sudo -n true
status=0
sudo /usr/sbin/policy-rc.d || status=$?
[[ "$status" == 101 ]]
for key in "$@"; do
    package="$(dotfiles_catalog_get "$key" package)"
    receipt="$HOME/.local/share/dotfiles-catalog/$key.apt"
    [[ ! -e "$receipt" && ! -L "$receipt" ]]
    status=0
    dpkg-query -W "$package" >/dev/null 2>&1 || status=$?
    case "$status" in
        1) ;;
        0) printf 'Pre-existing vendor package: %s\n' "$package" >&2; exit 2 ;;
        *) printf 'Cannot determine package state: %s\n' "$package" >&2; exit 2 ;;
    esac
done
# Only distro dependencies may float; every selected vendor package is a pinned deb.
sudo apt-get update >&2
for phase in fresh repeat; do
    dotfiles_catalog_begin
    dotfiles_catalog_install_debs "$@" >&2
    holds="$(apt-mark showhold)"
    for key in "$@"; do
        package="$(dotfiles_catalog_get "$key" package)"
        expected="$(dotfiles_catalog_get "$key" version)"
        dotfiles_catalog_apt_owned "$key" "$package"
        actual="$(dpkg-query -W -f='${Version}' "$package")"
        [[ "$actual" == "$expected" ]]
        mapfile -t proof <"$HOME/.local/share/dotfiles-catalog/$key.apt"
        [[ "${#proof[@]}" == 3 && "${proof[0]}" == "$package" &&
           "${proof[1]}" == "$actual" && "${proof[2]}" == "$SOFTWARE_CATALOG_DIGEST" ]]
        grep -Fxq -- "$package" <<<"$holds"
        printf '%s\t%s\t%s\t%s\t%s\theld\n' "$phase" "$key" "$package" "$actual" "${proof[2]}"
    done
done
dotfiles_catalog_begin
"""
    return subprocess.run(
        [
            "bash",
            "-c",
            script,
            "bash",
            str(ROOT),
            str(context),
            context_digest,
            *selected,
        ],
        cwd=ROOT,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        check=True,
        timeout=1800,
    ).stdout


def parse_observations(raw, selected, digest):
    from software_catalog import CatalogError

    observations = {"fresh": {}, "repeat": {}}
    for row in raw.splitlines():
        fields = row.split("\t")
        if len(fields) != 6:
            raise CatalogError("malformed vendor package observation")
        phase, key, package, version, receipt_digest, hold = fields
        if (
            phase not in observations
            or key not in selected
            or key in observations[phase]
            or package != selected[key]["package"]
            or version != selected[key]["version"]
            or receipt_digest != digest
            or hold != "held"
        ):
            raise CatalogError(
                "vendor package observation differs from frozen candidate"
            )
        observations[phase][key] = {
            "package": package,
            "version": version,
            "receipt_digest": receipt_digest,
            "hold": True,
        }
    if any(set(items) != set(selected) for items in observations.values()):
        raise CatalogError("incomplete vendor package fresh/repeat coverage")
    return observations


def probe_applications(selected, environment):
    from software_catalog import CatalogError

    paths = {}
    for key in ("powershell", "obsidian"):
        binary = selected[key]["binary"]
        resolved = subprocess.check_output(
            ["bash", "-c", 'command -v "$1"', "bash", binary],
            env=environment,
            text=True,
            timeout=10,
        ).strip()
        owner = subprocess.check_output(
            ["dpkg-query", "-S", str(Path(resolved).resolve())],
            env=environment,
            text=True,
            timeout=10,
        ).strip()
        if not owner.startswith(selected[key]["package"] + ": "):
            raise CatalogError(f"application executable is not package-owned: {key}")
        paths[key] = resolved
    powershell = subprocess.check_output(
        [
            paths["powershell"],
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            (
                "$ErrorActionPreference='Stop'; "
                "$x = @{message='catalog-ok'; total=(1..4 | Measure-Object -Sum).Sum}; "
                "$x | ConvertTo-Json -Compress"
            ),
        ],
        env=environment,
        text=True,
        timeout=30,
    )
    if json.loads(powershell) != {"message": "catalog-ok", "total": 10}:
        raise CatalogError("PowerShell local pipeline/JSON probe failed")
    gui = r"""
set -euo pipefail
"$1" --no-sandbox --disable-gpu --disable-dev-shm-usage \
    --disable-background-networking --user-data-dir="$HOME/obsidian-profile" >"$HOME/obsidian.log" 2>&1 &
app=$!
trap 'kill "$app" 2>/dev/null || true; wait "$app" 2>/dev/null || true' EXIT
for ((attempt=0; attempt<25; attempt++)); do
    kill -0 "$app"
    windows="$(xdotool search --onlyvisible --class '[Oo]bsidian' 2>/dev/null || true)"
    if [[ -n "$windows" ]]; then
        sleep 2
        kill -0 "$app"
        xdotool search --onlyvisible --class '[Oo]bsidian' >/dev/null
        printf 'visible-obsidian-window\n'
        exit 0
    fi
    sleep 1
done
printf 'Obsidian did not expose a visible window within 25 seconds\n' >&2
exit 2
"""
    window = subprocess.check_output(
        [
            "xvfb-run",
            "-a",
            "--server-args=-screen 0 1280x800x24",
            "dbus-run-session",
            "--",
            "bash",
            "-c",
            gui,
            "bash",
            paths["obsidian"],
        ],
        env=environment,
        text=True,
        timeout=45,
    ).strip()
    if window != "visible-obsidian-window":
        raise CatalogError("Obsidian GUI readiness observation missing")
    return {
        "powershell": {"path": paths["powershell"], "local_pipeline_json": "success"},
        "obsidian": {
            "path": paths["obsidian"],
            "xvfb_visible_window": "success",
            "readiness_timeout_seconds": 25,
            "sandbox_disabled": True,
        },
    }


def smoke(context):
    shared = subprocess.check_output(
        [
            "bash",
            "-c",
            (
                'source "$1/scripts/lib/shared_resolve.sh"; '
                'dotfiles_shared_require "$1" || exit 2; printf "%s" "$DOTFILES_SHARED_ROOT"'
            ),
            "bash",
            str(ROOT),
        ],
        text=True,
        timeout=30,
    )
    sys.path.insert(0, str(Path(shared) / "scripts/lib/shared/python"))
    from catalog_context import load_qualification_context
    from software_catalog import CatalogError

    snapshot, sources, context_digest = load_qualification_context(context)
    if sources["dotfiles"] != ROOT or sources["dotfiles-shared"] != Path(shared):
        raise CatalogError("vendor smoke requires its frozen source checkouts")
    system = platform.freedesktop_os_release()
    if (system.get("ID"), system.get("VERSION_ID"), platform.machine()) != (
        "ubuntu",
        "24.04",
        "x86_64",
    ):
        raise CatalogError("vendor smoke requires Ubuntu 24.04 AMD64")
    if (
        not Path("/.dockerenv").is_file()
        or os.geteuid() == 0
        or os.environ.get("GITHUB_ACTIONS") != "true"
    ):
        raise CatalogError("vendor smoke requires a non-root hosted CI container")
    if any(
        Path(path).exists() for path in ("/var/run/docker.sock", "/run/docker.sock")
    ):
        raise CatalogError("vendor package smoke forbids a Docker socket")
    daemon = subprocess.run(
        ["pgrep", "-x", "dockerd"], capture_output=True, timeout=10, check=False
    )
    if daemon.returncode != 1:
        raise CatalogError("vendor package smoke requires no Docker daemon")
    selected = select_packages(snapshot)
    home = Path(tempfile.mkdtemp(prefix="catalog-vendor-home-", dir="/tmp"))
    environment = {
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "HOME": str(home),
        "USER": "op",
        "LOGNAME": "op",
        "LANG": "C.UTF-8",
        "DOTFILES_SHARED_DIR": str(sources["dotfiles-shared"]),
        "POWERSHELL_TELEMETRY_OPTOUT": "1",
        "POWERSHELL_UPDATECHECK": "Off",
        "DEBIAN_FRONTEND": "noninteractive",
    }
    print(f"Private vendor qualification HOME retained at {home}", file=sys.stderr)
    observations = parse_observations(
        install_packages(context, selected, environment, context_digest),
        selected,
        snapshot.digest,
    )
    if load_qualification_context(context)[2] != context_digest:
        raise CatalogError("vendor qualification context changed during installation")
    probes = probe_applications(selected, environment)
    if load_qualification_context(context)[2] != context_digest:
        raise CatalogError(
            "vendor qualification context changed during application probes"
        )
    if (
        subprocess.run(
            ["pgrep", "-x", "dockerd"], capture_output=True, timeout=10, check=False
        ).returncode
        != 1
    ):
        raise CatalogError("package installation unexpectedly started a Docker daemon")
    return {
        "schema_version": 1,
        "scope": "vendor-package-smoke-only",
        "approved": False,
        "catalog_digest": snapshot.digest,
        "sources": dict(snapshot.data["sources"]),
        "observations": observations,
        "application_probes": probes,
        "home": str(home),
        "docker_daemon_qualified": False,
        "portainer_qualified": False,
        "limitations": [
            "fresh/repeat packages only; no baseline upgrade or failed replacement",
            "Obsidian window readiness only; no vault editing or authentication",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("context", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.output.exists() or args.output.is_symlink():
            raise ValueError("preserving existing vendor package evidence")
        result = smoke(args.context.resolve())
        with args.output.open("x") as stream:
            json.dump(result, stream, indent=2)
            stream.write("\n")
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Vendor package qualification held: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
