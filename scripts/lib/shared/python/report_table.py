"""Shared three-column report layout.

The Bash implementation of this same design lives beside it in
../tui/report_table.sh. ADR-0001 consolidates the two on Python, but Dotfiles
draws tables during first setup before it has installed a runtime, so the Bash
renderer is never fully retired -- the two coexist, and
agentbot/tests/test_renderer_parity.sh holds them byte-identical.

Deliberately pure: every function takes its width and its home directory as
arguments and returns a string. No environment reading, no printing, no colour.
Deciding how wide the terminal is and whether colour is wanted differs between
the two repositories and between interactive and piped output, so those choices
stay with the caller. That is also what makes this testable without a terminal.
"""

from __future__ import annotations

TableWidths = tuple[int, int, int]


def three_column_widths(columns: int) -> TableWidths:
    """Label, detail and result widths for a terminal this wide.

    Mirrors _rt_three_column_widths. The 8 subtracted covers the two leading
    spaces and the two ' | ' separators.
    """
    available = columns - 8
    label = max(10, available * 30 // 100)
    result = max(7, available * 14 // 100)
    detail = available - label - result
    return label, detail, result


def fit_line(text: str, max_len: int) -> str:
    """Truncate text with a trailing ellipsis. Mirrors _rt_fit_line."""
    if len(text) <= max_len:
        return text
    if max_len <= 1:
        return text[:max_len]
    return text[: max_len - 1] + "…"


def shorten_path(text: str, max_len: int, home: str) -> str:
    """Shorten a path, with the ellipsis in the middle. Mirrors _rt_shorten_path.

    A path's end identifies it, so trimming from the right would leave every
    path under one directory looking the same. Text keeps a trailing ellipsis;
    paths get a middle one.
    """
    home = home.rstrip("/")
    if text == home:
        text = "~"
    elif home and text.startswith(home + "/"):
        text = "~" + text[len(home) :]
    if max_len > 0 and len(text) > max_len:
        if max_len <= 8:
            return text[: max_len - 1] + "…"
        head = max_len // 2 - 1
        tail = max_len - head - 1
        return text[:head] + "…" + text[-tail:]
    return text


def fit_detail(text: str, max_len: int, home: str) -> str:
    """Fit the detail cell, choosing path or text treatment as the Bash row does."""
    if text.startswith(("/", "~")):
        return shorten_path(text, max_len, home)
    return fit_line(text, max_len)


def format_header(widths: TableWidths, headers: tuple[str, str, str]) -> tuple[str, str]:
    """The column line and the rule beneath it, uncoloured."""
    label_width, detail_width, result_width = widths
    h0, h1, h2 = (fit_line(h, w) for h, w in zip(headers, widths))
    columns = f"  {h0:<{label_width}} | {h1:<{detail_width}} | {h2:<{result_width}}"
    rule = f"  {'-' * label_width}-+-{'-' * detail_width}-+-{'-' * result_width}"
    return columns, rule


def format_row(widths: TableWidths, component: str, detail: str, result: str, home: str) -> str:
    """One uncoloured row. Every cell is padded, including the last.

    The trailing padding is load-bearing: Dotfiles pins every table line to the
    terminal width in test_update_and_upgrade_rows_keep_the_last_column_width.
    """
    label_width, detail_width, result_width = widths
    label = fit_line(component, label_width)
    detail_fit = fit_detail(detail, detail_width, home)
    result_fit = fit_line(result, result_width)
    return f"  {label:<{label_width}} | {detail_fit:<{detail_width}} | {result_fit:<{result_width}}"
