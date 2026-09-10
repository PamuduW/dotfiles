"""Interrogation, in Python.

ADR-0001 stage two, the half deliberately left until last. The readings moved
first because they are pure and every state is testable without a machine in it;
asking the machine is the half that needs one, which is why the amendment says
to leave it longer.

What is here is the subset with the best oracle: probes that read the
filesystem and Git configuration, where a temporary HOME reproduces every state
exactly. Nothing here spawns a version command or queries a package manager --
those stay in Bash until they have an oracle better than "it agreed on this
machine today".

The Bash probes in scripts/lib/components/probes.sh remain, and not as
scaffolding: `python3` belongs to the optional `python` component, so a first
setup that deselects it prints its install summary with no interpreter at all.
They are the pre-runtime path, exactly as the Bash renderer is, and
tests/test_probe_interrogation_parity.sh runs both against the same fixtures and
compares.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import probe_classify

STOW_TARGETS = (
    ("{home}/.bashrc", "{repo}/bash/.bashrc"),
    ("{home}/.bash_aliases", "{repo}/bash/.bash_aliases"),
    ("{home}/.inputrc", "{repo}/readline/.inputrc"),
    ("{home}/bin/ex", "{repo}/bin/bin/ex"),
    ("{home}/bin/clip", "{repo}/bin/bin/clip"),
    ("{home}/bin/codex-rc", "{repo}/bin/bin/codex-rc"),
    ("{home}/bin/git", "{repo}/bin/bin/git"),
    ("{home}/bin/dotfiles", "{repo}/bin/bin/dotfiles"),
)


def _home() -> Path:
    return Path(os.environ.get("HOME", "~")).expanduser()


def monaspace_fonts() -> str:
    """A directory is not an installation; the .otf files are.

    The version comes from a `.version` file the installer drops, and its
    absence is normal on a hand-copied install -- hence the literal fallback
    rather than "unknown".
    """
    font_dir = _home() / ".local/share/fonts/monaspace"
    fonts = sorted(font_dir.glob("*.otf")) if font_dir.is_dir() else []
    if not fonts:
        return probe_classify.monaspace_fonts(present=False, count="", version="")
    version_file = font_dir / ".version"
    version = version_file.read_text(encoding="utf-8").strip() if version_file.is_file() else ""
    return probe_classify.monaspace_fonts(
        present=True, count=str(len(fonts)), version=version or "installed"
    )


def stow_targets(repo: Path) -> str:
    """A link into a different checkout counts as missing.

    `Path.resolve()` matches `readlink -f`: it follows the whole chain and does
    not require the target to exist, so a link left dangling by a moved checkout
    is counted rather than raising.
    """
    home = _home()
    missing = 0
    for target_pattern, expected_pattern in STOW_TARGETS:
        target = Path(target_pattern.format(home=home, repo=repo))
        expected = Path(expected_pattern.format(home=home, repo=repo))
        if not target.is_symlink() or target.resolve() != expected.resolve():
            missing += 1
    return probe_classify.stow_targets(missing=missing)


def _wsl_conf_has_setting(conf: Path, section: str, key: str, expected: str) -> bool:
    """The same reading as wsl_conf_has_setting: last match wins, comments are
    stripped from the value, and a key outside its section does not count."""
    found = False
    current = ""
    try:
        lines = conf.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped[1:-1]
            continue
        if current != section or "=" not in line:
            continue
        name, _, value = line.partition("=")
        for comment in ("#", ";"):
            index = value.find(comment)
            if index != -1:
                value = value[:index]
        if name.strip() == key and value.strip() == expected:
            found = True
    return found


def wsl_conf() -> str:
    conf = Path(os.environ.get("DOTFILES_WSL_CONF", "/etc/wsl.conf"))
    present = conf.is_file()
    return probe_classify.wsl_conf(
        present=present,
        systemd=present and _wsl_conf_has_setting(conf, "boot", "systemd", "true"),
        append_windows_path=present
        and _wsl_conf_has_setting(conf, "interop", "appendWindowsPath", "true"),
    )


def _git_config(*args: str) -> str:
    try:
        done = subprocess.run(
            ["git", "config", "--global", *args],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return done.stdout.strip()


def git_identity() -> str:
    return probe_classify.git_identity(
        name=_git_config("user.name"), email=_git_config("user.email")
    )


def git_credential() -> str:
    return probe_classify.git_credential(
        helper=_git_config("--get-all", "credential.helper"),
        recurse=_git_config("--get", "submodule.recurse"),
        fetch=_git_config("--get", "fetch.recurseSubmodules"),
        push=_git_config("--get", "push.recurseSubmodules"),
        summary=_git_config("--get", "status.submoduleSummary"),
    )


PROBES = {
    "monaspace_fonts": lambda repo: monaspace_fonts(),
    "dotfiles": stow_targets,
    "wsl_conf": lambda repo: wsl_conf(),
    "git_identity": lambda repo: git_identity(),
    "git_credential": lambda repo: git_credential(),
}


def probe(key: str, repo: Path) -> str:
    return PROBES[key](repo)
