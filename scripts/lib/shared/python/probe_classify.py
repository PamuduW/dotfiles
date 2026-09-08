"""How probe results read.

ADR-0001 stage two. Each function here is the Python counterpart of a
`_comp_classify_*` in scripts/lib/components/probes.sh, and
tests/test_probe_classify_parity.sh holds the two sides in agreement while both
exist.

Pure by construction: every input arrives as an argument and nothing here runs a
command, reads the environment, or touches the filesystem. That is what lets one
process classify every probe in a run -- measured at ~18 ms against ~324 ms for
a process per probe -- and what lets every state be tested without a machine in
that state.
"""

from __future__ import annotations

TIMEOUT_RC = 124


def portainer(*, docker_present: bool, rc: int, name: str) -> str:
    """Defect 5: a refused `docker ps` was read as "container not found", so a
    Portainer created moments earlier reported missing. The docker group is
    granted during the same run and is not active until the next session, so a
    refusal says nothing about the container."""
    if not docker_present:
        return "missing|docker is not installed"
    if rc == TIMEOUT_RC:
        return "check|portainer probe timed out"
    if name == "portainer":
        return "installed|container exists (stopped by default)"
    if rc != 0:
        return "check|cannot query docker yet (new docker group needs a new session)"
    return "missing|portainer container not found"


def codex_cli(*, state: str, path: str, version: str, rc: int) -> str:
    """Defect 6: a standalone install not yet on PATH was read as shadowed,
    routing the run into a migration with nothing to migrate."""
    if state in ("standalone", "standalone-not-on-path"):
        if rc == TIMEOUT_RC:
            return "check|codex cli probe timed out"
        shown = version or path
        if state == "standalone-not-on-path":
            return f"installed|{shown} (standalone, not on PATH in this session)"
        return f"installed|{shown} (standalone)"
    if state == "external":
        if rc == TIMEOUT_RC:
            return "check|codex cli probe timed out"
        return f"check|{version or path} (external; migration required)"
    if state == "standalone-shadowed":
        return f"check|standalone Codex is shadowed by {path or 'unknown'}"
    return "missing|codex not on PATH"


def missing_package_count(entries: list[str], installed: set[str]) -> int:
    """Defect 9: entries may be `preferred|fallback` renames, and querying the
    raw entry counted a renamed package as missing even though it was installed
    under its current name. An entry is present when any alternative is."""
    present = sum(
        1 for entry in entries if any(alt and alt in installed for alt in entry.split("|"))
    )
    return max(0, len(entries) - present)


def apt_packages(*, package_count: int, missing: int, missing_label: str) -> str:
    """Empty is skipped rather than clean: nothing was checked."""
    if package_count == 0:
        return "skipped|no packages listed"
    if missing != 0:
        return f"missing|{missing} of {package_count} {missing_label} not installed"
    return ""


def version(
    *,
    missing_label: str,
    timeout_label: str,
    binary: str,
    rc: int,
    raw: str,
    extract: str,
    prefix: str,
) -> str:
    """Shared by roughly ten components. An empty version still reports
    installed: the binary resolved and answered, so falling back to its label
    beats claiming it is missing."""
    import re

    if not binary:
        return f"missing|{missing_label} not on PATH"
    if rc == TIMEOUT_RC:
        return f"check|{timeout_label} probe timed out"
    shown = raw
    if extract:
        match = re.search(extract, raw)
        shown = match.group(0) if match else ""
    return f"installed|{prefix}{shown or timeout_label}"
