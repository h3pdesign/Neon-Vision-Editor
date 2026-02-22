#!/usr/bin/env python3
"""Automate README/CHANGELOG release docs updates.

Usage:
  scripts/prepare_release_docs.py v0.4.6
  scripts/prepare_release_docs.py v0.4.6 --date 2026-02-12
  scripts/prepare_release_docs.py 0.4.6 --date 2026-02-12
  scripts/prepare_release_docs.py v0.4.6 --check
"""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
CHANGELOG = ROOT / "CHANGELOG.md"
WELCOME_TOUR_SWIFT = ROOT / "Neon Vision Editor" / "UI" / "PanelsAndHelpers.swift"


def normalize_tag(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        raise ValueError("Tag cannot be empty.")
    return raw if raw.startswith("v") else f"v{raw}"


def read_text(path: pathlib.Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"Missing file: {path}")
    return path.read_text(encoding="utf-8")


def write_text(path: pathlib.Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def has_changelog_section(changelog: str, tag: str) -> bool:
    return re.search(rf"^## \[{re.escape(tag)}\] - \d{{4}}-\d{{2}}-\d{{2}}$", changelog, flags=re.M) is not None


def add_changelog_section(changelog: str, tag: str, date: str) -> str:
    heading = f"## [{tag}] - {date}"
    template = (
        f"{heading}\n\n"
        "### Added\n"
        "- TODO\n\n"
        "### Improved\n"
        "- TODO\n\n"
        "### Fixed\n"
        "- TODO\n\n"
    )
    first_release = re.search(r"^## \[", changelog, flags=re.M)
    if not first_release:
        return changelog.rstrip() + "\n\n" + template
    idx = first_release.start()
    return changelog[:idx] + template + changelog[idx:]


def extract_changelog_section(changelog: str, tag: str) -> str:
    pattern = re.compile(
        rf"^## \[{re.escape(tag)}\] - [^\n]*\n(?P<body>.*?)(?=^## \[|\Z)",
        flags=re.M | re.S,
    )
    match = pattern.search(changelog)
    if not match:
        raise ValueError(f"Could not find CHANGELOG section for {tag}")
    return match.group("body").strip()


def summarize_section(section_body: str, limit: int = 5) -> list[str]:
    bullets: list[str] = []
    for line in section_body.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            bullets.append(stripped)
    if not bullets:
        return ["- See CHANGELOG.md entry."]
    return bullets[:limit]


def extract_release_headings(changelog: str) -> list[str]:
    return re.findall(r"^## \[(v[^\]]+)\] - \d{4}-\d{2}-\d{2}$", changelog, flags=re.M)


def is_prerelease_tag(tag: str) -> bool:
    return "-" in tag


def previous_release_tag(changelog: str, tag: str) -> str | None:
    headings = extract_release_headings(changelog)
    if tag not in headings:
        return None
    idx = headings.index(tag)
    # For stable releases, skip prerelease tags when computing "since ...".
    # Example: v0.4.8 should show v0.4.7, not v0.4.4-beta.
    for candidate in headings[idx + 1 :]:
        if not is_prerelease_tag(tag) and is_prerelease_tag(candidate):
            continue
        return candidate
    return None


def swift_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def update_welcome_tour_release_page(swift_source: str, tag: str, bullets: list[str], prev_tag: str | None) -> str:
    if not bullets:
        bullet_lines = ['                "See CHANGELOG.md for details"']
    else:
        bullet_lines = [f'                "{swift_string(bullet[2:])}"' for bullet in bullets]

    if prev_tag:
        subtitle = f"Major changes since {prev_tag}:"
    else:
        subtitle = f"Highlights for {tag}:"

    new_block = (
        "        TourPage(\n"
        '            title: "What\u2019s New in This Release",\n'
        f'            subtitle: "{swift_string(subtitle)}",\n'
        "            bullets: [\n"
        + ",\n".join(bullet_lines)
        + "\n"
        "            ],\n"
        '            iconName: "sparkles.rectangle.stack",\n'
        "            colors: [Color(red: 0.40, green: 0.28, blue: 0.90), Color(red: 0.96, green: 0.46, blue: 0.55)],\n"
        "            toolbarItems: []\n"
        "        ),"
    )

    pattern = re.compile(
        r'        TourPage\(\n'
        r'            title: "What[^\n]*This Release",\n'
        r"            subtitle: [^\n]*\n"
        r"            bullets: \[\n"
        r".*?"
        r"            \],\n"
        r'            iconName: "sparkles\.rectangle\.stack",\n'
        r"            colors: \[Color\(red: 0\.40, green: 0\.28, blue: 0\.90\), Color\(red: 0\.96, green: 0\.46, blue: 0\.55\)\],\n"
        r"            toolbarItems: \[\]\n"
        r"        \),",
        flags=re.S,
    )

    if not pattern.search(swift_source):
        raise ValueError("Could not find Welcome Tour 'What's New' page block to update.")
    return pattern.sub(new_block, swift_source, count=1)


def upsert_readme_summary(readme: str, tag: str, bullets: list[str]) -> str:
    block = "### {} (summary)\n\n{}\n\n".format(tag, "\n".join(bullets))
    header = "## Changelog\n\n"
    if header not in readme:
        raise ValueError("README missing '## Changelog' section")

    # Remove existing summary for the same tag first.
    same_tag_pattern = re.compile(
        rf"^### {re.escape(tag)} \(summary\)\n\n.*?(?=^### |\Z)",
        flags=re.M | re.S,
    )
    readme = same_tag_pattern.sub("", readme)

    insert_at = readme.index(header) + len(header)
    return readme[:insert_at] + block + readme[insert_at:]


def parse_version_key(tag: str) -> tuple[int, int, int, int, str]:
    """
    Sort key for tags like v1.2.3 and v1.2.3-beta.
    Stable releases sort above prereleases of the same numeric version.
    """
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?", tag)
    if not match:
        return (0, 0, 0, 0, tag)
    major = int(match.group(1))
    minor = int(match.group(2))
    patch = int(match.group(3))
    prerelease = match.group(4)
    stability_rank = 1 if prerelease is None else 0
    prerelease_text = prerelease or ""
    return (major, minor, patch, stability_rank, prerelease_text)


def sorted_latest_tags(tags: list[str], limit: int, ensure_tag: str | None = None) -> list[str]:
    unique: list[str] = []
    seen: set[str] = set()
    for tag in tags:
        if tag in seen:
            continue
        seen.add(tag)
        unique.append(tag)
    ordered = sorted(unique, key=parse_version_key, reverse=True)
    top = ordered[:limit]
    if ensure_tag and ensure_tag not in top:
        top = [ensure_tag] + top[: max(0, limit - 1)]
    return top


def rebuild_readme_changelog_summaries(readme: str, changelog: str, current_tag: str, limit: int = 3) -> str:
    header = "## Changelog\n\n"
    if header not in readme:
        raise ValueError("README missing '## Changelog' section")

    marker = "Full release history:"
    if marker not in readme:
        raise ValueError("README missing 'Full release history' marker")

    tags = extract_release_headings(changelog)
    top_tags = sorted_latest_tags(tags, limit=limit, ensure_tag=current_tag)

    blocks: list[str] = []
    for tag in top_tags:
        section = extract_changelog_section(changelog, tag)
        bullets = summarize_section(section, limit=5)
        blocks.append("### {} (summary)\n\n{}\n".format(tag, "\n".join(bullets)))

    new_summary_chunk = "\n".join(blocks) + "\n"

    changelog_start = readme.index(header) + len(header)
    marker_start = readme.index(marker, changelog_start)
    return readme[:changelog_start] + new_summary_chunk + readme[marker_start:]


def update_readme_release_refs(readme: str, tag: str) -> str:
    readme = re.sub(
        r"(?m)^> Latest release: \*\*.*\*\*$",
        f"> Latest release: **{tag}**",
        readme,
    )
    readme = re.sub(
        r"(?m)^- Latest release: \*\*.*\*\*$",
        f"- Latest release: **{tag}**",
        readme,
    )
    readme = re.sub(
        r"(?m)^- Tag: `.*`$",
        f"- Tag: `{tag}`",
        readme,
    )
    readme = re.sub(
        r"(?m)^git rev-parse --verify .*$",
        f"git rev-parse --verify {tag}",
        readme,
    )
    return readme


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare README and CHANGELOG for a release tag.")
    parser.add_argument("tag", help="Release tag, e.g. v0.4.6")
    parser.add_argument(
        "--date",
        help="Release date for a new CHANGELOG section (YYYY-MM-DD). Defaults to today.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify release docs are already up to date without writing files.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tag = normalize_tag(args.tag)
    release_date = args.date or dt.date.today().isoformat()

    original_changelog = read_text(CHANGELOG)
    changelog = original_changelog
    if not has_changelog_section(changelog, tag):
        changelog = add_changelog_section(changelog, tag, release_date)
        if not args.check:
            print(f"Added CHANGELOG template for {tag} ({release_date}).")
    elif not args.check:
        print(f"Found existing CHANGELOG section for {tag}.")

    section = extract_changelog_section(changelog, tag)
    bullets = summarize_section(section, limit=5)

    original_readme = read_text(README)
    readme = update_readme_release_refs(original_readme, tag)
    readme = upsert_readme_summary(readme, tag, bullets)
    readme = rebuild_readme_changelog_summaries(readme, changelog, tag, limit=3)

    original_welcome_src = read_text(WELCOME_TOUR_SWIFT)
    prev_tag = previous_release_tag(changelog, tag)
    welcome_src = update_welcome_tour_release_page(original_welcome_src, tag, bullets[:4], prev_tag)

    if args.check:
        outdated_files: list[str] = []
        if changelog != original_changelog:
            outdated_files.append(str(CHANGELOG))
        if readme != original_readme:
            outdated_files.append(str(README))
        if welcome_src != original_welcome_src:
            outdated_files.append(str(WELCOME_TOUR_SWIFT))
        if outdated_files:
            print(f"Release docs are not up to date for {tag}.", file=sys.stderr)
            print("Run: scripts/prepare_release_docs.py {}{}".format(tag, f" --date {release_date}" if args.date else ""), file=sys.stderr)
            print("Outdated files:", file=sys.stderr)
            for path in outdated_files:
                print(f"- {path}", file=sys.stderr)
            return 1
        print(f"Release docs are up to date for {tag}.")
        return 0

    write_text(CHANGELOG, changelog)
    write_text(README, readme)
    write_text(WELCOME_TOUR_SWIFT, welcome_src)
    print("Updated README release references and top 3 sorted summaries.")
    print(f"Updated Welcome Tour release page from CHANGELOG for {tag}.")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI friendly
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
