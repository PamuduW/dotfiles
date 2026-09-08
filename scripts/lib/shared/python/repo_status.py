"""Is this checkout behind its upstream?

Both tools report component state and neither reported whether the repository
itself had updates waiting. Dotfiles printed `git status -sb` and the words
"Remote freshness: unchecked"; Agentbot said nothing at all.

Knowing requires a fetch, so this one is bounded and degrades rather than hangs:
a network that is slow, absent or unauthenticated produces "unchecked", never a
stalled `status`. The fetch writes only to the remote-tracking refs — it never
touches the working tree, so `status` stays read-only in the sense that matters.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

DEFAULT_TIMEOUT_SECONDS = 5.0


def _git(repo: Path, *args: str, timeout: float) -> tuple[int, str]:
    try:
        done = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            # The caller's environment, plus one override. Replacing it
            # outright stripped HOME and git's own configuration, and in the
            # test harness it stripped the variables the fake git needs to
            # record what it was asked -- so a status that worked looked broken.
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )
    except (subprocess.TimeoutExpired, OSError):
        return 124, ""
    return done.returncode, done.stdout.strip()


def classify(*, upstream: str, fetched: bool, ahead: int, behind: int, asked: bool = True) -> str:
    """`detail|result` for a checkout whose counts are already known.

    Pure, so every state is testable without a repository in it.

    `asked` is whether a fetch was even attempted. Without one the counts are
    real but measured against the last fetch, which is stated rather than
    implied: reporting "up to date" from stale refs would be the one genuinely
    wrong answer here, the same shape as reading a refused `docker ps` as
    "container not found".
    """
    if not upstream:
        return "no upstream branch configured|check"
    if asked and not fetched:
        return f"{upstream}: unchecked (fetch failed or timed out)|skipped"

    suffix = "" if asked else " as of last fetch"
    if behind and ahead:
        return f"{upstream}: diverged, {ahead} ahead and {behind} behind{suffix}|check"
    if behind:
        return f"{upstream}: {behind} commit(s) behind{suffix} — run update|check"
    if ahead:
        return f"{upstream}: {ahead} commit(s) ahead, nothing to pull|ok"
    return f"{upstream}: up to date{suffix}|ok"


def check(
    repo: Path, *, timeout: float = DEFAULT_TIMEOUT_SECONDS, fetch: bool = False
) -> str:
    """`detail|result` for a checkout on disk.

    Local by default. `dotfiles status` is contractually strictly local -- it
    runs no fetch, makes no network call, and a test enforces both -- so the
    default answers from the refs already on disk and says the counts are as of
    the last fetch. Pass fetch=True where an authoritative answer is wanted and
    a network round trip is acceptable.
    """
    if not (repo / ".git").exists():
        return "not a Git checkout|skipped"

    rc, upstream = _git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}",
                        timeout=timeout)
    if rc != 0 or not upstream:
        return classify(upstream="", fetched=False, ahead=0, behind=0)

    fetched = False
    if fetch:
        fetch_rc, _ = _git(repo, "fetch", "--quiet", "--prune", timeout=timeout)
        fetched = fetch_rc == 0

    counts_rc, counts = _git(repo, "rev-list", "--left-right", "--count", "HEAD...@{upstream}",
                             timeout=timeout)
    ahead = behind = 0
    if counts_rc == 0 and counts:
        parts = counts.split()
        if len(parts) == 2:
            ahead, behind = int(parts[0]), int(parts[1])
    elif fetch:
        # Fetched fine but the count failed, so the answer is not known.
        fetched = False

    return classify(
        upstream=upstream, fetched=fetched, ahead=ahead, behind=behind, asked=fetch
    )


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--label", default="Repository")
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args(argv)
    print(
        f"{args.label}|{check(Path(args.repo), timeout=args.timeout, fetch=args.fetch)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
