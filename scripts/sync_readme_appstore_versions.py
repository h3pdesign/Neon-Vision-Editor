#!/usr/bin/env python3
"""Sync README release/version lines with GitHub release and public App Store metadata."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
APP_STORE_ID = "6758950965"
APP_STORE_COUNTRY = "de"


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: pathlib.Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def normalize_tag(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("Version cannot be empty.")
    return value if value.startswith("v") else f"v{value}"


def parse_stable_semver(tag: str) -> tuple[int, int, int] | None:
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
    if not match:
        return None
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def next_patch_tag(tag: str) -> str:
    parsed = parse_stable_semver(tag)
    if parsed is None:
        return tag
    major, minor, patch = parsed
    return f"v{major}.{minor}.{patch + 1}"


def latest_readme_tag(readme: str) -> str:
    match = re.search(r"(?m)^> Latest release: \*\*(v[^*]+)\*\*$", readme)
    if not match:
        raise ValueError("README missing latest release status line.")
    return match.group(1)


def fetch_public_appstore_version(app_id: str, country: str, timeout: float) -> str:
    url = f"https://itunes.apple.com/lookup?id={app_id}&country={country}"
    request = urllib.request.Request(url, headers={"User-Agent": "NeonVisionReleaseSync/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Could not fetch App Store lookup metadata: {exc}") from exc

    results = payload.get("results") or []
    if not results:
        raise RuntimeError(f"App Store lookup returned no result for app id {app_id}.")
    version = str(results[0].get("version") or "").strip()
    if not version:
        raise RuntimeError("App Store lookup result did not include a version.")
    return normalize_tag(version)


def replace_required(pattern: str, replacement: str, text: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.M)
    if count != 1:
        raise ValueError(f"README replacement failed for {label}.")
    return updated


def sync_readme_versions(readme: str, latest_tag: str, public_store_tag: str, today: str) -> str:
    next_tag = next_patch_tag(latest_tag)
    store_is_current = public_store_tag == latest_tag

    status_parts = [
        f"Direct GitHub release: **{latest_tag}**",
        f"iOS App Store approved: **{public_store_tag}**",
        f"macOS App Store approved: **{public_store_tag}**",
    ]
    if not store_is_current:
        status_parts.insert(2, f"iOS App Store review pending: **{latest_tag}**")
        status_parts.append(f"macOS App Store review pending: **{latest_tag}**")

    availability_note = (
        "The direct GitHub release and public App Store listing are currently aligned."
        if store_is_current
        else (
            "The direct GitHub release is currently ahead of the App Store version. "
            "The App Store version may temporarily lag while updates are in Apple review."
        )
    )

    readme = replace_required(
        r"^> Direct GitHub release: \*\*[^*]+\*\*.*$",
        "> " + " / ".join(status_parts),
        readme,
        "top release status",
    )
    readme = replace_required(
        r"^> Next release target: \*\*[^*]+\*\*$",
        f"> Next release target: **{next_tag}**",
        readme,
        "next release target",
    )
    readme = replace_required(
        r"^> Last updated \(README\): \*\*\d{4}-\d{2}-\d{2}\*\* for latest release \*\*[^*]+\*\*$",
        f"> Last updated (README): **{today}** for latest release **{latest_tag}**",
        readme,
        "last updated status",
    )
    readme = replace_required(
        r"^The direct GitHub release(?: and public App Store listing are currently aligned\.| is currently ahead of the App Store version\. The App Store version may temporarily lag while updates are in Apple review\.)$",
        availability_note,
        readme,
        "download availability note",
    )
    readme = replace_required(
        r"^(\| \*\*Store\*\* \| iOS / iPadOS \| [^|]+ \| \[Neon Vision Editor on the App Store\]\(https://apps\.apple\.com/de/app/neon-vision-editor/id6758950965\) \| )\*\*[^*]+\*\*( \| ).*$",
        rf"\1**{public_store_tag}**\2Current public App Store listing |",
        readme,
        "iOS App Store table row",
    )
    readme = replace_required(
        r"^(\| \*\*Store\*\* \| macOS \| [^|]+ \| \[Neon Vision Editor on the App Store\]\(https://apps\.apple\.com/de/app/neon-vision-editor/id6758950965\) \| )\*\*[^*]+\*\*( \| ).*$",
        rf"\1**{public_store_tag}**\2Current public App Store listing |",
        readme,
        "macOS App Store table row",
    )
    readme = replace_required(
        r"^(\| \*\*Store Review\*\* \| iOS / iPadOS \| [^|]+ \| App Store Connect review \| )\*\*[^*]+\*\*( \| ).*$",
        rf"\1**{latest_tag}**\2{'Already public on App Store' if store_is_current else 'In Apple review'} |",
        readme,
        "iOS App Store review row",
    )
    readme = replace_required(
        r"^(\| \*\*Store Review\*\* \| macOS \| [^|]+ \| App Store Connect review \| )\*\*[^*]+\*\*( \| ).*$",
        rf"\1**{latest_tag}**\2{'Already public on App Store' if store_is_current else 'Pending Apple review'} |",
        readme,
        "macOS App Store review row",
    )
    readme = replace_required(
        r"^(\| \*\*Beta\*\* \| iOS / iPadOS / macOS \| [^|]+ \| \[TestFlight Invite\]\(https://testflight\.apple\.com/join/YWB2fGAP\) \| )\*\*[^*]+\*\*( \| ).*$",
        rf"\1**{latest_tag}**\2Early access builds for feedback; availability may vary by review state |",
        readme,
        "TestFlight table row",
    )
    return readme


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync README App Store and release version lines.")
    parser.add_argument("--tag", help="Latest GitHub release tag. Defaults to README latest release.")
    parser.add_argument("--store-version", help="Override public App Store version instead of fetching.")
    parser.add_argument("--country", default=APP_STORE_COUNTRY, help="App Store lookup country code.")
    parser.add_argument("--app-id", default=APP_STORE_ID, help="App Store numeric app id.")
    parser.add_argument("--timeout", type=float, default=20.0, help="App Store lookup timeout in seconds.")
    parser.add_argument("--check", action="store_true", help="Verify README is already synced.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    original = read_text(README)
    latest_tag = normalize_tag(args.tag) if args.tag else latest_readme_tag(original)
    public_store_tag = normalize_tag(args.store_version) if args.store_version else fetch_public_appstore_version(
        args.app_id,
        args.country,
        args.timeout,
    )
    today = dt.date.today().isoformat()
    updated = sync_readme_versions(original, latest_tag, public_store_tag, today)

    if args.check:
        if updated != original:
            print(
                f"README App Store versions are not synced (release={latest_tag}, public_store={public_store_tag}).",
                file=sys.stderr,
            )
            return 1
        print(f"README App Store versions are synced (release={latest_tag}, public_store={public_store_tag}).")
        return 0

    if updated != original:
        write_text(README, updated)
        print(f"Updated README App Store versions (release={latest_tag}, public_store={public_store_tag}).")
    else:
        print(f"README App Store versions already current (release={latest_tag}, public_store={public_store_tag}).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
