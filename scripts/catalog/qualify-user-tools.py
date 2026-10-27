#!/usr/bin/env python3
"""Exercise real user-local installs in disposable Ubuntu; never approve data."""

from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def select_inventory(snapshot):
    from software_catalog import resolve_entry

    selected = {}
    for key, entry in snapshot.data["components"].items():
        if entry["owner"] != "dotfiles" or entry["kind"] not in {
            "software",
            "git-source",
        }:
            continue
        artifact = resolve_entry(snapshot, key, "linux-amd64", require_approved=False)
        if (
            artifact["archive"] not in {"deb", "oci"}
            and artifact.get("binary") != "fonts"
        ):
            selected[key] = entry
    return selected


def smoke(manifest: Path, output: Path) -> dict:
    shared = subprocess.check_output(
        [
            "bash",
            "-c",
            'source "$1/scripts/lib/shared_resolve.sh"; dotfiles_shared_require "$1" || exit 2; printf "%s" "$DOTFILES_SHARED_ROOT"',
            "bash",
            str(ROOT),
        ],
        text=True,
    )
    sys.path.insert(0, str(Path(shared) / "scripts/lib/shared/python"))
    from catalog_context import load_qualification_context
    from software_catalog import CatalogError

    snapshot, sources, _ = load_qualification_context(manifest)
    system = platform.freedesktop_os_release()
    if sources["dotfiles"] != ROOT or sources["dotfiles-shared"] != Path(shared):
        raise CatalogError("user-tools smoke requires its frozen source checkouts")
    if (
        system.get("ID") != "ubuntu"
        or system.get("VERSION_ID") != "24.04"
        or platform.machine() != "x86_64"
    ):
        raise CatalogError("user-tools smoke requires Ubuntu 24.04 AMD64")
    if not Path("/.dockerenv").exists() or os.geteuid() == 0:
        raise CatalogError(
            "user-tools smoke requires a disposable container and a non-root user"
        )
    selected = select_inventory(snapshot)
    if not selected:
        raise CatalogError("user-tools smoke cannot pass with empty coverage")
    order, active, complete = [], set(), set()

    def visit(key):
        if key in complete:
            return
        if key in active:
            raise CatalogError("user-tools dependency cycle")
        active.add(key)
        for dependency in selected[key]["requires"]:
            if dependency in selected:
                visit(dependency)
        active.remove(key)
        complete.add(key)
        order.append(key)

    for key in sorted(selected):
        visit(key)
    script = """
set -euo pipefail
trap 'status=$?; printf "User-tools failure: %s/%s (exit %s)\\n" "${phase:-setup}" "${key:-setup}" "$status" >&2' ERR
source "$1/scripts/lib/installers/load.sh"
software_catalog_qualification_begin "$2"
dotfiles_catalog_begin
shift 2
for phase in fresh repeat; do
    for key in "$@"; do
        printf 'User tools %s: %s\\n' "$phase" "$key" >&2
        if [[ "$(dotfiles_catalog_get "$key" kind)" == git-source ]]; then
            checkout="$(dotfiles_catalog_source_install "$key")"
            dotfiles_catalog_source_owned "$key"
            dotfiles_catalog_source_checkout_owned "$key" "$checkout"
            actual="$(_dotfiles_catalog_source_git -C "$checkout" rev-parse --verify HEAD)"
            expected="$(dotfiles_catalog_get "$key" revision)"
        else
            dotfiles_catalog_install "$key" >&2
            dotfiles_catalog_owned "$key" || { echo "Missing ownership: $key" >&2; exit 2; }
            actual="$(dotfiles_catalog_installed "$key")"
            expected="$(dotfiles_catalog_get "$key" version)"
        fi
        [[ "$actual" == "$expected" ]] || { echo "Version mismatch: $key ($actual)" >&2; exit 2; }
        printf '%s\\t%s\\t%s\\n' "$phase" "$key" "$actual"
    done
done
"""
    result = subprocess.run(
        ["bash", "-c", script, "bash", str(ROOT), str(manifest), *order],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        check=True,
        timeout=1800,
    )
    observations = {phase: {} for phase in ("fresh", "repeat")}
    for line in result.stdout.splitlines():
        phase, key, version = line.split("\t")
        if (
            phase not in observations
            or key not in selected
            or key in observations[phase]
        ):
            raise CatalogError("unexpected or duplicate user-tools observation")
        observations[phase][key] = version
    if any(set(values) != set(selected) for values in observations.values()):
        raise CatalogError(
            "user-tools observations do not cover the selected inventory"
        )
    scan = output.parent / "container-vulnerabilities.json"
    subprocess.run(
        [
            str(Path.home() / ".local/bin/trivy"),
            "rootfs",
            "--scanners",
            "vuln",
            "--format",
            "json",
            "--output",
            str(scan),
            "--exit-code",
            "0",
            "--skip-dirs",
            "/proc",
            "--skip-dirs",
            "/sys",
            "--skip-dirs",
            "/dev",
            "--skip-dirs",
            "/root",
            "--skip-dirs",
            str(ROOT.parent),
            "--skip-dirs",
            str(Path.home() / ".cache"),
            "/",
        ],
        check=True,
        timeout=300,
    )
    load_qualification_context(manifest)
    return {
        "schema_version": 1,
        "scope": "user-tools-smoke-only",
        "approved": False,
        "catalog_digest": snapshot.digest,
        "sources": dict(snapshot.data["sources"]),
        "observations": observations,
        "excluded_components": sorted(set(snapshot.data["components"]) - set(selected)),
        "container_scan": scan.name,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("context", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.output.exists() or args.output.is_symlink():
            raise ValueError("preserving existing user-tools evidence")
        result = smoke(args.context.resolve(), args.output.resolve())
        with args.output.open("x") as stream:
            json.dump(result, stream, indent=2)
            stream.write("\n")
    except subprocess.CalledProcessError as error:
        print(
            f"User-tools subprocess failed with exit {error.returncode}; see component diagnostics above",
            file=sys.stderr,
        )
        return 2
    except subprocess.TimeoutExpired as error:
        print(
            f"User-tools subprocess exceeded {error.timeout} seconds", file=sys.stderr
        )
        return 2
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
