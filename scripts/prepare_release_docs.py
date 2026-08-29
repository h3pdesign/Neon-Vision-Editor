#!/usr/bin/env python3
"""Automate README/CHANGELOG release docs updates.

Usage:
  scripts/prepare_release_docs.py v0.4.6
  scripts/prepare_release_docs.py v0.4.6 --date 2026-02-12
  scripts/prepare_release_docs.py 0.4.6 --date 2026-02-12
  scripts/prepare_release_docs.py v0.4.6 --check
  scripts/prepare_release_docs.py v0.4.6 --preflight
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
CHANGELOG = ROOT / "CHANGELOG.md"
ARCHITECTURE = ROOT / "ARCHITECTURE.md"
WEBSITE = ROOT / "site" / "index.html"
CHANGELOG_PAGE = ROOT / "site" / "changelog.html"
LOCALIZED_WEBSITES = {
    "de": ROOT / "site" / "de" / "index.html",
    "da": ROOT / "site" / "da" / "index.html",
    "fr": ROOT / "site" / "fr" / "index.html",
    "es": ROOT / "site" / "es" / "index.html",
    "ja": ROOT / "site" / "ja" / "index.html",
    "zh-Hans": ROOT / "site" / "zh-Hans" / "index.html",
}
WELCOME_TOUR_SWIFT = ROOT / "Neon Vision Editor" / "UI" / "PanelsAndHelpers.swift"
WELCOME_TOUR_CARD_COUNT = 6
WELCOME_TOUR_CARD_TEXT_BUDGET = 126
RELEASE_TIMELINE_COUNT = 5

README_FEATURE_COVERAGE = """<!-- FEATURE_COVERAGE:START -->
### Current Feature Coverage

- **Editing utilities:** configurable iPhone/iPad keyboard actions, Copy Current Editor Reference, and Sort & Deduplicate Lines complement the regular save, find, undo, redo, and formatting commands.
- **Languages and structured documents:** Swift 6-ready highlighting includes TeX/LaTeX and Typst/CeTZ-aware editing; CSV/TSV, property lists, Apple crash reports, and recognized logs can switch between structured and raw-text views, and plain text can be transformed into validated JSON through an explicit AI-assisted action.
- **Project and preview workflows:** project-level Markdown/PDF cards reuse the project index for bounded excerpts and thumbnails, while Markdown, HTML, SVG, PDF, and PNG previews remain integrated with the editor.
- **macOS integration:** the embedded Quick Look extension previews supported Markdown and source files in Finder, and detached Markdown previews can use the same glass treatment without changing editor content.
{latest_additions}
<!-- FEATURE_COVERAGE:END -->"""


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


def replace_or_insert_managed_block(
    content: str,
    *,
    start_marker: str,
    end_marker: str,
    replacement: str,
    insert_before: str,
) -> str:
    start_count = content.count(start_marker)
    end_count = content.count(end_marker)
    if start_count != end_count or start_count > 1:
        raise ValueError(f"Managed documentation markers are unbalanced: {start_marker} / {end_marker}")
    if start_count == 1:
        pattern = re.compile(
            rf"{re.escape(start_marker)}.*?{re.escape(end_marker)}",
            flags=re.S,
        )
        return pattern.sub(replacement, content, count=1)
    anchor = content.find(insert_before)
    if anchor < 0:
        raise ValueError(f"Could not insert managed documentation block before: {insert_before.strip()}")
    return content[:anchor] + replacement + "\n\n" + content[anchor:]


def readme_feature_coverage(changelog: str, tag: str) -> str:
    _, section = extract_changelog_section_meta(changelog, tag)
    highlights = extract_heading_bullets(section, "Highlights", limit=6)
    if highlights:
        latest = "; ".join(item.rstrip(".") for item in highlights) + "."
    else:
        latest = "See the current release entry in `CHANGELOG.md`."
    return README_FEATURE_COVERAGE.format(
        latest_additions=f"- **Latest stable additions ({tag}):** {latest}"
    )


def update_readme_durable_documentation(readme: str, changelog: str, tag: str) -> str:
    readme = readme.replace("```bash\n```bash\n", "```bash\n")
    architecture_row = "| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Current cross-platform architecture, ownership boundaries, performance rules, and verification model |"
    if architecture_row not in readme:
        changelog_row = "| [`CHANGELOG.md`](CHANGELOG.md) | Full release history and milestone issue coverage |"
        if changelog_row not in readme:
            raise ValueError("README project-documentation table anchor is missing")
        readme = readme.replace(changelog_row, changelog_row + "\n" + architecture_row, 1)
    return replace_or_insert_managed_block(
        readme,
        start_marker="<!-- FEATURE_COVERAGE:START -->",
        end_marker="<!-- FEATURE_COVERAGE:END -->",
        replacement=readme_feature_coverage(changelog, tag),
        insert_before="### Editing Core\n",
    )


def architecture_release_alignment(changelog: str, tag: str) -> str:
    tags = [tag, *prior_release_tags(changelog, tag, limit=1)]
    lines = ["<!-- RELEASE_ARCHITECTURE_ALIGNMENT:START -->", "## Current Release Alignment", ""]
    for release_tag in tags:
        release_date, section = extract_changelog_section_meta(changelog, release_tag)
        lines.append(f"### {release_tag} ({release_date})")
        lines.append("")
        bullets = []
        for heading in ("Highlights", "Fixes"):
            bullets.extend(extract_heading_bullets(section, heading, limit=4))
        lines.extend([f"- {item}" for item in bullets[:6]] or ["- See `CHANGELOG.md` for release details."])
        lines.append("")
    lines.append("This block is regenerated from `CHANGELOG.md` after each stable release. The sections below remain the authoritative description of ownership and runtime boundaries.")
    lines.append("<!-- RELEASE_ARCHITECTURE_ALIGNMENT:END -->")
    return "\n".join(lines)


def update_architecture_release_alignment(architecture: str, changelog: str, tag: str) -> str:
    release_date, _ = extract_changelog_section_meta(changelog, tag)
    architecture = re.sub(
        r"(?m)^Last updated: .*$",
        f"Last updated: {release_date} ({tag} release-aligned architecture)",
        architecture,
        count=1,
    )
    return replace_or_insert_managed_block(
        architecture,
        start_marker="<!-- RELEASE_ARCHITECTURE_ALIGNMENT:START -->",
        end_marker="<!-- RELEASE_ARCHITECTURE_ALIGNMENT:END -->",
        replacement=architecture_release_alignment(changelog, tag),
        insert_before="## Platform and Product Targets\n",
    )


def has_changelog_section(changelog: str, tag: str) -> bool:
    return re.search(rf"^## \[{re.escape(tag)}\] - \d{{4}}-\d{{2}}-\d{{2}}$", changelog, flags=re.M) is not None


def promote_unreleased_section(changelog: str, tag: str, date: str) -> str | None:
    """Move substantive Unreleased notes into the requested immutable release section."""
    pattern = re.compile(
        r"^## \[Unreleased\](?: - \d{4}-\d{2}-\d{2})?\n(?P<body>.*?)(?=^## \[|\Z)",
        flags=re.M | re.S,
    )
    match = pattern.search(changelog)
    if not match:
        return None
    body = match.group("body").strip()
    meaningful = [line for line in body.splitlines() if line.strip() and not line.lstrip().startswith("<!--")]
    if not meaningful:
        return None
    heading = f"## [{tag}] - {date}"
    replacement = f"{heading}\n\n{body}\n\n## [Unreleased]\n\n"
    return changelog[: match.start()] + replacement + changelog[match.end() :]


def add_changelog_section(changelog: str, tag: str, date: str) -> str:
    heading = f"## [{tag}] - {date}"
    template = (
        f"{heading}\n\n"
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


def prefixed_heading_bullets(tag: str, section_body: str, heading: str, limit: int) -> list[str]:
    bullets = extract_heading_bullets(section_body, heading, limit=limit)
    return [f"- {tag}: {bullet}" for bullet in bullets]


def release_card_bullets(tag: str, section: str, limit: int) -> list[str]:
    bullets: list[str] = []
    for heading in ("Why Upgrade", "Highlights", "Fixes"):
        remaining = limit - len(bullets)
        if remaining <= 0:
            break
        bullets.extend(prefixed_heading_bullets(tag, section, heading, limit=remaining))
    if not bullets:
        bullets = [f"- {tag}: {bullet[2:]}" for bullet in summarize_section(section, limit=limit)]
    return bullets[:limit]


def prior_release_tags(changelog: str, tag: str, limit: int = 3) -> list[str]:
    headings = extract_release_headings(changelog)
    if tag not in headings:
        return []
    stable_current = not is_prerelease_tag(tag)
    return [
        candidate
        for candidate in headings[headings.index(tag) + 1 :]
        if not (stable_current and is_prerelease_tag(candidate))
    ][:limit]


def welcome_release_bullets(changelog: str, tag: str, section: str) -> list[str]:
    bullets = release_card_bullets(tag, section, limit=WELCOME_TOUR_CARD_COUNT)
    if len(bullets) >= WELCOME_TOUR_CARD_COUNT:
        return bullets

    for prior_tag in prior_release_tags(changelog, tag):
        prior_section = extract_changelog_section(changelog, prior_tag)
        remaining = WELCOME_TOUR_CARD_COUNT - len(bullets)
        bullets.extend(release_card_bullets(prior_tag, prior_section, limit=remaining))
        if len(bullets) >= WELCOME_TOUR_CARD_COUNT:
            break
    return bullets[:WELCOME_TOUR_CARD_COUNT]


def shorten_for_welcome_tour_card(text: str, limit: int = WELCOME_TOUR_CARD_TEXT_BUDGET) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    clipped = text[: max(0, limit - 1)].rstrip()
    if " " in clipped:
        clipped = clipped.rsplit(" ", 1)[0]
    return clipped.rstrip(".,;:") + "…"


def welcome_feature_title(description: str, index: int) -> str:
    lowered = description.lower()
    rules = (
        (("navigation",), "Editor Navigation"),
        (("unnecessary work", "larger document", "performance", "responsive"), "Editor Performance"),
        (("assistive", "accessibility", "toolbar controls"), "Accessible Controls"),
        (("timeout", "ai provider"), "AI Timeouts"),
        (("table of contents", "toc", "heading"), "iPhone TOC"),
        (("syntax highlighting", "syntax coloring"), "Large-file Highlighting"),
        (("save", "trailing whitespace", "line ending"), "Reliable Saves"),
    )
    for keywords, title in rules:
        if any(keyword in lowered for keyword in keywords):
            return title
    return ["Editor Improvements", "Workflow Refinements", "Performance Updates", "Usability Updates"][index % 4]


def normalize_welcome_tour_bullets(bullets: list[str]) -> list[str]:
    normalized: list[str] = []
    for index, bullet in enumerate(bullets[:WELCOME_TOUR_CARD_COUNT]):
        body = bullet[2:] if bullet.startswith("- ") else bullet
        if ": " in body:
            _, description = body.split(": ", 1)
            body = f"{welcome_feature_title(description, index)}: {shorten_for_welcome_tour_card(description)}"
        else:
            body = shorten_for_welcome_tour_card(body)
        normalized.append(f"- {body}")
    return normalized


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


def adjacent_patch_release(previous_tag: str | None, current_tag: str) -> bool:
    if previous_tag is None:
        return False
    previous = parse_stable_semver(previous_tag)
    current = parse_stable_semver(current_tag)
    if previous is None or current is None:
        return False
    return previous[:2] == current[:2] and current[2] == previous[2] + 1


def whats_new_heading(previous_tag: str | None, current_tag: str) -> str:
    if adjacent_patch_release(previous_tag, current_tag):
        return f"## What's New in {previous_tag} and {current_tag}"
    if previous_tag:
        return f"## What's New Since {previous_tag}"
    return f"## What's New in {current_tag}"


def welcome_release_subtitle(current_tag: str) -> str:
    return f"Release highlights for {current_tag}."


def swift_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def update_welcome_tour_release_page(swift_source: str, tag: str, bullets: list[str]) -> str:
    if not bullets:
        bullet_lines = ['                "See CHANGELOG.md for details"']
    else:
        bullet_lines = [f'                "{swift_string(bullet[2:])}"' for bullet in bullets]

    subtitle = welcome_release_subtitle(tag)

    new_block = (
        "        TourPage(\n"
        f'            title: "What\u2019s New in {swift_string(tag)}",\n'
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
        r'            title: "What[^\n]*(?:This Release|in [^"]+)",\n'
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


def shorten_text(text: str, limit: int) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    clipped = text[: max(0, limit - 1)].rstrip()
    if " " in clipped:
        clipped = clipped.rsplit(" ", 1)[0]
    return clipped.rstrip(".,;:") + "…"


def release_timeline_title(section_body: str) -> str:
    title_items = extract_heading_bullets(section_body, "Why Upgrade", limit=2) + extract_heading_bullets(
        section_body, "Highlights", limit=2
    )
    text = " ".join(title_items or summarize_section(section_body, limit=2)).lower()
    if "markdown" in text:
        return "A more deliberate workflow"
    if any(token in text for token in ("shared-file sync", "external change", "icloud drive", "network folder")):
        return "Shared work, safely"
    if "window" in text and any(token in text for token in ("restore", "frame", "position")):
        return "Windows that remember"
    if any(token in text for token in ("appkit", "layout", "document transition")):
        return "Safer document transitions"
    return "Release highlights"


def release_timeline_description(section_body: str, limit: int = 235) -> str:
    for heading in ("Why Upgrade", "Highlights", "Fixes", "Added", "Improved"):
        items = extract_heading_bullets(section_body, heading, limit=1)
        if items:
            return shorten_text(items[0], limit)
    return "See CHANGELOG.md for details."


def release_timeline_impact(section_body: str, limit: int = 170) -> str:
    for heading in ("Fixes", "Fixed", "Highlights", "Why Upgrade", "Added", "Improved"):
        items = extract_heading_bullets(section_body, heading, limit=1)
        if items:
            return shorten_text(items[0], limit)
    return "See CHANGELOG.md for details."


def release_timeline_tags(section_body: str, limit: int = 3) -> list[str]:
    text = " ".join(summarize_section(section_body, limit=12)).lower()
    keyword_tags = (
        ("shared-file sync", "Shared-file sync"),
        ("external change", "External updates"),
        ("markdown", "Markdown"),
        ("code snapshot", "Code Snapshot"),
        ("welcome tour", "Welcome Tour"),
        ("window", "Windows"),
        ("preview", "Preview"),
        ("appkit", "AppKit stability"),
        ("layout", "Layout stability"),
        ("html", "HTML"),
        ("theme", "Themes"),
    )
    tags = [label for keyword, label in keyword_tags if keyword in text]
    return tags[:limit] or ["Release highlights"]


def release_timeline_entries(changelog: str, current_tag: str, limit: int = RELEASE_TIMELINE_COUNT) -> list[tuple[str, str, str, str, list[str]]]:
    tags = sorted_latest_tags(extract_release_headings(changelog), limit=limit, ensure_tag=current_tag)
    entries: list[tuple[str, str, str, str, list[str]]] = []
    for tag in reversed(tags):
        date, section = extract_changelog_section_meta(changelog, tag)
        entries.append((tag, date, release_timeline_title(section), release_timeline_description(section), release_timeline_tags(section)))
    return entries


def display_release_date(date: str) -> str:
    parsed = dt.date.fromisoformat(date)
    return f"{parsed.day} {parsed.strftime('%B %Y')}"


def mermaid_safe(value: str) -> str:
    return value.replace(":", " —").replace("\n", " ")


def rebuild_readme_release_timeline(readme: str, changelog: str, current_tag: str) -> str:
    lines = ["<!-- RELEASE_TIMELINE:START -->", "```mermaid", "timeline", "    title Neon Vision Editor — recent release story"]
    for tag, date, title, description, _ in release_timeline_entries(changelog, current_tag):
        lines.append(f"    {display_release_date(date)} : {tag} · {mermaid_safe(title)}")
        lines.append(f"                : {mermaid_safe(description)}")
    lines.extend(["```", "<!-- RELEASE_TIMELINE:END -->"])
    replacement = "\n".join(lines)
    pattern = re.compile(r"<!-- RELEASE_TIMELINE:START -->.*?<!-- RELEASE_TIMELINE:END -->", flags=re.S)
    if not pattern.search(readme):
        raise ValueError("README missing release timeline markers")
    return pattern.sub(replacement, readme, count=1)


def rebuild_website_release_timeline(website: str, changelog: str, current_tag: str) -> str:
    entries: list[str] = []
    for tag, date, title, description, tags in release_timeline_entries(changelog, current_tag):
        current_class = " current" if tag == current_tag else ""
        tag_html = "".join(f"<span>{html.escape(item)}</span>" for item in tags)
        entries.extend(
            [
                f'        <article class="release-entry{current_class}">',
                f'          <div class="release-marker" aria-hidden="true">{html.escape(tag.removeprefix("v"))}</div>',
                '          <div class="release-card">',
                '            <div class="release-card-header">',
                f'              <h3><a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/{html.escape(tag)}">{html.escape(tag)} — {html.escape(title)}</a></h3>',
                f'              <span class="release-date">{html.escape(display_release_date(date))}</span>',
                "            </div>",
                f"            <p>{html.escape(description)}</p>",
                f'            <div class="release-tags">{tag_html}</div>',
                "          </div>",
                "        </article>",
            ]
        )
    replacement = "\n".join(["        <!-- RELEASE_TIMELINE:START -->", *entries, "        <!-- RELEASE_TIMELINE:END -->"])
    pattern = re.compile(r"        <!-- RELEASE_TIMELINE:START -->.*?        <!-- RELEASE_TIMELINE:END -->", flags=re.S)
    if not pattern.search(website):
        raise ValueError("Website missing release timeline markers")
    return pattern.sub(replacement, website, count=1)


def changelog_badge_class(heading: str) -> str:
    return {"Highlights": "new", "Improvements": "improved", "Fixes": "fixed", "Breaking changes": "breaking"}.get(heading, "improved")


def changelog_badge_label(heading: str) -> str:
    return {"Highlights": "New", "Improvements": "Improved", "Fixes": "Fixed", "Breaking changes": "Breaking"}.get(heading, heading)


def full_changelog_tags(changelog: str, minimum_tag: str = "v0.5.0") -> list[str]:
    minimum_key = parse_version_key(minimum_tag)
    return [tag for tag in sorted_latest_tags(extract_release_headings(changelog), limit=len(extract_release_headings(changelog))) if parse_version_key(tag) >= minimum_key]


def rebuild_changelog_page(page: str, changelog: str, current_tag: str) -> str:
    entries: list[str] = []
    for tag in full_changelog_tags(changelog):
        date, _ = extract_changelog_section_meta(changelog, tag)
        _, section = extract_changelog_section_meta(changelog, tag)
        groups = [(heading, extract_heading_bullets(section, heading, limit=20)) for heading in ("Highlights", "Improvements", "Fixes", "Breaking changes")]
        current_class = " current" if tag == current_tag else ""
        latest = '<span class="latest">Latest</span>' if tag == current_tag else ""
        items = [f'          <div class="item"><span class="badge {changelog_badge_class(heading)}">{html.escape(changelog_badge_label(heading))}</span><p>{html.escape(bullet.removeprefix("- "))}</p></div>' for heading, bullets in groups for bullet in bullets]
        entries.append("\n".join([f'      <article class="release{current_class}">', f'        <div class="release-header"><h2>{html.escape(tag)}</h2><span class="date">{html.escape(display_release_date(date))}</span>{latest}</div>', '        <div class="items">', *items, '        </div>', '      </article>']))
    replacement = "\n".join(["    <!-- CHANGELOG_ENTRIES:START -->", *entries, "    <!-- CHANGELOG_ENTRIES:END -->"])
    pattern = re.compile(r"    <!-- CHANGELOG_ENTRIES:START -->.*?    <!-- CHANGELOG_ENTRIES:END -->", flags=re.S)
    if not pattern.search(page):
        raise ValueError("Changelog page entry markers are missing")
    return pattern.sub(replacement, page, count=1)


LOCALIZED_TIMELINE_COPY = {
    "de": {
        "v1.5.5": ("Präzise Bearbeitung mit Apple Pencil", "Zeigt auf dem iPad beim Schweben die Caret-Position, ermöglicht die direkte Bereichsauswahl mit dem Pencil und korrigiert die macOS-Editorzeichnung.", ["Editor", "Apple Pencil", "iPad"]),
        "v1.5.4": ("Alle Editorzeilen bleiben erreichbar", "Stellt sicher, dass umbrochene Zeilen nach Änderungen an Seitenleiste oder Vorschau bis zum Dokumentende erreichbar bleiben.", ["Editor", "Zeilenumbruch", "macOS"]),
        "v1.5.3": ("Große Dokumente reagieren schneller", "Beschleunigt Bearbeitung und Scrollen, reduziert unnötige Aktualisierungen und ergänzt einen ablenkungsfreien Fokusmodus.", ["Editor", "Leistung", "Fokusmodus"]),
        "v1.5.2": ("Editor und Vorschau bleiben synchron", "Gleicht die Schriftgröße der Markdown-Vorschau an den Editor an und misst die Leistung großer Dokumente.", ["Editor", "Vorschau", "Leistung"]),
        "v1.5.1": ("Lebendigere Markdown-Themes", "Verfeinert die Farbpaletten der Vorschau, verbessert das Öffnen von Projektordnern und stabilisiert Sparkle-Updates.", ["Markdown", "Themes", "Updates"]),
        "v1.3.6": ("Quick Look und Einstellungen werden stabiler", "Verfeinert Quick Look und die Größenanpassung des macOS-Einstellungsfensters für einen ruhigeren Arbeitsablauf.", ["Quick Look", "Einstellungen", "macOS"]),
        "v1.4.0": ("Toolbar und Quick Look bleiben lesbar", "Stellt die Kurzbezeichnungen der Toolbar wieder her und bündelt Quick Look in einem eigenständigen, überprüfbaren Build-Schema.", ["Symbolleiste", "Quick Look", "macOS"]),
        "v1.4.1": ("Große Dokumente bleiben flüssig", "Verbessert den virtuellen macOS-Editor, die Projektnavigation und kompakte iPhone-Bedienelemente.", ["Editor", "Projekt", "iPhone"]),
        "v1.4.2": ("Lesbare Vorschauen aus Milchglas", "Macht abgetrennte Markdown- und Finder-Quick-Look-Vorschauen transparenter und zugleich besser lesbar.", ["Vorschau", "Quick Look", "macOS"]),
        "v1.4.3": ("Stabiles Layout und Markdown-Karten", "Hält den macOS-Editor beim Wechseln von Arbeitsbereichen stabil und platziert Markdown-Aktionen direkt in der Vorschau.", ["Editor", "Markdown", "macOS"]),
        "v1.4.4": ("Zuverlässige Tastaturaktionen", "Zeigt Bearbeitungsaktionen über der Bildschirmtastatur und erhält den Zeilenumbruch bei Vorschau- und Seitenleistenwechseln.", ["Editor", "Tastatur", "iPhone"]),
        "v1.4.5": ("Editorbreite bleibt korrekt", "Hält den gesamten macOS-Editor nach Vorschau- und Seitenleistenwechseln beschreibbar und stellt den Zeilenumbruch sofort wieder her.", ["Editor", "Zeilenumbruch", "macOS"]),
        "v1.4.6": ("Quick Look zeigt mehr Syntaxfarben", "Erweitert die Syntaxfarben für unterstützte Dateitypen und hält kompakte Finder-Vorschauen frei von zusätzlichen Bedienelementen.", ["Quick Look", "Syntax", "macOS"]),
        "v1.5.0": ("Editor und Snapshots werden verlässlicher", "Verbessert Auswahl, Tastaturnavigation und Themes im macOS-Editor und erweitert den Code-Snapshot-Export.", ["Editor", "Themes", "Snapshots"]),
    },
    "da": {
        "v1.5.5": ("Præcis redigering med Apple Pencil", "Viser markørens placering ved svævning på iPad, vælger tekstområder direkte med Pencil og retter tegningen i macOS-editoren.", ["Editor", "Apple Pencil", "iPad"]),
        "v1.5.4": ("Alle editorlinjer forbliver tilgængelige", "Sikrer, at ombrudte linjer kan nås helt til dokumentets slutning efter ændringer i sidepanel eller forhåndsvisning.", ["Editor", "Linjeombrydning", "macOS"]),
        "v1.5.3": ("Store dokumenter reagerer hurtigere", "Gør redigering og rulning hurtigere, reducerer unødvendige opdateringer og tilføjer en fokustilstand uden forstyrrelser.", ["Editor", "Ydeevne", "Fokustilstand"]),
        "v1.5.2": ("Editor og forhåndsvisning følger hinanden", "Tilpasser Markdown-forhåndsvisningens skriftstørrelse til editoren og måler ydeevnen i store dokumenter.", ["Editor", "Forhåndsvisning", "Ydeevne"]),
        "v1.5.1": ("Mere levende Markdown-temaer", "Forfiner forhåndsvisningens farvepaletter, forbedrer åbning af projektmapper og stabiliserer Sparkle-opdateringer.", ["Markdown", "Temaer", "Opdateringer"]),
        "v1.3.6": ("Quick Look og indstillinger bliver mere stabile", "Forfiner Quick Look og størrelsestilpasningen af macOS-indstillingsvinduet for et roligere arbejdsforløb.", ["Quick Look", "Indstillinger", "macOS"]),
        "v1.4.0": ("Værktøjslinje og Quick Look forbliver læselige", "Gendanner værktøjslinjens korte etiketter og samler Quick Look i et selvstændigt, verificerbart byggeskema.", ["Værktøjslinje", "Quick Look", "macOS"]),
        "v1.4.1": ("Store dokumenter forbliver hurtige", "Forbedrer den virtuelle macOS-editor, projektnavigationen og kompakte iPhone-kontroller.", ["Editor", "Projekt", "iPhone"]),
        "v1.4.2": ("Læsbare frostede forhåndsvisninger", "Gør separate Markdown- og Finder Quick Look-forhåndsvisninger gennemsigtige og samtidig lettere at læse.", ["Forhåndsvisning", "Quick Look", "macOS"]),
        "v1.4.3": ("Stabilt layout og Markdown-kort", "Holder macOS-editoren stabil ved skift af arbejdsområde og placerer Markdown-handlinger direkte i forhåndsvisningen.", ["Editor", "Markdown", "macOS"]),
        "v1.4.4": ("Pålidelige tastaturhandlinger", "Viser redigeringshandlinger over skærmtastaturet og bevarer linjeskift ved skift af forhåndsvisning og sidepanel.", ["Editor", "Tastatur", "iPhone"]),
        "v1.4.5": ("Korrekt editorbredde", "Holder hele macOS-editoren skrivbar efter skift af forhåndsvisning og sidepanel og gendanner linjeombrydning med det samme.", ["Editor", "Linjeombrydning", "macOS"]),
        "v1.4.6": ("Flere syntaksfarver i Quick Look", "Udvider syntaksfarverne til understøttede filtyper og holder kompakte Finder-forhåndsvisninger fri for ekstra betjeningselementer.", ["Quick Look", "Syntaks", "macOS"]),
        "v1.5.0": ("Editor og snapshots bliver mere pålidelige", "Forbedrer markering, tastaturnavigation og temaer i macOS-editoren og udvider eksporten af kodesnapshots.", ["Editor", "Temaer", "Snapshots"]),
    },
    "fr": {
        "v1.5.5": ("Édition précise avec Apple Pencil", "Affiche la position du curseur au survol sur iPad, sélectionne directement des plages avec le Pencil et corrige le rendu de l’éditeur macOS.", ["Éditeur", "Apple Pencil", "iPad"]),
        "v1.5.4": ("Toutes les lignes restent accessibles", "Garantit l’accès aux lignes renvoyées à la ligne jusqu’à la fin du document après un changement de barre latérale ou d’aperçu.", ["Éditeur", "Retour à la ligne", "macOS"]),
        "v1.5.3": ("Les grands documents répondent plus vite", "Accélère l’édition et le défilement, réduit les actualisations inutiles et ajoute un mode concentration sans distraction.", ["Éditeur", "Performances", "Concentration"]),
        "v1.5.2": ("Éditeur et aperçu restent synchronisés", "Aligne la taille du texte de l’aperçu Markdown sur celle de l’éditeur et mesure les performances des grands documents.", ["Éditeur", "Aperçu", "Performances"]),
        "v1.5.1": ("Des thèmes Markdown plus vivants", "Affine les palettes de l’aperçu, améliore l’ouverture des dossiers de projet et stabilise les mises à jour Sparkle.", ["Markdown", "Thèmes", "Mises à jour"]),
        "v1.3.6": ("Quick Look et les réglages gagnent en stabilité", "Affine Quick Look et l’adaptation de taille de la fenêtre Réglages sur macOS pour un flux de travail plus calme.", ["Quick Look", "Réglages", "macOS"]),
        "v1.4.0": ("Barre d’outils et Quick Look restent lisibles", "Restaure les libellés courts de la barre d’outils et regroupe Quick Look dans un schéma de build autonome et vérifiable.", ["Barre d’outils", "Quick Look", "macOS"]),
        "v1.4.1": ("Les grands documents restent fluides", "Améliore l’éditeur virtuel macOS, la navigation de projet et les commandes compactes sur iPhone.", ["Éditeur", "Projet", "iPhone"]),
        "v1.4.2": ("Des aperçus givrés lisibles", "Rend les aperçus Markdown détachés et Finder Quick Look transparents tout en améliorant leur lisibilité.", ["Aperçu", "Quick Look", "macOS"]),
        "v1.4.3": ("Mise en page stable et cartes Markdown", "Maintient la stabilité de l’éditeur macOS lors des changements d’espace de travail et place les actions Markdown dans l’aperçu.", ["Éditeur", "Markdown", "macOS"]),
        "v1.4.4": ("Actions clavier fiables", "Affiche les actions d’édition au-dessus du clavier à l’écran et préserve le retour à la ligne lors des changements d’aperçu ou de barre latérale.", ["Éditeur", "Clavier", "iPhone"]),
        "v1.4.5": ("Largeur d’éditeur fiable", "Garde toute la largeur de l’éditeur macOS modifiable après les changements d’aperçu ou de barre latérale et rétablit immédiatement le retour à la ligne.", ["Éditeur", "Retour à la ligne", "macOS"]),
        "v1.4.6": ("Plus de couleurs de syntaxe dans Quick Look", "Étend les couleurs de syntaxe aux types de fichiers pris en charge et garde les aperçus compacts du Finder sans commandes supplémentaires.", ["Quick Look", "Syntaxe", "macOS"]),
        "v1.5.0": ("Éditeur et instantanés plus fiables", "Améliore la sélection, la navigation au clavier et les thèmes dans l’éditeur macOS, tout en enrichissant l’export d’instantanés de code.", ["Éditeur", "Thèmes", "Instantanés"]),
    },
    "es": {
        "v1.5.5": ("Edición precisa con Apple Pencil", "Muestra la posición del cursor al pasar el Pencil en iPad, permite seleccionar rangos directamente y corrige el dibujo del editor de macOS.", ["Editor", "Apple Pencil", "iPad"]),
        "v1.5.4": ("Todas las líneas siguen accesibles", "Garantiza el acceso a las líneas ajustadas hasta el final del documento tras cambiar la barra lateral o la vista previa.", ["Editor", "Ajuste de línea", "macOS"]),
        "v1.5.3": ("Los documentos grandes responden más rápido", "Acelera la edición y el desplazamiento, reduce actualizaciones innecesarias y añade un modo de concentración sin distracciones.", ["Editor", "Rendimiento", "Concentración"]),
        "v1.5.2": ("Editor y vista previa sincronizados", "Alinea el tamaño del texto de la vista previa Markdown con el editor y mide el rendimiento de documentos grandes.", ["Editor", "Vista previa", "Rendimiento"]),
        "v1.5.1": ("Temas Markdown más vivos", "Perfecciona las paletas de color de la vista previa, mejora la apertura de carpetas de proyecto y estabiliza las actualizaciones de Sparkle.", ["Markdown", "Temas", "Actualizaciones"]),
        "v1.3.6": ("Quick Look y Ajustes ganan estabilidad", "Perfecciona Quick Look y el ajuste de tamaño de la ventana Ajustes de macOS para un flujo de trabajo más tranquilo.", ["Quick Look", "Ajustes", "macOS"]),
        "v1.4.0": ("La barra y Quick Look siguen siendo legibles", "Restaura las etiquetas abreviadas de la barra y reúne Quick Look en un esquema de compilación autónomo y verificable.", ["Barra", "Quick Look", "macOS"]),
        "v1.4.1": ("Los documentos grandes siguen siendo ágiles", "Mejora el editor virtual de macOS, la navegación de proyectos y los controles compactos del iPhone.", ["Editor", "Proyecto", "iPhone"]),
        "v1.4.2": ("Vistas previas de vidrio esmerilado", "Mantiene transparentes las vistas previas Markdown separadas y de Finder Quick Look, con mejor legibilidad.", ["Vista previa", "Quick Look", "macOS"]),
        "v1.4.3": ("Diseño estable y tarjetas Markdown", "Mantiene estable el editor de macOS al cambiar de espacio de trabajo y sitúa las acciones de Markdown en la vista previa.", ["Editor", "Markdown", "macOS"]),
        "v1.4.4": ("Acciones de teclado fiables", "Muestra acciones de edición sobre el teclado en pantalla y conserva el ajuste de línea al cambiar la vista previa o la barra lateral.", ["Editor", "Teclado", "iPhone"]),
        "v1.4.5": ("Ancho de editor fiable", "Mantiene editable todo el ancho del editor de macOS tras cambiar la vista previa o la barra lateral y restaura de inmediato el ajuste de línea.", ["Editor", "Ajuste de línea", "macOS"]),
        "v1.4.6": ("Más colores de sintaxis en Quick Look", "Amplía los colores de sintaxis para los tipos de archivo compatibles y mantiene las vistas compactas del Finder sin controles adicionales.", ["Quick Look", "Sintaxis", "macOS"]),
        "v1.5.0": ("Editor y capturas más fiables", "Mejora la selección, la navegación por teclado y los temas del editor de macOS, y amplía la exportación de capturas de código.", ["Editor", "Temas", "Capturas"]),
    },
    "ja": {
        "v1.5.5": ("Apple Pencil で正確に編集", "iPad でホバー時にキャレット位置を表示し、Pencil で範囲を直接選択できるようにして、macOS エディタの描画も修正します。", ["エディタ", "Apple Pencil", "iPad"]),
        "v1.5.4": ("すべての行に最後までアクセス", "サイドバーやプレビューの変更後も、折り返された行を文書の末尾まで確実に表示できるようにします。", ["エディタ", "行の折り返し", "macOS"]),
        "v1.5.3": ("大きな書類をさらに高速に操作", "編集とスクロールを高速化し、不要な更新を減らして、集中できるフォーカスモードを追加します。", ["エディタ", "パフォーマンス", "フォーカス"]),
        "v1.5.2": ("エディタとプレビューを同期", "Markdown プレビューの文字サイズをエディタに合わせ、大きなドキュメントのパフォーマンスを測定します。", ["エディタ", "プレビュー", "パフォーマンス"]),
        "v1.5.1": ("Markdown テーマをより鮮やかに", "プレビューのカラーパレットを改善し、プロジェクトフォルダの直接オープンと Sparkle の更新を安定させます。", ["Markdown", "テーマ", "アップデート"]),
        "v1.3.6": ("Quick Look と設定がさらに安定", "Quick Look と macOS 設定ウインドウのサイズ調整を改善し、より落ち着いた作業環境にします。", ["Quick Look", "設定", "macOS"]),
        "v1.4.0": ("ツールバーと Quick Look の可読性を維持", "ツールバーの短いラベルを復元し、Quick Look を独立した検証可能なビルドスキームにまとめます。", ["ツールバー", "Quick Look", "macOS"]),
        "v1.4.1": ("大きな書類も快適に操作", "macOS の仮想エディタ、プロジェクトナビゲーション、iPhone のコンパクトな操作を改善します。", ["エディタ", "プロジェクト", "iPhone"]),
        "v1.4.2": ("読みやすいフロストガラスのプレビュー", "分離した Markdown と Finder Quick Look のプレビューを透明に保ちながら読みやすくします。", ["プレビュー", "Quick Look", "macOS"]),
        "v1.4.3": ("安定したレイアウトと Markdown カード", "ワークスペースの切り替え時も macOS エディタを安定させ、Markdown の操作をプレビュー内に配置します。", ["エディタ", "Markdown", "macOS"]),
        "v1.4.4": ("信頼できるキーボード操作", "画面キーボードの上に編集操作を表示し、プレビューやサイドバーの切り替え時も行の折り返しを維持します。", ["エディタ", "キーボード", "iPhone"]),
        "v1.4.5": ("正確なエディタ幅", "プレビューやサイドバーの切り替え後も macOS エディタの全幅で編集でき、行の折り返しをすぐに復元します。", ["エディタ", "行の折り返し", "macOS"]),
        "v1.4.6": ("Quick Look の構文色を拡充", "対応するファイル形式の構文色を増やし、Finder のコンパクトなプレビューでは追加の操作を表示しません。", ["Quick Look", "構文", "macOS"]),
        "v1.5.0": ("エディタとスナップショットをさらに信頼性向上", "macOS エディタの選択、キーボード操作、テーマを改善し、コードスナップショットの書き出しを拡充します。", ["エディタ", "テーマ", "スナップショット"]),
    },
    "zh-Hans": {
        "v1.5.5": ("使用 Apple Pencil 精确编辑", "在 iPad 悬停时预览插入点，使用 Pencil 直接选择文本范围，并修复 macOS 编辑器绘制问题。", ["编辑器", "Apple Pencil", "iPad"]),
        "v1.5.4": ("所有编辑器行均可访问", "在切换侧边栏或预览后，确保自动换行内容一直可以滚动到文档末尾。", ["编辑器", "自动换行", "macOS"]),
        "v1.5.3": ("大型文档响应更快", "加快编辑和滚动，减少不必要的刷新，并加入无干扰的专注模式。", ["编辑器", "性能", "专注模式"]),
        "v1.5.2": ("编辑器与预览保持同步", "让 Markdown 预览文字大小与编辑器一致，并测量大型文档的性能。", ["编辑器", "预览", "性能"]),
        "v1.5.1": ("更鲜明的 Markdown 主题", "改进预览配色，优化直接打开项目文件夹，并提高 Sparkle 更新的稳定性。", ["Markdown", "主题", "更新"]),
        "v1.3.6": ("Quick Look 与设置更加稳定", "优化 Quick Look 和 macOS 设置窗口的尺寸调整，让工作流程更加稳定。", ["Quick Look", "设置", "macOS"]),
        "v1.4.0": ("工具栏与 Quick Look 保持清晰", "恢复工具栏的简短标签，并将 Quick Look 整合到独立且可验证的构建方案中。", ["工具栏", "Quick Look", "macOS"]),
        "v1.4.1": ("大文档依然流畅", "改进 macOS 虚拟编辑器、项目导航和 iPhone 的紧凑控制。", ["编辑器", "项目", "iPhone"]),
        "v1.4.2": ("更易读的磨砂玻璃预览", "让独立 Markdown 和 Finder Quick Look 预览保持透明，同时提高可读性。", ["预览", "Quick Look", "macOS"]),
        "v1.4.3": ("稳定布局与 Markdown 卡片", "在切换工作区时保持 macOS 编辑器稳定，并将 Markdown 操作放在预览中。", ["编辑器", "Markdown", "macOS"]),
        "v1.4.4": ("可靠的键盘操作", "在屏幕键盘上方显示编辑操作，并在切换预览或侧边栏时保持自动换行。", ["编辑器", "键盘", "iPhone"]),
        "v1.4.5": ("可靠的编辑器宽度", "切换预览或侧边栏后，macOS 编辑器的整个宽度仍可编辑，并立即恢复自动换行。", ["编辑器", "自动换行", "macOS"]),
        "v1.4.6": ("Quick Look 展示更多语法颜色", "扩展受支持文件类型的语法配色，并让 Finder 的紧凑预览不显示额外控件。", ["Quick Look", "语法", "macOS"]),
        "v1.5.0": ("编辑器与快照更加可靠", "改进 macOS 编辑器的选择、键盘导航和主题，并扩展代码快照导出功能。", ["编辑器", "主题", "快照"]),
    },
}

README_PREVIOUS_RELEASE_OVERRIDES = {
    "v1.3.3": "v1.3.1",
}


def rebuild_localized_website_release_timeline(website: str, changelog: str, current_tag: str, locale: str) -> str:
    source_entries = release_timeline_entries(changelog, current_tag)
    copy = LOCALIZED_TIMELINE_COPY[locale]
    source_tags = tuple(entry[0] for entry in source_entries)
    missing_tags = [tag for tag in source_tags if tag not in copy]
    if missing_tags:
        raise ValueError(f"Localized timeline copy is incomplete for {locale}: missing {', '.join(missing_tags)}.")
    entries: list[str] = []
    for tag, date, _, _, _ in source_entries:
        title, description, tags = copy[tag]
        current_class = " current" if tag == current_tag else ""
        tag_html = "".join(f"<span>{html.escape(item)}</span>" for item in tags)
        entries.extend([
            f'        <article class="release-entry{current_class}">',
            f'          <div class="release-marker" aria-hidden="true">{html.escape(tag.removeprefix("v"))}</div>',
            '          <div class="release-card">',
            '            <div class="release-card-header">',
            f'              <h3><a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/{html.escape(tag)}">{html.escape(tag)} — {html.escape(title)}</a></h3>',
            f'              <span class="release-date">{html.escape(display_release_date(date))}</span>',
            "            </div>",
            f"            <p>{html.escape(description)}</p>",
            f'            <div class="release-tags">{tag_html}</div>',
            "          </div>",
            "        </article>",
        ])
    replacement = "\n".join(["        <!-- RELEASE_TIMELINE:START -->", *entries, "        <!-- RELEASE_TIMELINE:END -->"])
    pattern = re.compile(r"        <!-- RELEASE_TIMELINE:START -->.*?        <!-- RELEASE_TIMELINE:END -->", flags=re.S)
    if not pattern.search(website):
        raise ValueError(f"Localized website timeline markers are missing for {locale}.")
    return pattern.sub(replacement, website, count=1)


def validate_release_input(changelog: str, tag: str) -> None:
    if not has_changelog_section(changelog, tag):
        raise ValueError(f"CHANGELOG.md has no section for {tag}.")
    for locale, path in LOCALIZED_WEBSITES.items():
        rebuild_localized_website_release_timeline(read_text(path), changelog, tag, locale)


def replace_website_value(website: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, website, count=1, flags=re.S)
    if count != 1:
        raise ValueError(f"Website replacement failed for {label}.")
    return updated


def update_website_release_fallbacks(website: str, tag: str, build: str | None = None) -> str:
    version = tag.removeprefix("v")
    website = replace_website_value(
        website,
        r'(<html lang="en" data-static-release-version=")v[^\"]+(">)',
        rf"\g<1>{tag}\g<2>",
        "static release marker",
    )
    website = replace_website_value(
        website,
        r'("softwareVersion": ")\d+\.\d+(?:\.\d+)?(?:-[^\"]+)?(")',
        rf"\g<1>{version}\g<2>",
        "JSON-LD software version",
    )
    for label, pattern in (
        ("JSON-LD download URL", r'("downloadUrl": "https://github\.com/h3pdesign/Neon-Vision-Editor/releases/tag/)v[^\"]+(\")'),
        ("JSON-LD release-notes URL", r'("releaseNotes": "https://github\.com/h3pdesign/Neon-Vision-Editor/releases/tag/)v[^\"]+(\")'),
    ):
        website = replace_website_value(website, pattern, rf"\g<1>{tag}\g<2>", label)

    website = re.sub(r'(<span data-latest-version>)v[^<]+(</span>)', rf"\g<1>{tag}\g<2>", website)
    website = re.sub(
        r'(<p class="markdown-feature-cta"><a class="button" href="#get-neon">[^<]*?)v\d+\.\d+\.\d+',
        rf'\g<1>{tag}',
        website,
    )
    if build is not None:
        website = re.sub(r'(<(?:span|strong) data-latest-build>)\d+(</(?:span|strong)>)', rf"\g<1>{build}\g<2>", website)
    website = re.sub(
        r'(data-latest-release-url href="https://github\.com/h3pdesign/Neon-Vision-Editor/releases/tag/)v[^\"]+(\")',
        rf"\g<1>{tag}\g<2>",
        website,
    )
    website = re.sub(
        r'(data-release-asset="[^\"]+"\s+href="https://github\.com/h3pdesign/Neon-Vision-Editor/releases/download/)v[^/\"]+(/[^\"]+\")',
        rf"\g<1>{tag}\g<2>",
        website,
    )
    return website


def update_localized_website_release_fallbacks(website: str, tag: str, build: str | None = None) -> str:
    """Keep localized Pages fallbacks and client-side release selectors aligned."""
    version = tag.removeprefix("v")
    website, count = re.subn(
        r'(<html lang="[^"]+" )data-static-release-[^=]+="v[^"]+"',
        rf'\g<1>data-static-release-version="{tag}"',
        website,
        count=1,
    )
    if count != 1:
        raise ValueError("Localized website static release marker is missing.")
    website = re.sub(
        r'data-latest-(?:Version|versión|バージョン|版本)(?=[\s>])',
        "data-latest-version",
        website,
    )
    website = re.sub(r'("softwareVersion": ")\d+\.\d+(?:\.\d+)?(?:-[^"]+)?(")', rf'\g<1>{version}\g<2>', website)
    website = re.sub(
        r'("(?:downloadUrl|releaseNotes)": "https://github\.com/h3pdesign/Neon-Vision-Editor/releases/tag/)v[^"]+(")',
        rf'\g<1>{tag}\g<2>',
        website,
    )
    website = re.sub(r'(<span data-latest-version>)v[^<]+(</span>)', rf'\g<1>{tag}\g<2>', website)
    website = re.sub(
        r'(<p class="markdown-feature-cta"><a class="button" href="#get-neon">[^<]*?)v\d+\.\d+\.\d+',
        rf'\g<1>{tag}',
        website,
    )
    if build is not None:
        website = re.sub(r'(<(?:span|strong) data-latest-build>)\d+(</(?:span|strong)>)', rf'\g<1>{build}\g<2>', website)
    website = re.sub(
        r'(data-latest-release-url href="https://github\.com/h3pdesign/Neon-Vision-Editor/releases/tag/)v[^"]+(")',
        rf'\g<1>{tag}\g<2>',
        website,
    )
    return re.sub(
        r'(data-release-asset="[^"]+"\s+href="https://github\.com/h3pdesign/Neon-Vision-Editor/releases/download/)v[^/"]+(/[^\"]+")',
        rf'\g<1>{tag}\g<2>',
        website,
    )


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
        r"\| Release \| The editor change \| What it protects or enables \|\n"
        r"\|---\|---\|---\|\n)"
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
        _, section = extract_changelog_section_meta(changelog, tag)
        title = release_timeline_title(section)
        description = release_timeline_description(section, limit=150)
        impact = release_timeline_impact(section, limit=150)
        rows.append(
            f"| [`{tag}`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/{tag}) | "
            f"**{title}** — {description} | {impact} |"
        )

    rows_block = "\n".join(rows) + "\n"
    return readme[: match.start("rows")] + rows_block + readme[match.end("rows") :]


def update_readme_latest_stable_line(readme: str, tag: str, changelog: str) -> str:
    date, _ = extract_changelog_section_meta(changelog, tag)
    readme = re.sub(
        r"(?m)^Latest stable: \*\*.*\*\* \(\d{4}-\d{2}-\d{2}\)$",
        f"Latest stable: **{tag}** ({date})",
        readme,
    )
    last_updated_date = date
    last_updated_match = re.search(
        r"(?m)^> Last updated \(README\): \*\*(?P<date>\d{4}-\d{2}-\d{2})\*\* for latest release \*\*(?P<tag>[^*]+)\*\*$",
        readme,
    )
    if last_updated_match and last_updated_match.group("tag") == tag:
        existing_date = last_updated_match.group("date")
        last_updated_date = max(date, existing_date)
    readme = re.sub(
        r"(?m)^> Last updated \(README\): \*\*\d{4}-\d{2}-\d{2}\*\* for latest release \*\*.*\*\*$",
        f"> Last updated (README): **{last_updated_date}** for latest release **{tag}**",
        readme,
    )
    return readme


def update_readme_release_refs(readme: str, tag: str) -> str:
    stable = parse_stable_semver(tag)
    if stable is not None:
        major, minor, patch = stable
        next_tag = f"v{major}.{minor}.{patch + 1}"
        readme = re.sub(
            r"(?m)^> Next release target: \*\*.*\*\*$",
            f"> Next release target: **{next_tag}**",
            readme,
        )
    readme = re.sub(
        r"(?m)^> Latest release: \*\*.*\*\*$",
        f"> Latest release: **{tag}**",
        readme,
    )
    readme = re.sub(
        r"(?m)(<img alt=\"Latest Release\" src=\"https://img\.shields\.io/badge/release-)v[^-\"]+(-0A84FF\"></a>)",
        rf"\1{tag}\2",
        readme,
    )
    readme = re.sub(
        r"(?m)^> Direct GitHub release: .*$",
        f"> Direct GitHub release: **{tag}** / App Store and TestFlight availability varies by platform and review status",
        readme,
    )
    fallback_tag = README_PREVIOUS_RELEASE_OVERRIDES.get(tag)
    fallback_line = (
        f"> Previous viable fallback: **{fallback_tag}**"
        if fallback_tag
        else ""
    )
    if fallback_line:
        direct_release_line = (
            f"> Direct GitHub release: **{tag}** / App Store and TestFlight availability varies by platform and review status"
        )
        if re.search(r"(?m)^> Previous viable fallback: .*$", readme):
            readme = re.sub(r"(?m)^> Previous viable fallback: .*$", fallback_line, readme)
        else:
            readme = readme.replace(direct_release_line, f"{direct_release_line}\n{fallback_line}", 1)
    else:
        readme = re.sub(r"(?m)^> Previous viable fallback: .*$\n?", "", readme)
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
        r"(?m)^(\| \*\*Stable\*\* \| [^|]+ \| [^|]+ \| \[GitHub Releases\]\(https://github\.com/h3pdesign/Neon-Vision-Editor/releases\) \| )\*\*v[^*]+\*\*( \| Current direct download \|)$",
        rf"\1**{tag}**\2",
        readme,
    )
    readme = re.sub(
        r"(?m)^        <td>v[^<]+ release docs current; v[^<]+ direct download current</td>$",
        f"        <td>{tag} release docs current; {tag} direct download current</td>",
        readme,
    )
    readme = re.sub(
        r"(?m)^\| Stable direct download \| `v[^`]+` notarized GitHub release \| Current \|$",
        f"| Stable direct download | `{tag}` notarized GitHub release | Current |",
        readme,
    )
    return readme


def update_readme_whats_new_heading(readme: str, previous_tag: str | None, current_tag: str) -> str:
    replacement = whats_new_heading(previous_tag, current_tag)
    return re.sub(
        r"(?m)^## What's New Since [^\n]+$|^## What's New in [^\n]+$",
        replacement,
        readme,
    )


def markdown_bullets(items: list[str], fallback: str) -> str:
    if not items:
        return f"- {fallback}"
    return "\n".join(f"- {item}" for item in items)


def whats_new_feature_badges(why_upgrade_items: list[str]) -> list[str]:
    release_summary = " ".join(why_upgrade_items).lower()
    if "shared-file sync" not in release_summary:
        return []
    return [
        '<p align="center">',
        '  <img alt="Shared File Sync" src="https://img.shields.io/badge/Shared%20Files-Open%20Tab%20Sync-14B8A6?style=for-the-badge">',
        "</p>",
    ]


def update_readme_whats_new_section(
    readme: str,
    changelog: str,
    current_tag: str,
    current_section: str,
    previous_tag: str | None,
) -> str:
    heading = whats_new_heading(previous_tag, current_tag)
    current_why = extract_heading_bullets(current_section, "Why Upgrade", limit=3)
    current_highlights = extract_heading_bullets(current_section, "Highlights", limit=5)
    feature_badges = whats_new_feature_badges(current_why)

    sections = [
        heading,
        "",
        "### Why Upgrade",
        "",
    ]
    if feature_badges:
        sections.extend(feature_badges + [""])
    sections.extend(
        [
            markdown_bullets([f"{current_tag}: {item}" for item in current_why], f"{current_tag}: See CHANGELOG.md entry."),
            "",
            f"### {current_tag} Highlights",
            "",
            markdown_bullets(current_highlights, "See CHANGELOG.md release highlights."),
        ]
    )

    if adjacent_patch_release(previous_tag, current_tag):
        assert previous_tag is not None
        previous_section = extract_changelog_section(changelog, previous_tag)
        previous_why = extract_heading_bullets(previous_section, "Why Upgrade", limit=3)
        previous_highlights = extract_heading_bullets(previous_section, "Highlights", limit=4)
        sections.extend(
            [
                "",
                f"### {previous_tag} Context",
                "",
                markdown_bullets(
                    [f"{previous_tag}: {item}" for item in previous_why],
                    f"{previous_tag}: See CHANGELOG.md entry.",
                ),
                "",
                f"### {previous_tag} Highlights",
                "",
                markdown_bullets(previous_highlights, "See CHANGELOG.md release highlights."),
            ]
        )

    replacement = "\n".join(sections).rstrip() + "\n\n"
    pattern = re.compile(
        r"^## What's New(?: Since [^\n]+| in [^\n]+)\n.*?(?=^## Start Here\n)",
        flags=re.M | re.S,
    )
    if not pattern.search(readme):
        raise ValueError("README missing What's New section before Start Here.")
    return pattern.sub(replacement, readme, count=1)


def readme_previous_release_tag(changelog: str, current_tag: str) -> str | None:
    preferred_tag = README_PREVIOUS_RELEASE_OVERRIDES.get(current_tag)
    if preferred_tag and has_changelog_section(changelog, preferred_tag):
        return preferred_tag
    return previous_release_tag(changelog, current_tag)


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
    readme = re.sub(
        r"(?m)^- !\[v[^]]+\]\(https://img\.shields\.io/badge/v[^)]+-22C55E\?style=flat-square\) focuses on .*$",
        (
            f"- ![v{major}.{minor}.{patch}](https://img.shields.io/badge/v{major}.{minor}.{patch}-22C55E?style=flat-square) "
            "focuses on editor interaction polish, Markdown preview stability, local custom AI endpoints, sidebar terminal improvements, and release workflow hardening."
        ),
        readme,
    )
    readme = re.sub(
        r"(?m)^  Tracking: \[Release v[^]]+\]\(https://github\.com/h3pdesign/Neon-Vision-Editor/releases/tag/v[^)]+\)$",
        f"  Tracking: [Release v{major}.{minor}.{patch}](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v{major}.{minor}.{patch})",
        readme,
        count=1,
    )
    readme = re.sub(
        r"(?m)^- !\[v[^]]+\]\(https://img\.shields\.io/badge/v[^)]+-F59E0B\?style=flat-square\) targets .*$",
        (
            f"- ![v{major}.{minor}.{next_patch}](https://img.shields.io/badge/v{major}.{minor}.{next_patch}-F59E0B?style=flat-square) "
            f"targets post-{major}.{minor}.{patch} stabilization: App Store review follow-up, README/release metadata freshness, preview polish, and small cross-platform editor fixes."
        ),
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
    parser.add_argument(
        "--preflight",
        action="store_true",
        help="Validate the changelog and localized timeline inputs before release preparation mutates project metadata.",
    )
    parser.add_argument(
        "--build",
        help="Release build number used by static website fallbacks. Release preparation supplies this after bumping the project build.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tag = normalize_tag(args.tag)
    if args.check and args.preflight:
        raise ValueError("--check and --preflight cannot be used together.")
    if args.build is not None and not re.fullmatch(r"[1-9]\d*", args.build):
        raise ValueError("Build number must be a positive integer.")
    release_date = args.date or dt.date.today().isoformat()

    original_changelog = read_text(CHANGELOG)
    if args.preflight:
        validate_release_input(original_changelog, tag)
        print(f"Release input preflight passed for {tag}.")
        return 0

    changelog = original_changelog
    if not has_changelog_section(changelog, tag):
        promoted = promote_unreleased_section(changelog, tag, release_date)
        changelog = promoted if promoted is not None else add_changelog_section(changelog, tag, release_date)
        if not args.check:
            action = "Promoted Unreleased notes" if promoted is not None else "Added CHANGELOG template"
            print(f"{action} for {tag} ({release_date}).")
    elif not args.check:
        print(f"Found existing CHANGELOG section for {tag}.")

    section = extract_changelog_section(changelog, tag)
    prev_tag = readme_previous_release_tag(changelog, tag)
    bullets = normalize_welcome_tour_bullets(welcome_release_bullets(changelog, tag, section))

    original_readme = read_text(README)
    readme = update_readme_release_refs(original_readme, tag)
    readme = update_readme_whats_new_heading(readme, prev_tag, tag)
    readme = update_readme_whats_new_section(readme, changelog, tag, section, prev_tag)
    readme = update_readme_roadmap_windows(readme, tag)
    readme = update_readme_compare_link(readme, prev_tag, tag)
    readme = update_readme_feature_spotlight(readme, tag, section)
    readme = update_readme_latest_stable_line(readme, tag, changelog)
    readme = rebuild_readme_release_timeline(readme, changelog, tag)
    readme = rebuild_readme_changelog_table(readme, changelog, tag, limit=3)
    readme = update_readme_durable_documentation(readme, changelog, tag)

    original_architecture = read_text(ARCHITECTURE)
    architecture = update_architecture_release_alignment(original_architecture, changelog, tag)

    original_welcome_src = read_text(WELCOME_TOUR_SWIFT)
    welcome_src = update_welcome_tour_release_page(original_welcome_src, tag, bullets)

    original_website = read_text(WEBSITE)
    website = rebuild_website_release_timeline(original_website, changelog, tag)
    website = update_website_release_fallbacks(website, tag, args.build)
    original_changelog_page = read_text(CHANGELOG_PAGE)
    changelog_page = rebuild_changelog_page(original_changelog_page, changelog, tag)
    original_localized_websites = {locale: read_text(path) for locale, path in LOCALIZED_WEBSITES.items()}
    localized_websites = {
        locale: update_localized_website_release_fallbacks(
            rebuild_localized_website_release_timeline(content, changelog, tag, locale),
            tag,
            args.build,
        )
        for locale, content in original_localized_websites.items()
    }

    if args.check:
        outdated_files: list[str] = []
        if changelog != original_changelog:
            outdated_files.append(str(CHANGELOG))
        if readme != original_readme:
            outdated_files.append(str(README))
        if architecture != original_architecture:
            outdated_files.append(str(ARCHITECTURE))
        if welcome_src != original_welcome_src:
            outdated_files.append(str(WELCOME_TOUR_SWIFT))
        if website != original_website:
            outdated_files.append(str(WEBSITE))
        if changelog_page != original_changelog_page:
            outdated_files.append(str(CHANGELOG_PAGE))
        outdated_files.extend(
            str(LOCALIZED_WEBSITES[locale])
            for locale, website_content in localized_websites.items()
            if website_content != original_localized_websites[locale]
        )
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
    write_text(ARCHITECTURE, architecture)
    write_text(WELCOME_TOUR_SWIFT, welcome_src)
    write_text(WEBSITE, website)
    write_text(CHANGELOG_PAGE, changelog_page)
    for locale, path in LOCALIZED_WEBSITES.items():
        write_text(path, localized_websites[locale])
    print("Updated README release references, durable feature coverage, and top 3 release rows.")
    print("Updated architecture release alignment from CHANGELOG.")
    print("Updated English and localized GitHub Pages release fallbacks and timelines from CHANGELOG.")
    print(f"Updated Welcome Tour release page from CHANGELOG for {tag}.")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI friendly
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
