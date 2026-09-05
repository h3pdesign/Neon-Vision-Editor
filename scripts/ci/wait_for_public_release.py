#!/usr/bin/env python3
"""Bounded publication readiness check followed by public asset checksum verification."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

ASSETS = {"Neon.Vision.Editor.app.zip", "Neon.Vision.Editor.app.dmg", "SHA256SUMS.txt"}


def ready(release: dict, tag: str) -> bool:
    uploaded = {a["name"] for a in release.get("assets", [])
                if a.get("size", 0) > 0 and a.get("state") == "uploaded"}
    return (release.get("tag_name") == tag and not release.get("draft", True)
            and not release.get("prerelease", True) and bool(release.get("published_at"))
            and ASSETS <= uploaded)


def verify_checksums(root: Path) -> None:
    entries = {}
    for line in (root / "SHA256SUMS.txt").read_text().splitlines():
        match = re.fullmatch(r"([a-fA-F0-9]{64})\s+\*?(.+)", line)
        if not match or match[2] not in ASSETS - {"SHA256SUMS.txt"} or match[2] in entries:
            raise ValueError("Invalid, unexpected or duplicate release checksum entry.")
        entries[match[2]] = match[1].lower()
    if set(entries) != ASSETS - {"SHA256SUMS.txt"}:
        raise ValueError("Release checksums do not cover both download artifacts.")
    for name, expected in entries.items():
        digest = hashlib.sha256()
        with (root / name).open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected:
            raise ValueError(f"Checksum mismatch for {name}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    tag = args.tag if args.tag.startswith("v") else "v" + args.tag
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag) or args.timeout < 1:
        parser.error("A stable version and positive timeout are required.")
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            result = subprocess.run(["gh", "api", f"repos/{{owner}}/{{repo}}/releases/tags/{tag}"],
                                    capture_output=True, text=True, timeout=min(30, max(1, deadline - time.monotonic())))
            if result.returncode == 0 and ready(json.loads(result.stdout), tag):
                break
        except (subprocess.TimeoutExpired, ValueError):
            pass
        time.sleep(min(10, max(0, deadline - time.monotonic())))
    else:
        raise SystemExit(f"Timed out waiting for the published {tag} ZIP, DMG and checksums.")
    with tempfile.TemporaryDirectory(prefix="nve-public-assets-") as temp:
        subprocess.run(["gh", "release", "download", tag, "--dir", temp,
                        "--pattern", "Neon.Vision.Editor.app.zip", "--pattern", "Neon.Vision.Editor.app.dmg",
                        "--pattern", "SHA256SUMS.txt"], check=True, timeout=300)
        verify_checksums(Path(temp))
    print(f"Verified public {tag} assets and checksums. Signing/notarization remain hosted release gates.")


if __name__ == "__main__":
    main()
