#!/usr/bin/env python3
"""Generate dark/light release history timeline SVGs with upcoming milestones.

This script updates:
  - docs/images/neon-vision-release-history-0.1-to-0.5.svg
  - docs/images/neon-vision-release-history-0.1-to-0.5-light.svg

The filename is kept stable for README compatibility.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import textwrap
from dataclasses import dataclass
from html import escape


ROOT = pathlib.Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "CHANGELOG.md"
DARK_SVG = ROOT / "docs" / "images" / "neon-vision-release-history-0.1-to-0.5.svg"
LIGHT_SVG = ROOT / "docs" / "images" / "neon-vision-release-history-0.1-to-0.5-light.svg"


@dataclass(frozen=True)
class ReleaseSection:
    tag: str
    major: int
    minor: int
    patch: int
    body: str


@dataclass(frozen=True)
class Milestone:
    label: str
    title: str
    bullets: list[str]
    is_future: bool
    color: str


SEED_MINOR_TITLES: dict[tuple[int, int], tuple[str, list[str]]] = {
    (0, 1): (
        "Early Editor Foundation",
        [
            "Initial lightweight editor core",
            "Basic syntax highlighting",
            "First SwiftUI editor interface",
            "Early file handling",
        ],
    ),
    (0, 2): (
        "Core Editing",
        [
            "Regex Find & Replace",
            "Bracket helper",
            "Improved syntax highlighting",
            "Faster editor rendering",
        ],
    ),
    (0, 3): (
        "Projects",
        [
            "Project sidebar navigation",
            "Recursive folder support",
            "Quick Open workflow",
            "Better file loading performance",
        ],
    ),
    (0, 4): (
        "Cross-Platform",
        [
            "iPadOS + iOS workflow parity",
            "Toolbar and keyboard polish",
            "Reliability and performance hardening",
            "Cross-platform Save As support",
        ],
    ),
    (0, 5): (
        "Editor Intelligence",
        [
            "Inline code completion",
            "Optional AI assistance",
            "Markdown preview templates",
            "Diagnostics and runtime controls",
        ],
    ),
}

COLOR_PALETTE = ["#49C6FF", "#66E3FF", "#9F6BFF", "#FF6FD8", "#FF5CA8", "#22C55E", "#F59E0B", "#06B6D4", "#A855F7"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Update release history SVG timelines.")
    p.add_argument("tag", nargs="?", help="Optional release tag context (e.g. v0.6.0).")
    p.add_argument("--check", action="store_true", help="Fail when output files are outdated.")
    return p.parse_args()


def parse_tag(raw: str) -> tuple[int, int, int]:
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", raw.strip())
    if not m:
        raise ValueError(f"Invalid tag: {raw}")
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def load_sections(changelog: str) -> list[ReleaseSection]:
    pattern = re.compile(
        r"^## \[(v(\d+)\.(\d+)\.(\d+))\] - [0-9]{4}-[0-9]{2}-[0-9]{2}\n(?P<body>.*?)(?=^## \[|\Z)",
        flags=re.M | re.S,
    )
    sections: list[ReleaseSection] = []
    for m in pattern.finditer(changelog):
        sections.append(
            ReleaseSection(
                tag=m.group(1),
                major=int(m.group(2)),
                minor=int(m.group(3)),
                patch=int(m.group(4)),
                body=m.group("body").strip(),
            )
        )
    return sections


def minor_key(major: int, minor: int) -> tuple[int, int]:
    return (major, minor)


def latest_section_by_minor(sections: list[ReleaseSection]) -> dict[tuple[int, int], ReleaseSection]:
    out: dict[tuple[int, int], ReleaseSection] = {}
    for section in sections:
        key = minor_key(section.major, section.minor)
        prev = out.get(key)
        if prev is None or section.patch > prev.patch:
            out[key] = section
    return out


def extract_bullets(body: str, limit: int = 4) -> list[str]:
    bullets: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            text = stripped[2:]
            text = re.sub(r"`([^`]+)`", r"\1", text)
            text = re.sub(r"\[[^\]]+\]\([^)]+\)", "", text).strip()
            if text:
                bullets.append(text)
        if len(bullets) >= limit:
            break
    return bullets


def milestone_title_from_section(section: ReleaseSection) -> str:
    body = section.body
    heading_match = re.search(r"^### ([^\n]+)$", body, flags=re.M)
    if heading_match:
        heading = heading_match.group(1).strip()
        if heading.lower() not in {"added", "improved", "fixed"}:
            return heading
    return f"Release line {section.major}.{section.minor}"


def choose_current_minor(sections: list[ReleaseSection], explicit_tag: str | None) -> tuple[int, int]:
    if explicit_tag:
        major, minor, _ = parse_tag(explicit_tag)
        return major, minor
    stable = [s for s in sections if "-" not in s.tag]
    if not stable:
        return (0, 5)
    latest = max(stable, key=lambda s: (s.major, s.minor, s.patch))
    return latest.major, latest.minor


def build_completed_minors(current: tuple[int, int], by_minor: dict[tuple[int, int], ReleaseSection]) -> list[tuple[int, int]]:
    seeds = set(SEED_MINOR_TITLES.keys())
    known = set(by_minor.keys()) | seeds
    completed = [m for m in known if m <= current]
    completed.sort()
    if len(completed) > 8:
        completed = completed[-8:]
    return completed


def build_future_minors(current: tuple[int, int], completed: list[tuple[int, int]]) -> list[tuple[int, int]]:
    major, minor = current
    candidates = [(major, minor + 1), (major, minor + 2), (major + 1, 0)]
    out: list[tuple[int, int]] = []
    completed_set = set(completed)
    for c in candidates:
        if c not in completed_set and c not in out:
            out.append(c)
    return out[:3]


def format_minor_label(m: tuple[int, int]) -> str:
    return f"{m[0]}.{m[1]}"


def wrap_lines(text: str, width: int, max_lines: int) -> list[str]:
    wrapped = textwrap.wrap(text, width=width) or [text]
    return wrapped[:max_lines]


def milestone_for_minor(
    m: tuple[int, int],
    by_minor: dict[tuple[int, int], ReleaseSection],
    is_future: bool,
    color: str,
) -> Milestone:
    label = format_minor_label(m)
    if is_future:
        major, minor = m
        if minor == 0:
            title = "Next Major Foundation"
            bullets = [
                "Platform + architecture step-up",
                "Roadmap themes converge",
                "Migration guidance in release notes",
            ]
        else:
            title = "Upcoming Milestone"
            bullets = [
                "Planned roadmap milestone",
                "UX + reliability polishing",
                "Scope refined via issue feedback",
            ]
        return Milestone(label=label, title=title, bullets=bullets, is_future=True, color=color)

    if m in SEED_MINOR_TITLES:
        title, bullets = SEED_MINOR_TITLES[m]
        return Milestone(label=label, title=title, bullets=bullets, is_future=False, color=color)

    section = by_minor.get(m)
    if section is None:
        return Milestone(
            label=label,
            title=f"Release line {label}",
            bullets=["See CHANGELOG for details."],
            is_future=False,
            color=color,
        )
    bullets = extract_bullets(section.body, limit=4) or ["See CHANGELOG for details."]
    title = milestone_title_from_section(section)
    return Milestone(label=label, title=title, bullets=bullets, is_future=False, color=color)


def render_svg(milestones: list[Milestone], dark: bool) -> str:
    n = len(milestones)
    card_w = 300
    card_h = 470
    gap = 52
    margin = 110
    width = max(2050, margin * 2 + n * card_w + (n - 1) * gap)
    height = 1080
    timeline_y = 800
    card_y = 260

    if dark:
        bg_stops = ("#050A2A", "#1B1850", "#41123A")
        title_fill = "#FFFFFF"
        subtitle_fill = "#DFE8FF"
        card_fill = "rgba(255,255,255,0.06)"
        text_main = "#F3F7FF"
        text_body = "#E7EFFF"
        divider = "#DBE6FF"
        shadow_opacity = "0.35"
    else:
        bg_stops = ("#F6FBFF", "#EEF2FF", "#F9EEF6")
        title_fill = "#0F172A"
        subtitle_fill = "#334155"
        card_fill = "rgba(255,255,255,0.78)"
        text_main = "#0F172A"
        text_body = "#1F2937"
        divider = "#94A3B8"
        shadow_opacity = "0.12"

    completed = [m for m in milestones if not m.is_future]
    start_label = completed[0].label if completed else milestones[0].label
    end_label = completed[-1].label if completed else milestones[0].label
    subtitle = f"Release History · Versions {start_label} – {end_label} + upcoming"

    out: list[str] = []
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">')
    out.extend(
        [
            "<defs>",
            '<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">',
            f'<stop offset="0%" stop-color="{bg_stops[0]}"/>',
            f'<stop offset="55%" stop-color="{bg_stops[1]}"/>',
            f'<stop offset="100%" stop-color="{bg_stops[2]}"/>',
            "</linearGradient>",
            '<linearGradient id="lineGrad" x1="0" y1="0" x2="1" y2="0">',
            '<stop offset="0%" stop-color="#4DD9FF"/>',
            '<stop offset="50%" stop-color="#9D63FF"/>',
            '<stop offset="100%" stop-color="#FF689A"/>',
            "</linearGradient>",
            '<filter id="shadow" x="-20%" y="-20%" width="140%" height="160%">',
            f'<feDropShadow dx="0" dy="12" stdDeviation="18" flood-color="#000000" flood-opacity="{shadow_opacity}"/>',
            "</filter>",
            "</defs>",
            '<rect width="100%" height="100%" fill="url(#bg)"/>',
            f'<text x="{margin}" y="110" fill="{title_fill}" font-size="62" font-weight="700" font-family="Arial, Helvetica, sans-serif">Neon Vision Editor</text>',
            f'<text x="{margin}" y="165" fill="{subtitle_fill}" font-size="30" font-family="Arial, Helvetica, sans-serif">{escape(subtitle)}</text>',
            f'<line x1="{margin + 70}" y1="{timeline_y}" x2="{width - margin + 10}" y2="{timeline_y}" stroke="url(#lineGrad)" stroke-width="8" stroke-linecap="round"/>',
        ]
    )

    for i, m in enumerate(milestones):
        cx = margin + i * (card_w + gap) + card_w / 2
        rect_x = cx - card_w / 2
        stroke_dash = ' stroke-dasharray="12 10"' if m.is_future else ""
        out.extend(
            [
                '<g filter="url(#shadow)">',
                (
                    f'<rect x="{rect_x:.1f}" y="{card_y}" width="{card_w}" height="{card_h}" rx="30" '
                    f'fill="{card_fill}" stroke="{m.color}" stroke-width="3"{stroke_dash}/>'
                ),
                "</g>",
                f'<text x="{cx:.1f}" y="{card_y + 70}" text-anchor="middle" fill="{text_main}" font-size="48" font-weight="700" font-family="Arial, Helvetica, sans-serif">{escape(m.label)}</text>',
            ]
        )

        title_lines = wrap_lines(m.title, width=20, max_lines=2)
        for idx, line in enumerate(title_lines):
            out.append(
                f'<text x="{rect_x + 24:.1f}" y="{card_y + 130 + idx * 36}" fill="{text_main}" font-size="30" font-weight="600" font-family="Arial, Helvetica, sans-serif">{escape(line)}</text>'
            )
        divider_y = card_y + 176
        out.append(
            f'<line x1="{rect_x + 24:.1f}" y1="{divider_y}" x2="{rect_x + card_w - 24:.1f}" y2="{divider_y}" stroke="{divider}" stroke-opacity="0.4"/>'
        )

        for bi, bullet in enumerate(m.bullets[:4]):
            bullet_lines = wrap_lines(bullet, width=34, max_lines=2)
            y = divider_y + 50 + bi * 70
            out.append(
                f'<text x="{rect_x + 24:.1f}" y="{y}" fill="{text_body}" font-size="20" font-family="Arial, Helvetica, sans-serif">• {escape(bullet_lines[0])}</text>'
            )
            if len(bullet_lines) > 1:
                out.append(
                    f'<text x="{rect_x + 40:.1f}" y="{y + 28}" fill="{text_body}" font-size="20" font-family="Arial, Helvetica, sans-serif">{escape(bullet_lines[1])}</text>'
                )

        node_dash = ' stroke-dasharray="6 6"' if m.is_future else ""
        fill_opacity = "0.5" if m.is_future else "0.85"
        out.append(f'<circle cx="{cx:.1f}" cy="{timeline_y}" r="26" fill="{m.color}" fill-opacity="{fill_opacity}"{node_dash}/>')
        out.append(
            f'<text x="{cx:.1f}" y="{timeline_y + 70}" text-anchor="middle" fill="{title_fill if dark else "#0F172A"}" font-size="28" font-family="Arial, Helvetica, sans-serif">{escape(m.label)}</text>'
        )
        if m.is_future:
            out.append(
                f'<text x="{cx:.1f}" y="{timeline_y + 102}" text-anchor="middle" fill="{subtitle_fill}" font-size="18" font-family="Arial, Helvetica, sans-serif">upcoming</text>'
            )

    out.append("</svg>")
    return "\n".join(out) + "\n"


def main() -> int:
    args = parse_args()
    changelog = CHANGELOG.read_text(encoding="utf-8")
    sections = load_sections(changelog)
    by_minor = latest_section_by_minor(sections)

    current = choose_current_minor(sections, args.tag)
    completed = build_completed_minors(current, by_minor)
    future = build_future_minors(current, completed)
    pairs = completed + future
    milestones = [
        milestone_for_minor(pair, by_minor, pair in future, COLOR_PALETTE[i % len(COLOR_PALETTE)])
        for i, pair in enumerate(pairs)
    ]

    dark_svg = render_svg(milestones, dark=True)
    light_svg = render_svg(milestones, dark=False)

    dark_before = DARK_SVG.read_text(encoding="utf-8") if DARK_SVG.exists() else ""
    light_before = LIGHT_SVG.read_text(encoding="utf-8") if LIGHT_SVG.exists() else ""
    changed = dark_before != dark_svg or light_before != light_svg
    if args.check:
        if changed:
            print("Release history SVGs are outdated. Run scripts/update_release_history_svg.py")
            return 1
        return 0

    DARK_SVG.write_text(dark_svg, encoding="utf-8")
    LIGHT_SVG.write_text(light_svg, encoding="utf-8")
    print(f"Updated release history SVGs for current milestone {current[0]}.{current[1]} with {len(future)} upcoming nodes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
