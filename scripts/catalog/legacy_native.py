"""Validate frozen native-tool fixtures against the selected catalog inventory."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

ARCHIVES = frozenset({"raw", "tar", "tar.gz", "tar.xz", "zip"})
MANAGERS = frozenset({"nodejs", "npm", "go", "asdf"})


def select_native(snapshot):
    return {
        key: entry["targets"]["linux-amd64"]
        for key, entry in snapshot.data["components"].items()
        if entry["owner"] == "dotfiles"
        and entry["kind"] == "software"
        and key not in MANAGERS
        and entry["targets"].get("linux-amd64", {}).get("archive") in ARCHIVES
        and entry["targets"]["linux-amd64"].get("binary") != "fonts"
    }


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate legacy fixture field")
        result[key] = value
    return result


def load_fixture(snapshot, path):
    with path.open("rb") as stream:
        raw = stream.read(65_537)
    if len(raw) > 65_536:
        raise ValueError("legacy native fixture exceeds size limit")
    data = json.loads(raw, object_pairs_hook=_unique)
    if (
        not isinstance(data, dict)
        or set(data) != {"schema_version", "origin_run_id", "approved", "tools"}
        or type(data["schema_version"]) is not int
        or data["schema_version"] != 1
        or data["origin_run_id"] != 40477067865
        or data["approved"] is not False
        or not isinstance(data["tools"], dict)
        or not data["tools"]
        or set(data["tools"]) != set(select_native(snapshot))
    ):
        raise ValueError("frozen native fixture does not cover selected inventory")
    for key, item in data["tools"].items():
        if (
            not re.fullmatch(r"[a-z][a-z0-9_.-]*", key)
            or not isinstance(item, dict)
            or set(item) != {"archive", "binary", "digest", "url", "version"}
            or any(
                not isinstance(value, str)
                or any(ord(char) < 32 or ord(char) == 127 for char in value)
                for value in item.values()
            )
            or item["archive"] not in ARCHIVES
            or not re.fullmatch(r"[A-Za-z0-9_./+-]+", item["binary"])
            or Path(item["binary"]).is_absolute()
            or any(part in {".", ".."} for part in item["binary"].split("/"))
            or not re.fullmatch(r"[0-9][A-Za-z0-9.+_-]*", item["version"])
            or not re.fullmatch(
                r"sha256:[a-f0-9]{64}|sha512:[a-f0-9]{128}", item["digest"]
            )
        ):
            raise ValueError("unsafe legacy native artifact")
        url = urlsplit(item["url"])
        if (
            url.scheme != "https"
            or url.hostname
            not in {"github.com", "storage.googleapis.com", "downloads.claude.ai"}
            or url.username
            or url.password
            or url.port
            or url.query
            or url.fragment
        ):
            raise ValueError("unsupported legacy native publisher URL")
    return data["tools"]


def main():
    shared, context, fixture = map(Path, sys.argv[1:])
    sys.path.insert(0, str(shared / "scripts/lib/shared/python"))
    from catalog_context import load_qualification_context

    snapshot, _, _ = load_qualification_context(context)
    for key, item in sorted(load_fixture(snapshot, fixture).items()):
        print(
            "\t".join(
                [
                    key,
                    *(item[field] for field in ("url", "digest", "archive", "binary")),
                ]
            )
        )


if __name__ == "__main__":
    main()
