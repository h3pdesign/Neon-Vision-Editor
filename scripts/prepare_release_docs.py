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
        "### Hero Screenshot\n"
        "- ![TODO hero screenshot](docs/images/TODO-release-hero.png)\n\n"
        "### Why Upgrade\n"
        "- TODO\n"
        "- TODO\n"
        "- TODO\n\n"
        "### Highlights\n"
        "- TODO\n\n"
        "### Fixes\n"
        "- TODO\n\n"
        "### Breaking changes\n"
        "- None.\n\n"
        "### Migration\n"
        "- None.\n\n"
    )
    first_release = re.search(r"^## \[", changelog, flags=re.M)
    if not first_release:
        return changelog.rstrip() + "\n\n" + template
    idx = first_release.start()
    return changelog[:idx] + template + changelog[idx:]


def extract_changelog_section_meta(changelog: str, tag: str) -> tuple[str, str]:
    pattern = re.compile(
        rf"^## \[{re.escape(tag)}\] - (?P<date>\d{{4}}-\d{{2}}-\d{{2}})\n(?P<body>.*?)(?=^## \[|\Z)",
        flags=re.M | re.S,
    )
    match = pattern.search(changelog)
    if not match:
        raise ValueError(f"Could not find CHANGELOG section for {tag}")
    return (match.group("date"), match.group("body").strip())


def extract_changelog_section(changelog: str, tag: str) -> str:
    _, body = extract_changelog_section_meta(changelog, tag)
    return body


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


def extract_heading_bullets(section_body: str, heading: str, limit: int = 5) -> list[str]:
    bullets: list[str] = []
    in_heading = False
    target = f"### {heading}"
    for line in section_body.splitlines():
        stripped = line.strip()
        if stripped.startswith("### "):
            in_heading = stripped == target
            continue
        if in_heading and stripped.startswith("- "):
            bullets.append(stripped[2:].strip())
            if len(bullets) >= limit:
                break
    return bullets


def compact_bullets(items: list[str], default: str) -> str:
    if not items:
        return default
    return "; ".join(items)


def clean_release_cell_item(item: str) -> str:
    text = item.strip()
    text = re.sub(r"^(Added|Improved|Fixed|Fixes)\s+", "", text, flags=re.I)
    return text.rstrip(".")


def normalize_none_value(value: str, default: str) -> str:
    compact = value.strip().rstrip(".")
    if not compact:
        return default
    if compact.lower() in {"none", "none noted", "none required", "n/a", "not applicable"}:
        return default
    return value


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


def build_readme_release_row(tag: str, date: str, section_body: str) -> str:
    highlights_items = extract_heading_bullets(section_body, "Highlights", limit=4)
    if not highlights_items:
        highlights_items = extract_heading_bullets(section_body, "Added", limit=2) + extract_heading_bullets(
            section_body, "Improved", limit=1
        )
    fixes_items = extract_heading_bullets(section_body, "Fixes", limit=3)
    if not fixes_items:
        fixes_items = extract_heading_bullets(section_body, "Fixed", limit=3)

    highlights = compact_bullets([clean_release_cell_item(x) for x in highlights_items], "See CHANGELOG.")
    fixes = compact_bullets([clean_release_cell_item(x) for x in fixes_items], "None noted")
    breaking_items = extract_heading_bullets(section_body, "Breaking changes", limit=1)
    migration_items = extract_heading_bullets(section_body, "Migration", limit=1)

    breaking = normalize_none_value(breaking_items[0], "None noted") if breaking_items else "None noted"
    migration = normalize_none_value(migration_items[0], "None required") if migration_items else "None required"

    return (
        f"| [`{tag}`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/{tag}) | "
        f"{date} | {highlights} | {fixes} | {breaking} | {migration} |"
    )


def rebuild_readme_changelog_table(readme: str, changelog: str, current_tag: str, limit: int = 3) -> str:
    pattern = re.compile(
        r"(### Recent Releases \(At a glance\)\n\n"
        r"\| Version \| Date \| Highlights \| Fixes \| Breaking changes \| Migration \|\n"
        r"\|---\|---\|---\|---\|---\|---\|\n)"
        r"(?P<rows>.*?)(?=\n- Full release history:)",
        flags=re.S,
    )
    match = pattern.search(readme)
    if not match:
        raise ValueError("README missing changelog at-a-glance table block")

    tags = extract_release_headings(changelog)
    top_tags = sorted_latest_tags(tags, limit=limit, ensure_tag=current_tag)
    rows: list[str] = []
    for tag in top_tags:
        date, section = extract_changelog_section_meta(changelog, tag)
        rows.append(build_readme_release_row(tag, date, section))

    rows_block = "\n".join(rows) + "\n"
    return readme[: match.start("rows")] + rows_block + readme[match.end("rows") :]


def update_readme_latest_stable_line(readme: str, tag: str, changelog: str) -> str:
    date, _ = extract_changelog_section_meta(changelog, tag)
    readme = re.sub(
        r"(?m)^Latest stable: \*\*.*\*\* \(\d{4}-\d{2}-\d{2}\)$",
        f"Latest stable: **{tag}** ({date})",
        readme,
    )
    readme = re.sub(
        r"(?m)^> Last updated \(README\): \*\*\d{4}-\d{2}-\d{2}\*\* for latest release \*\*.*\*\*$",
        f"> Last updated (README): **{date}** for latest release **{tag}**",
        readme,
    )
    return readme


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
    readme = re.sub(
        r'(?m)^  <img alt="v[^"]+ Downloads" src="https://img\.shields\.io/github/downloads/h3pdesign/Neon-Vision-Editor/v[^/]+/total\?style=for-the-badge&label=v[^&]+&color=22C55E">$',
        (
            f'  <img alt="{tag} Downloads" '
            f'src="https://img.shields.io/github/downloads/h3pdesign/Neon-Vision-Editor/{tag}/total?style=for-the-badge&label={tag}&color=22C55E">'
        ),
        readme,
    )
    readme = re.sub(
        r"(?m)^(\| \*\*Stable\*\* \| [^|]+ \| \[GitHub Releases\]\(https://github\.com/h3pdesign/Neon-Vision-Editor/releases\) \| )\*\*v[^*]+\*\*( \| .*)$",
        rf"\1**{tag}**\2",
        readme,
    )
    return readme


def update_readme_whats_new_heading(readme: str, previous_tag: str | None, current_tag: str) -> str:
    if previous_tag:
        replacement = f"## What's New Since {previous_tag}"
    else:
        replacement = f"## What's New in {current_tag}"
    return re.sub(
        r"(?m)^## What's New Since [^\n]+$|^## What's New in [^\n]+$",
        replacement,
        readme,
    )


def parse_stable_semver(tag: str) -> tuple[int, int, int] | None:
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
    if not match:
        return None
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def update_readme_roadmap_windows(readme: str, tag: str) -> str:
    stable = parse_stable_semver(tag)
    if stable is None:
        return readme

    major, minor, patch = stable
    next_patch = patch + 1

    now_badge = (
        f'<img alt="Now" src="https://img.shields.io/badge/NOW-v{major}.{minor}.{patch}-22C55E?style=for-the-badge">'
    )
    next_badge = (
        f'<img alt="Next" src="https://img.shields.io/badge/NEXT-v{major}.{minor}.{next_patch}-F59E0B?style=for-the-badge">'
    )

    readme = re.sub(
        r'(?m)^  <img alt="Now" src="https://img\.shields\.io/badge/NOW-v[^"]+">$',
        f"  {now_badge}",
        readme,
    )
    readme = re.sub(
        r'(?m)^  <img alt="Next" src="https://img\.shields\.io/badge/NEXT-v[^"]+">$',
        f"  {next_badge}",
        readme,
    )
    readme = re.sub(
        r"(?m)^### Now \(v[^)]+\)$",
        f"### Now (v{major}.{minor}.{patch})",
        readme,
    )
    readme = re.sub(
        r"(?m)^### Next \(v[^)]+\)$",
        f"### Next (v{major}.{minor}.{next_patch})",
        readme,
    )
    return readme


def update_readme_compare_link(readme: str, prev_tag: str | None, current_tag: str) -> str:
    if not prev_tag:
        return readme
    return re.sub(
        r"(?m)^- Compare recent changes: \[v[^]]+\.\.\.v[^]]+\]\(https://github\.com/h3pdesign/Neon-Vision-Editor/compare/v[^)]+\)$",
        (
            f"- Compare recent changes: [{prev_tag}...{current_tag}]"
            f"(https://github.com/h3pdesign/Neon-Vision-Editor/compare/{prev_tag}...{current_tag})"
        ),
        readme,
    )


def pick_feature_spotlight(section_body: str) -> str:
    highlight_items = extract_heading_bullets(section_body, "Highlights", limit=8)
    preferred_keywords = ("share shot", "code snapshot", "camera.viewfinder", "snapshot")
    for item in highlight_items:
        lowered = item.lower()
        if any(keyword in lowered for keyword in preferred_keywords):
            cleaned = clean_release_cell_item(item)
            if cleaned:
                return cleaned
    for item in highlight_items:
        cleaned = clean_release_cell_item(item)
        if cleaned:
            return cleaned

    added_items = extract_heading_bullets(section_body, "Added", limit=8)
    for item in added_items:
        lowered = item.lower()
        if any(keyword in lowered for keyword in preferred_keywords):
            cleaned = clean_release_cell_item(item)
            if cleaned:
                return cleaned
    for item in added_items:
        cleaned = clean_release_cell_item(item)
        if cleaned:
            return cleaned

    fallback = summarize_section(section_body, limit=1)
    if fallback:
        return clean_release_cell_item(fallback[0][2:].strip())
    return "See CHANGELOG.md release highlights."


def update_readme_feature_spotlight(readme: str, tag: str, section_body: str) -> str:
    feature_text = pick_feature_spotlight(section_body).rstrip(".")
    badge = f'https://img.shields.io/badge/NEW%20FEATURE-{tag}-F97316?style=for-the-badge'
    featured_line = f"**Featured in {tag}:** {feature_text}."

    readme = re.sub(
        r'(?m)^  <img alt="New Feature Release" src="https://img\.shields\.io/badge/NEW%20FEATURE-v[^"]+">$',
        f'  <img alt="New Feature Release" src="{badge}">',
        readme,
    )
    readme = re.sub(
        r"(?m)^\*\*Featured in v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?:\*\* .*$",
        featured_line,
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
    prev_tag = previous_release_tag(changelog, tag)
    readme = update_readme_whats_new_heading(readme, prev_tag, tag)
    readme = update_readme_roadmap_windows(readme, tag)
    readme = update_readme_compare_link(readme, prev_tag, tag)
    readme = update_readme_feature_spotlight(readme, tag, section)
    readme = update_readme_latest_stable_line(readme, tag, changelog)
    readme = rebuild_readme_changelog_table(readme, changelog, tag, limit=3)

    original_welcome_src = read_text(WELCOME_TOUR_SWIFT)
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
    print("Updated README release references and top 3 release rows.")
    print(f"Updated Welcome Tour release page from CHANGELOG for {tag}.")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI friendly
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
