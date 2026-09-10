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

Run as a script, this is that one process: `comp_classify` in probes.sh writes
one request per line to stdin and reads one `result|detail` back per line, in
order. Fields are separated by \x1f and a newline inside a field travels as
\x1e, because the requests are collected through files that Bash reads a line
at a time.
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


def package_gaps(
    entries: list[str], installed: set[str], available: set[str]
) -> tuple[int, int]:
    """(missing, unavailable) for entries with no installed alternative.

    The two are different problems and only one of them is the operator's. A
    package this release does not carry -- `wslu` on Ubuntu 26.04 -- cannot be
    installed by anyone, and counting it as missing leaves a row permanently red
    with nothing to do about it. The installer already draws this line; the
    reading did not, so the two disagreed about the same machine.
    """
    missing = unavailable = 0
    for entry in entries:
        alternatives = [alt for alt in entry.split("|") if alt]
        if any(alt in installed for alt in alternatives):
            continue
        if any(alt in available for alt in alternatives):
            missing += 1
        else:
            unavailable += 1
    return missing, unavailable


def apt_packages(
    *,
    package_count: int,
    missing: int,
    missing_label: str,
    clean_detail: str,
    unavailable: int = 0,
) -> str:
    """Empty is skipped rather than clean: nothing was checked.

    `clean_detail` is the caller's wording for a complete set. It arrives as an
    argument because the two callers word it differently and because the
    alternative -- returning nothing and letting the caller decide -- is a
    control-flow dependency on the classification, which cannot be deferred to
    a batched call.
    """
    aside = f" ({unavailable} unavailable on this release)" if unavailable else ""
    if package_count == 0:
        return "skipped|no packages listed"
    if missing != 0:
        return f"missing|{missing} of {package_count} {missing_label} not installed{aside}"
    return f"installed|{clean_detail}{aside}"


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


def go(
    *,
    go_present: bool,
    go_rc: int,
    go_raw: str,
    asdf_present: bool,
    asdf_rc: int,
    asdf_raw: str,
) -> str:
    """Two sources with a fallback between them.

    The subtle path: `go` resolves but its output does not parse, so this falls
    through to asdf rather than reporting a version it does not have.
    """
    import re

    if go_present:
        if go_rc == TIMEOUT_RC:
            return "check|go probe timed out"
        match = re.search(r"go[0-9.]+", go_raw)
        if match:
            return f"installed|{match.group(0)}"

    if asdf_present:
        if asdf_rc == TIMEOUT_RC:
            return "check|go probe timed out"
        selected = ""
        for line in asdf_raw.splitlines():
            fields = line.split()
            if fields and fields[0] == "golang":
                selected = fields[1] if len(fields) > 1 else ""
                break
        if selected and selected != "system":
            return f"installed|go{selected} (asdf)"
        return "missing|asdf has no selected Go version"

    return "missing|working Go installation not found"


def git_credential(
    *, helper: str, recurse: str, fetch: str, push: str, summary: str
) -> str:
    """Five inputs, three outcomes. Every submodule default set but no
    credential helper is a different message from a partial configuration, and
    one value of five separates them."""
    defaults_set = (
        recurse == "true"
        and fetch == "on-demand"
        and push == "check"
        and summary == "true"
    )
    if defaults_set and helper:
        return "configured|credential helper + recursive submodule defaults"
    if defaults_set:
        return "check|submodule defaults set; credential helper not configured"
    return "check|Git configuration incomplete"


def git_identity(*, name: str, email: str) -> str:
    """Both halves or neither: an identity with only one of them configured is
    not usable, and `git commit` says so at the worst possible moment."""
    if name and email:
        return f"configured|{name} <{email}>"
    return "missing|not configured"


def python_runtime(*, python3_present: bool, pip_ok: bool, venv_ok: bool) -> str:
    """Three questions asked in order, because each one needs the answer before
    it. The reading names the first that failed rather than the last."""
    if not python3_present:
        return "missing|python3 not on PATH"
    if not pip_ok:
        return "missing|python3-pip unavailable"
    if not venv_ok:
        return "missing|python3-venv unavailable"
    return "installed|python3 pip venv ready"


def owned_cli(
    *,
    missing_label: str,
    timeout_label: str,
    owned_suffix: str,
    external_suffix: str,
    found: bool,
    rc: int,
    version: str,
    path: str,
    owned: bool,
) -> str:
    """Graphify and Boost differ only in what they call themselves and in what
    owning them means -- uv against nothing, Dotfiles-managed against external.
    Same shape as `version` above, plus the ownership the two report."""
    if not found:
        return f"missing|{missing_label} not on PATH"
    if rc == TIMEOUT_RC:
        return f"check|{timeout_label} probe timed out"
    suffix = owned_suffix if owned else external_suffix
    return f"installed|{version or path}{suffix}"


def monaspace_fonts(*, present: bool, count: str, version: str) -> str:
    """A directory with no .otf in it is not an installation, so presence here
    means the fonts, never the folder."""
    if not present:
        return "missing|fonts not in ~/.local/share/fonts/monaspace"
    return f"installed|{version} ({count} fonts)"


def stow_targets(*, missing: int) -> str:
    """A link pointing somewhere else is as missing as no link at all: the
    count is of targets that do not resolve to this checkout."""
    if missing == 0:
        return "installed|stow bash bin readline"
    return f"missing|{missing} managed stow target(s) missing or incorrect"


def wsl_conf(*, present: bool, systemd: bool, append_windows_path: bool) -> str:
    if present and systemd and append_windows_path:
        return "configured|systemd + appendWindowsPath"
    return "check|/etc/wsl.conf not as expected"


# --- Batch front end -------------------------------------------------------
#
# The wire format is deliberately dull: no JSON to quote and unquote on the Bash
# side, and separators that cannot occur in a version string or a path.

FIELD_SEP = "\x1f"
NEWLINE_SUB = "\x1e"


def classify(fields: list[str]) -> str:
    """One request -> one `result|detail` line.

    Arity is checked by unpacking: a request with the wrong number of fields
    raises here rather than silently classifying something else.
    """
    name, args = fields[0], fields[1:]

    if name == "version":
        missing_label, timeout_label, binary, rc, raw, extract, prefix = args
        return version(
            missing_label=missing_label,
            timeout_label=timeout_label,
            binary=binary,
            rc=int(rc or 0),
            raw=raw,
            extract=extract,
            prefix=prefix,
        )
    if name == "go":
        go_present, go_rc, go_raw, asdf_present, asdf_rc, asdf_raw = args
        return go(
            go_present=go_present == "1",
            go_rc=int(go_rc or 0),
            go_raw=go_raw,
            asdf_present=asdf_present == "1",
            asdf_rc=int(asdf_rc or 0),
            asdf_raw=asdf_raw,
        )
    if name == "portainer":
        docker_present, rc, container = args
        return portainer(
            docker_present=docker_present == "1", rc=int(rc or 0), name=container
        )
    if name == "codex_cli":
        state, path, ver, rc = args
        return codex_cli(state=state, path=path, version=ver, rc=int(rc or 0))
    if name == "git_credential":
        helper, recurse, fetch, push, summary = args
        return git_credential(
            helper=helper, recurse=recurse, fetch=fetch, push=push, summary=summary
        )
    if name == "apt":
        # Variable arity: the package entries and the installed names are both
        # lists, so the entry count separates them. Counting and reading are one
        # request because the count is not a decision anyone else needs.
        queried, catalog, missing_label, clean_detail, entry_count, installed_count = args[:6]
        if catalog != "1":
            return "missing|packages.txt not found"
        # A query that never answered says nothing about what is installed;
        # reading its silence as "none of them" would report a healthy machine
        # as empty, which is worse than saying the state is unknown.
        if queried != "1":
            return "check|package state unknown (dpkg-query timed out)"
        rest = args[6:]
        count, installed_end = int(entry_count or 0), int(entry_count or 0) + int(
            installed_count or 0
        )
        entries = [entry for entry in rest[:count] if entry]
        installed = {name for name in rest[count:installed_end] if name}
        # What this release could still install, asked only about the names dpkg
        # said were absent -- see the probe.
        available = {name for name in rest[installed_end:] if name}
        missing, unavailable = package_gaps(entries, installed, available)
        return apt_packages(
            package_count=len(entries),
            missing=missing,
            unavailable=unavailable,
            missing_label=missing_label,
            clean_detail=clean_detail,
        )

    if name == "git_identity":
        user, email = args
        return git_identity(name=user, email=email)
    if name == "python_runtime":
        python3_present, pip_ok, venv_ok = args
        return python_runtime(
            python3_present=python3_present == "1",
            pip_ok=pip_ok == "1",
            venv_ok=venv_ok == "1",
        )
    if name == "owned_cli":
        (
            missing_label,
            timeout_label,
            owned_suffix,
            external_suffix,
            found,
            rc,
            ver,
            path,
            owned,
        ) = args
        return owned_cli(
            missing_label=missing_label,
            timeout_label=timeout_label,
            owned_suffix=owned_suffix,
            external_suffix=external_suffix,
            found=found == "1",
            rc=int(rc or 0),
            version=ver,
            path=path,
            owned=owned == "1",
        )
    if name == "monaspace_fonts":
        present, count, ver = args
        return monaspace_fonts(present=present == "1", count=count, version=ver)
    if name == "stow_targets":
        (missing,) = args
        return stow_targets(missing=int(missing or 0))
    if name == "wsl_conf":
        present, systemd, append_windows_path = args
        return wsl_conf(
            present=present == "1",
            systemd=systemd == "1",
            append_windows_path=append_windows_path == "1",
        )

    raise ValueError(f"unknown classification: {name}")


def main(argv: list[str] | None = None) -> int:
    import sys

    for line in sys.stdin:
        fields = [
            field.replace(NEWLINE_SUB, "\n")
            for field in line.rstrip("\n").split(FIELD_SEP)
        ]
        print(classify(fields))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
