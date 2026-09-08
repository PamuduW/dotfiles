"""Render a whole three-column report: header, columns, rows, rollup.

A command-line front end to report_table.py, so a Bash caller can draw a table
in one process instead of one per row. ADR-0001 moves rendering to Python; this
is what the Bash side calls until the caller itself is Python.

Width and colour arrive as arguments. Deciding them differs between the two
repositories and between interactive and piped output, and the Bash callers
already have that logic -- duplicating those predicates here is exactly the
divergence this consolidation exists to remove.

Rows arrive on stdin as component|detail|result.
"""

from __future__ import annotations

import argparse
import os
import sys

import report_table as layout

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
ORANGE = "\033[38;5;208m"
RED = "\033[31m"
CYAN = "\033[36m"

# Mirrors status_color_result in ../tui/colors.sh. Both are pinned against each
# other by agentbot/tests/test_renderer_parity.sh.
_GREEN = {"ok", "installed", "configured", "linked", "up to date", "current", "applied", "read-only"}
_RED = {"missing", "failed", "error", "conflict"}
_YELLOW = {
    "check", "drift", "extra", "warn", "warning", "partial",
    "mutating", "applied-with-local-changes",
}
_CYAN = {"info", "dry-run", "preview"}


def color_result(result: str, *, color: bool) -> str:
    if not color:
        return result
    key = result.strip().lower()
    if key.startswith("skipped"):
        return f"{DIM}{result}{RESET}"
    for names, code in ((_GREEN, GREEN), (_RED, RED), (_YELLOW, YELLOW), (_CYAN, CYAN)):
        if key in names:
            return f"{code}{result}{RESET}"
    return result


def _paint(text: str, code: str, *, color: bool) -> str:
    return f"{code}{text}{RESET}" if color else text


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cols", type=int, default=80)
    parser.add_argument("--color", action="store_true")
    parser.add_argument("--title", default="")
    parser.add_argument("--breadcrumb", default="")
    parser.add_argument("--rollup", action="store_true")
    # Callers that already know their counts pass them. Doctor does: its
    # "nothing wrong" table holds one synthetic row whose result is `ok`, which
    # the derivation below would score as needing attention.
    parser.add_argument("--ok", type=int)
    parser.add_argument("--check", type=int)
    parser.add_argument("--miss", type=int)
    args = parser.parse_args(argv)

    color = args.color
    widths = layout.three_column_widths(args.cols)
    home = os.path.expanduser("~")

    out: list[str] = []
    if args.title:
        out.append("")
        out.append("  " + _paint(f"=== {args.title} ===", BOLD + ORANGE, color=color))
        if args.breadcrumb:
            out.append("  " + _paint(args.breadcrumb, DIM, color=color))
        out.append("")

    columns, rule = layout.format_header(widths, ("component", "detail", "result"))
    # The indent sits outside the escape, matching both the Bash renderer and
    # src/ui/table.py in the sibling. Bold-then-indent renders the same and
    # compares differently, which defeats the point of byte parity.
    out.append("  " + _paint(columns[2:], BOLD, color=color))
    out.append(rule)

    ok = check = miss = 0
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            continue
        component, _, rest = line.partition("|")
        detail, _, result = rest.partition("|")
        if result in {"installed", "configured"}:
            ok += 1
        elif result == "missing":
            miss += 1
        else:
            check += 1
        # Composed cell by cell rather than colouring a finished row: padding
        # must be measured on the text the operator sees, never on the escape
        # bytes that carry its colour.
        label_width, detail_width, result_width = widths
        label = layout.fit_line(component, label_width)
        detail_fit = layout.fit_detail(detail, detail_width, home)
        result_fit = layout.fit_line(result, result_width)
        painted = color_result(result_fit, color=color)
        padding = " " * (result_width - len(result_fit))
        out.append(
            f"  {label:<{label_width}} | {detail_fit:<{detail_width}} | {painted}{padding}"
        )

    if args.ok is not None:
        ok = args.ok
    if args.check is not None:
        check = args.check
    if args.miss is not None:
        miss = args.miss

    if args.rollup:
        out.append("")
        if miss == 0 and check == 0:
            out.append("  " + _paint(f"All {ok} component(s) look good.", GREEN, color=color))
        elif miss == 0:
            out.append(
                "  " + _paint(f"{ok} ok", GREEN, color=color)
                + ", " + _paint(f"{check} need attention", YELLOW, color=color) + "."
            )
        else:
            out.append(
                "  " + _paint(f"{ok} ok", GREEN, color=color)
                + ", " + _paint(f"{miss} missing", RED, color=color)
                + ", " + _paint(f"{check} need attention", YELLOW, color=color) + "."
            )

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
