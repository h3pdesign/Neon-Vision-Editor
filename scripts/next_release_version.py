#!/usr/bin/env python3
"""Print the next stable release tag from tags reachable at HEAD."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
TAG_PATTERN = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def stable_tags() -> list[tuple[int, int, int]]:
    result = subprocess.run(
        ["git", "tag", "--merged", "HEAD", "--list", "v*"],
        cwd=ROOT, text=True, capture_output=True, check=True,
    )
    versions = []
    for tag in result.stdout.splitlines():
        match = TAG_PATTERN.fullmatch(tag.strip())
        if match:
            versions.append(tuple(int(part) for part in match.groups()))
    if not versions:
        raise ValueError("No stable vMAJOR.MINOR.PATCH tag is reachable from HEAD.")
    return versions


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Print the next stable Neon Vision Editor release tag.")
    bump = parser.add_mutually_exclusive_group()
    bump.add_argument("--patch", action="store_true", help="Increment PATCH (default; capped at .9).")
    bump.add_argument("--minor", action="store_true", help="Increment MINOR and reset PATCH to 0.")
    bump.add_argument("--major", action="store_true", help="Increment MAJOR and reset MINOR/PATCH to 0.")
    parser.add_argument("--patch-cap", type=int, default=9, help="Highest PATCH before --patch refuses rollover (default: 9).")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.patch_cap < 0:
        raise ValueError("--patch-cap must be zero or greater.")
    major, minor, patch = max(stable_tags())
    if args.major:
        next_version = (major + 1, 0, 0)
    elif args.minor:
        next_version = (major, minor + 1, 0)
    else:
        if patch >= args.patch_cap:
            raise ValueError(f"v{major}.{minor}.{patch} reached the patch cap; use --minor for v{major}.{minor + 1}.0.")
        next_version = (major, minor, patch + 1)
    print("v{}.{}.{}".format(*next_version))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
