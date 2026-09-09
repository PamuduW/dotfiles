"""One Python process per command.

ADR-0001's end state: Bash gathers the raw facts and a single Python invocation
classifies, checks and renders. A `dotfiles status` used to spawn three -- one
to read the probe results, one to ask the repository where it stands, one to
draw the table -- at 17-21 ms each. This is one interpreter answering all three,
so the Bash callers keep owning what they say and when while the process count
stops growing with the number of things Python does.

Protocol, deliberately small enough to read in one sitting:

    request   a verb line, its arguments separated by \x1f, then payload lines,
              then a line holding \x03
    response  output lines, then a line holding \x03

Strictly one request at a time. Nothing here is concurrent, and the caller never
issues a request from a parallel probe -- the collector resolves classifications
after its probes have been waited on.

A verb that fails answers with no output and a terminator rather than a stack
trace: every caller has a Bash path for the machine that has no runtime yet, and
the empty answer routes it there instead of half-drawing a table.
"""

from __future__ import annotations

import sys
from pathlib import Path

import probe_classify
import probes
import render_report
import repo_status

END = "\x03"
FS = "\x1f"


def _read_payload() -> list[str]:
    """Read to the terminator with `readline`, never by iterating the file.

    Iteration reads ahead into a buffer and would block until it filled, which
    on a request/response pipe is a hang rather than a slow answer.
    """
    payload: list[str] = []
    while True:
        line = sys.stdin.readline()
        if not line:
            return payload
        line = line.rstrip("\n")
        if line == END:
            return payload
        payload.append(line)


def _classify(payload: list[str]) -> None:
    for line in payload:
        fields = [
            field.replace(probe_classify.NEWLINE_SUB, "\n")
            for field in line.split(probe_classify.FIELD_SEP)
        ]
        print(probe_classify.classify(fields))


def _probe(args: list[str], payload: list[str]) -> None:
    """Component probes that ask the filesystem, answered in this process.

    One call for all of them rather than a subshell each: they are cheap
    individually and there is nothing to overlap. The ones that run a version
    command stay in Bash, where they are already run in parallel.
    """
    repo = Path(args[0]) if args else Path.cwd()
    for key in payload:
        if not key:
            continue
        print(f"{key}{FS}{probes.probe(key, repo)}")


def _repo_status(args: list[str]) -> None:
    repo, label, timeout = args[0], args[1], float(args[2] or repo_status.DEFAULT_TIMEOUT_SECONDS)
    print(f"{label}|{repo_status.check(Path(repo), timeout=timeout)}")


def serve() -> int:
    while True:
        header = sys.stdin.readline()
        if not header:
            return 0
        header = header.rstrip("\n")
        if not header:
            continue
        verb, *args = header.split(FS)
        payload = _read_payload()
        try:
            if verb == "classify":
                _classify(payload)
            elif verb == "render":
                render_report.main(args, rows=payload)
            elif verb == "probe":
                _probe(args, payload)
            elif verb == "repo_status":
                _repo_status(args)
            elif verb == "ping":
                print("ok")
        except Exception:  # noqa: BLE001 -- the caller's fallback is the handler
            pass
        print(END, flush=True)


if __name__ == "__main__":
    raise SystemExit(serve())
