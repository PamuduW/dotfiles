"""Read native runtime publisher metadata without installing any software."""

from __future__ import annotations

import gzip
import hashlib
import io
import json
import re
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

from catalog_discovery import DiscoveryError, public_response_stream
from software_catalog import _object

_HOSTS = frozenset(
    {
        "nodejs.org",
        "go.dev",
        "googlechromelabs.github.io",
        "downloads.claude.ai",
        "antigravity-cli-auto-updater-974169037036.us-central1.run.app",
    }
)
_HOSTS = _HOSTS | {"download.docker.com", "hub.docker.com"}
_VERSION = re.compile(r"(?:v|go)([0-9]+\.[0-9]+\.[0-9]+)\Z")


class _RuntimeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        _public_url(newurl)
        if urlsplit(newurl).netloc != urlsplit(request.full_url).netloc:
            raise DiscoveryError("runtime metadata redirected to a different publisher")
        return super().redirect_request(request, fp, code, message, headers, newurl)


def _public_url(url):
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.netloc not in _HOSTS or parsed.fragment:
        raise DiscoveryError("runtime metadata requires its canonical public publisher")


def fetch_public(url):
    _public_url(url)
    request = urllib.request.Request(
        url, headers={"User-Agent": "dotfiles-software-catalog/1"}
    )
    for attempt in range(3):
        try:
            opener = urllib.request.build_opener(
                urllib.request.ProxyHandler({}), _RuntimeRedirect()
            )
            with opener.open(request, timeout=30) as response:
                _public_url(response.url)
                raw = public_response_stream(response).read(8_388_609)
                if len(raw) > 8_388_608:
                    raise DiscoveryError("runtime metadata exceeds its size limit")
                return raw
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt == 2:
                raise DiscoveryError(
                    "runtime metadata unavailable after bounded retries"
                ) from error
            time.sleep(attempt + 1)
    raise DiscoveryError("runtime metadata unavailable")


def chrome_checksum(url):
    if not re.fullmatch(
        r"https://storage\.googleapis\.com/chrome-for-testing-public/[0-9]+(?:\.[0-9]+){3}/linux64/chrome-headless-shell-linux64\.zip",
        url,
    ):
        raise DiscoveryError(
            "Chrome artifact differs from its exact public publisher path"
        )
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "dotfiles-software-catalog/1",
            "Accept-Encoding": "identity",
        },
    )
    for attempt in range(3):
        try:
            opener = urllib.request.build_opener(
                urllib.request.ProxyHandler({}), _RuntimeRedirect()
            )
            with opener.open(request, timeout=30) as response:
                if (
                    response.url != url
                    or response.headers.get("Content-Encoding", "identity")
                    != "identity"
                ):
                    raise DiscoveryError("Chrome artifact URL or encoding changed")
                digest, size = hashlib.sha256(), 0
                while chunk := response.read(1_048_576):
                    size += len(chunk)
                    if size > 268_435_456:
                        raise DiscoveryError(
                            "Chrome artifact exceeds its download limit"
                        )
                    digest.update(chunk)
                if not size:
                    raise DiscoveryError("Chrome artifact download was empty")
                return digest.hexdigest()
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt == 2:
                raise DiscoveryError(
                    "Chrome artifact unavailable after bounded retries"
                ) from error
            time.sleep(attempt + 1)
    raise DiscoveryError("Chrome artifact unavailable")


def _releases(raw):
    try:
        releases = json.loads(raw, object_pairs_hook=_object)
    except (ValueError, UnicodeError) as error:
        raise DiscoveryError(
            "runtime release metadata is not unique-key JSON"
        ) from error
    if (
        not isinstance(releases, list)
        or not releases
        or not all(isinstance(row, dict) for row in releases)
    ):
        raise DiscoveryError("runtime release metadata lacks its release list")
    return releases


def _latest(releases, predicate):
    choices = []
    for row in releases:
        match = _VERSION.fullmatch(str(row.get("version", "")))
        if match and predicate(row):
            choices.append((tuple(map(int, match[1].split("."))), row))
    if not choices:
        raise DiscoveryError("publisher has no qualifying stable runtime release")
    selected = max(version for version, _row in choices)
    rows = [row for version, row in choices if version == selected]
    if len(rows) != 1:
        raise DiscoveryError("publisher returned duplicate runtime releases")
    return rows[0]


class RuntimeCandidateResolver:
    def __init__(
        self,
        *,
        fetch=fetch_public,
        checksum=chrome_checksum,
        uv=None,
        uv_version=None,
        locks=None,
    ):
        self.fetch = fetch
        self.checksum = checksum
        self.uv, self.uv_version, self.locks = uv, uv_version, locks
        self.docker_rows = None

    def resolve(self, identity, discovery, target):
        if target != "linux-amd64":
            raise DiscoveryError(
                "native runtime discovery currently qualifies Linux AMD64 only"
            )
        if identity == "nodejs" and discovery == {
            "provider": "node-lts",
            "locator": "nodejs.org",
        }:
            return self._node()
        if identity == "go" and discovery == {
            "provider": "go-stable",
            "locator": "go.dev",
        }:
            return self._go()
        if identity == "chrome_headless" and discovery == {
            "provider": "chrome-for-testing",
            "locator": "Stable",
        }:
            return self._chrome()
        if identity == "claude_cli" and discovery == {
            "provider": "claude-native",
            "locator": "stable",
            "auto_update_env": "DISABLE_UPDATES",
            "auto_update_value": "1",
        }:
            return self._claude()
        if identity == "antigravity_cli" and discovery == {
            "provider": "antigravity-manifest",
            "locator": "linux_amd64",
            "auto_update_env": "AGY_CLI_DISABLE_AUTO_UPDATE",
            "auto_update_value": "true",
        }:
            return self._antigravity()
        if identity == "graphify_cli" and discovery == {
            "provider": "pypi-tool",
            "locator": "graphifyy",
            "binary": "graphify",
        }:
            return self._graphify()
        if identity == "portainer" and discovery == {
            "provider": "portainer-lts",
            "locator": "portainer/portainer-ce",
        }:
            return self._portainer()
        package = discovery.get("locator", "")
        if identity == "docker." + package and discovery == {
            "provider": "docker-apt",
            "locator": package,
            "channel": "noble",
        }:
            return self._docker(package)
        raise DiscoveryError(
            "native runtime publisher identity differs from its declared policy"
        )

    def _node(self):
        row = _latest(
            _releases(self.fetch("https://nodejs.org/dist/index.json")),
            lambda item: isinstance(item.get("lts"), str) and bool(item["lts"]),
        )
        if "linux-x64" not in row.get("files", []):
            raise DiscoveryError("selected Node LTS lacks its Linux AMD64 archive")
        version = row["version"][1:]
        filename = f"node-v{version}-linux-x64.tar.xz"
        base = f"https://nodejs.org/dist/v{version}/"
        try:
            checksums = self.fetch(base + "SHASUMS256.txt").decode("ascii")
        except UnicodeError as error:
            raise DiscoveryError("Node checksums are not ASCII") from error
        matches = [
            match[1]
            for line in checksums.splitlines()
            if (
                match := re.fullmatch(
                    r"([0-9a-f]{64})\s+\*?" + re.escape(filename), line
                )
            )
        ]
        if len(matches) != 1:
            raise DiscoveryError("Node archive lacks one exact publisher checksum")
        return {
            "version": version,
            "url": base + filename,
            "digest": "sha256:" + matches[0],
            "archive": "tar.xz",
            "binary": f"node-v{version}-linux-x64/bin/node",
        }

    def _go(self):
        row = _latest(
            _releases(self.fetch("https://go.dev/dl/?mode=json")),
            lambda item: item.get("stable") is True,
        )
        version = row["version"][2:]
        filename = f"go{version}.linux-amd64.tar.gz"
        files = row.get("files", [])
        if not isinstance(files, list) or not all(
            isinstance(item, dict) for item in files
        ):
            raise DiscoveryError("Go metadata lacks its file list")
        selected = [item for item in files if item.get("filename") == filename]
        if len(selected) != 1:
            raise DiscoveryError("Go archive is missing or duplicated")
        artifact = selected[0]
        if (
            artifact.get("version") != row["version"]
            or artifact.get("os") != "linux"
            or artifact.get("arch") != "amd64"
            or artifact.get("kind") != "archive"
            or not re.fullmatch(r"[0-9a-f]{64}", str(artifact.get("sha256", "")))
        ):
            raise DiscoveryError(
                "Go archive identity or checksum differs from its release"
            )
        return {
            "version": version,
            "url": "https://go.dev/dl/" + filename,
            "digest": "sha256:" + artifact["sha256"],
            "archive": "tar.gz",
            "binary": "go/bin/go",
        }

    def _chrome(self):
        try:
            document = json.loads(
                self.fetch(
                    "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json"
                ),
                object_pairs_hook=_object,
            )
            row = document["channels"]["Stable"]
            version = row["version"]
            if row["channel"] != "Stable" or not re.fullmatch(
                r"[0-9]+(?:\.[0-9]+){3}", version
            ):
                raise DiscoveryError("Chrome metadata lacks an exact stable version")
            selected = [
                item
                for item in row["downloads"]["chrome-headless-shell"]
                if item.get("platform") == "linux64"
            ]
            url = f"https://storage.googleapis.com/chrome-for-testing-public/{version}/linux64/chrome-headless-shell-linux64.zip"
            if len(selected) != 1 or selected[0].get("url") != url:
                raise DiscoveryError(
                    "Chrome metadata lacks its canonical Linux AMD64 headless bundle"
                )
            digest = self.checksum(url)
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise DiscoveryError("Chrome artifact lacks SHA256 integrity")
            return {
                "version": version,
                "url": url,
                "digest": "sha256:" + digest,
                "archive": "zip",
                "binary": "chrome-headless-shell-linux64/chrome-headless-shell",
            }
        except (KeyError, TypeError, ValueError, UnicodeError) as error:
            raise DiscoveryError("Chrome publisher metadata is malformed") from error

    def _claude(self):
        base = "https://downloads.claude.ai/claude-code-releases"
        try:
            version = self.fetch(base + "/stable").decode("ascii").strip()
            if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
                raise DiscoveryError(
                    "Claude channel did not return an exact release version"
                )
            manifest = json.loads(
                self.fetch(f"{base}/{version}/manifest.json"), object_pairs_hook=_object
            )
            checksum = manifest["platforms"]["linux-x64"]["checksum"]
            if manifest["version"] != version or not re.fullmatch(
                r"[0-9a-f]{64}", checksum
            ):
                raise DiscoveryError(
                    "Claude platform checksum or manifest version differs"
                )
            return {
                "version": version,
                "url": f"{base}/{version}/linux-x64/claude",
                "digest": "sha256:" + checksum,
                "archive": "raw",
                "binary": "claude",
            }
        except (UnicodeError, ValueError, KeyError, TypeError) as error:
            raise DiscoveryError("Claude publisher metadata is malformed") from error

    def _antigravity(self):
        endpoint = "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json"
        try:
            manifest = json.loads(self.fetch(endpoint), object_pairs_hook=_object)
            version, url, checksum = (
                manifest[field] for field in ("version", "url", "sha512")
            )
            parsed = urlsplit(url)
            if (
                not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
                or parsed.scheme != "https"
                or parsed.netloc != "storage.googleapis.com"
                or not parsed.path.startswith("/antigravity-public/")
                or not parsed.path.endswith(".tar.gz")
                or any(part in {".", ".."} for part in parsed.path.split("/"))
                or parsed.query
                or parsed.fragment
                or not re.fullmatch(r"[0-9a-fA-F]{128}", checksum)
            ):
                raise DiscoveryError(
                    "Antigravity metadata differs from its public release identity"
                )
            return {
                "version": version,
                "url": url,
                "digest": "sha512:" + checksum.lower(),
                "archive": "tar.gz",
                "binary": "antigravity",
            }
        except (UnicodeError, ValueError, KeyError, TypeError) as error:
            raise DiscoveryError(
                "Antigravity publisher metadata is malformed"
            ) from error

    def _graphify(self):
        from catalog_dependencies import generate_python_lock, validate_python_lock

        if self.uv is None or self.uv_version is None or self.locks is None:
            raise DiscoveryError(
                "Graphify discovery requires selected approved uv and lock output"
            )
        raw = generate_python_lock(
            "graphifyy\n",
            uv=self.uv,
            uv_version=self.uv_version,
            python_version="3.12",
            target="linux-amd64",
        )
        packages = validate_python_lock(raw)
        if "graphifyy" not in packages:
            raise DiscoveryError("Graphify dependency closure lacks its root package")
        digest = hashlib.sha256(raw).hexdigest()
        path = f"locks/python/graphify-py312-linux-amd64-{digest}.txt"
        self.locks[path] = raw
        return {
            "version": packages["graphifyy"]["version"],
            "package": "graphifyy",
            "archive": "python-lock",
            "binary": "graphify",
            "lock": path,
            "digest": "sha256:" + digest,
        }

    def _docker(self, package):
        source = (
            Path(__file__).resolve().parents[1] / "lib/managed_tool_state.sh"
        ).read_text()
        match = re.search(r"^DOCKER_VENDOR_PACKAGES=\(([^)]*)\)", source, re.MULTILINE)
        if match is None or package not in match[1].split():
            raise DiscoveryError(
                "Docker package is outside the owning vendor package registry"
            )
        if self.docker_rows is None:
            raw = self.fetch(
                "https://download.docker.com/linux/ubuntu/dists/noble/stable/binary-amd64/Packages.gz"
            )
            self.docker_rows = _docker_records(raw)
        selected = None
        for row in self.docker_rows:
            if row.get("Package") != package or row.get("Architecture") != "amd64":
                continue
            _docker_identity(row, package)
            if selected is None or _debian_newer(row["Version"], selected["Version"]):
                selected = row
            elif row["Version"] == selected["Version"] and row != selected:
                raise DiscoveryError(
                    "Docker index duplicates a version with different package metadata"
                )
        if selected is None:
            raise DiscoveryError(
                "Docker stable repository lacks the exact package/architecture"
            )
        return {
            "version": selected["Version"],
            "package": package,
            "archive": "deb",
            "url": "https://download.docker.com/linux/ubuntu/" + selected["Filename"],
            "digest": "sha256:" + selected["SHA256"],
        }

    def _portainer(self):
        base = "https://hub.docker.com/v2/repositories/portainer/portainer-ce/tags"
        root = _json_object(self.fetch(base + "/lts"))
        digest = _image_digest(root, required=True)
        matches = []
        for page in range(1, 11):
            tags = _json_object(
                self.fetch(base + f"?page_size=100&page={page}&ordering=last_updated")
            )
            rows = tags.get("results")
            if not isinstance(rows, list) or not all(
                isinstance(row, dict) for row in rows
            ):
                raise DiscoveryError("Portainer tag metadata is malformed")
            for row in rows:
                version = row.get("name", "")
                if (
                    isinstance(version, str)
                    and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
                    and _image_digest(row) == digest
                ):
                    matches.append(version)
            if matches or tags.get("next") is None:
                break
        if not matches:
            raise DiscoveryError(
                "Portainer LTS digest has no exact matching release tag within bounded discovery"
            )
        version = max(matches, key=lambda value: tuple(map(int, value.split("."))))
        return {
            "version": version,
            "package": "portainer/portainer-ce",
            "archive": "oci",
            "digest": digest,
            "url": "https://registry-1.docker.io/v2/portainer/portainer-ce/manifests/"
            + digest,
        }


def _json_object(raw):
    try:
        data = json.loads(raw, object_pairs_hook=_object)
    except (ValueError, UnicodeError) as error:
        raise DiscoveryError("publisher metadata is not unique-key JSON") from error
    if not isinstance(data, dict):
        raise DiscoveryError("publisher metadata is not an object")
    return data


def _image_digest(row, *, required=False):
    images = row.get("images")
    if not isinstance(images, list) or not all(
        isinstance(image, dict) for image in images
    ):
        raise DiscoveryError("OCI tag lacks its image descriptor list")
    selected = [
        image
        for image in images
        if image.get("architecture") == "amd64" and image.get("os") == "linux"
    ]
    if not selected and not required:
        return None
    if len(selected) != 1 or not re.fullmatch(
        r"sha256:[0-9a-f]{64}", str(selected[0].get("digest", ""))
    ):
        raise DiscoveryError("OCI tag lacks one exact Linux AMD64 image digest")
    return selected[0]["digest"]


def _docker_records(raw):
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream:
            decoded = stream.read(16_777_217)
        if len(decoded) > 16_777_216:
            raise DiscoveryError("Docker package index exceeds its decoded size limit")
        records = []
        for stanza in decoded.decode().split("\n\n"):
            fields = {}
            for line in stanza.splitlines():
                if not line or line[0].isspace():
                    continue
                name, separator, value = line.partition(": ")
                if not separator or name in fields:
                    raise DiscoveryError(
                        "Docker package index contains malformed or duplicate fields"
                    )
                fields[name] = value
            if fields:
                records.append(fields)
        return records
    except (OSError, EOFError, UnicodeError) as error:
        raise DiscoveryError(
            "Docker package index is not valid bounded gzip text"
        ) from error


def _docker_identity(row, package):
    if (
        not re.fullmatch(r"[0-9][A-Za-z0-9.+:~_-]*", row.get("Version", ""))
        or not re.fullmatch(r"[0-9a-f]{64}", row.get("SHA256", ""))
        or not re.fullmatch(
            r"dists/noble/pool/stable/amd64/"
            + re.escape(package)
            + r"_[A-Za-z0-9_.+~:%-]+\.deb",
            row.get("Filename", ""),
        )
    ):
        raise DiscoveryError(
            "Docker package lacks an exact version, publisher filename or checksum"
        )


def _debian_newer(left, right):
    try:
        result = subprocess.run(
            ["/usr/bin/dpkg", "--compare-versions", left, "gt", right],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
            timeout=5,
        )
        if result.returncode not in (0, 1):
            raise DiscoveryError(
                "Docker publisher returned an invalid Debian package version"
            )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError) as error:
        raise DiscoveryError(
            "Debian package version comparison is unavailable"
        ) from error
