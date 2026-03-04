#!/usr/bin/env python3
"""Refresh README download badges/text and regenerate the release trend SVG.

Usage:
  scripts/update_download_metrics.py
  scripts/update_download_metrics.py --check
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import pathlib
import re
import sys
import urllib.request
from dataclasses import dataclass


ROOT = pathlib.Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
SVG_PATH = ROOT / "docs" / "images" / "release-download-trend.svg"
OWNER = "h3pdesign"
REPO = "Neon-Vision-Editor"
API_URL = f"https://api.github.com/repos/{OWNER}/{REPO}/releases?per_page=100"


@dataclass(frozen=True)
class ReleasePoint:
    tag: str
    downloads: int
    published_at: dt.datetime


def fetch_releases() -> list[ReleasePoint]:
    req = urllib.request.Request(
        API_URL,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "neon-vision-editor-metrics-updater",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))

    points: list[ReleasePoint] = []
    for release in payload:
        if release.get("draft"):
            continue
        tag = str(release.get("tag_name", "")).strip()
        published_raw = release.get("published_at")
        if not tag or not published_raw:
            continue
        try:
            published = dt.datetime.fromisoformat(published_raw.replace("Z", "+00:00"))
        except ValueError:
            continue
        assets = release.get("assets", [])
        downloads = 0
        for asset in assets:
            value = asset.get("download_count", 0)
            if isinstance(value, int):
                downloads += value
        points.append(ReleasePoint(tag=tag, downloads=downloads, published_at=published))

    if not points:
        raise RuntimeError("No stable releases found from GitHub API.")
    return points


def y_top(max_value: int, ticks: int = 4) -> int:
    if max_value <= 0:
        return ticks
    rough = max_value / ticks
    magnitude = 10 ** max(0, int(math.log10(max(1, rough))))
    step = max(1, int(math.ceil(rough / magnitude) * magnitude))
    return step * ticks


def generate_svg(points: list[ReleasePoint], snapshot_date: str) -> str:
    width = 1200
    height = 460
    left = 130
    right = 1070
    top = 84
    bottom = 340

    max_downloads = max(p.downloads for p in points)
    top_value = y_top(max_downloads, ticks=4)
    if top_value == 0:
        top_value = 4

    span_x = right - left
    span_y = bottom - top
    step_x = span_x / max(1, len(points) - 1)

    coords: list[tuple[float, float]] = []
    for idx, point in enumerate(points):
        x = left + (idx * step_x)
        y = bottom - (point.downloads / top_value) * span_y
        coords.append((x, y))

    grid_lines: list[str] = []
    y_labels: list[str] = []
    for i in range(5):
        value = int((top_value / 4) * i)
        y = bottom - (value / top_value) * span_y if top_value else bottom
        color = "#37566F" if i in (0, 4) else "#2B4255"
        grid_lines.append(
            f'  <line x1="{left}" y1="{y:.1f}" x2="{right}" y2="{y:.1f}" stroke="{color}" stroke-width="1"/>'
        )
        y_labels.append(
            f'  <text x="{78 if value >= 10 else 90}" y="{y + 6:.1f}" fill="#9CC3E6" font-size="14" '
            'font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">'
            f"{value}</text>"
        )

    point_nodes: list[str] = []
    x_labels: list[str] = []
    value_labels: list[str] = []
    colors = ["#00C2FF", "#00D7D2", "#1AE7C0", "#34EDAA", "#47F193", "#5AF57D", "#72FA64", "#8CFF5A"]
    for idx, ((x, y), point) in enumerate(zip(coords, points)):
        fill = colors[idx % len(colors)]
        point_nodes.append(
            f'  <circle cx="{x:.1f}" cy="{y:.1f}" r="7" fill="{fill}" stroke="#D7F7FF" stroke-width="2"/>'
        )
        x_labels.append(
            f'  <text x="{x - 14:.1f}" y="372" fill="#D7E8F8" font-size="13" '
            'font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">'
            f"{point.tag}</text>"
        )
        label_y = y - 14 if y > top + 26 else y + 22
        value_labels.append(
            f'  <text x="{x - 10:.1f}" y="{label_y:.1f}" fill="#D7F7FF" font-size="15" '
            'font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" '
            f'font-weight="600">{point.downloads}</text>'
        )

    polyline_points = " ".join(f"{x:.1f},{y:.1f}" for x, y in coords)

    return """<svg width="1200" height="460" viewBox="0 0 1200 460" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="title desc">
  <title id="title">GitHub Release Downloads Trend</title>
  <desc id="desc">Line chart of release downloads with highlighted points.</desc>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1200" y2="460" gradientUnits="userSpaceOnUse">
      <stop stop-color="#061423"/>
      <stop offset="1" stop-color="#041C16"/>
    </linearGradient>
    <linearGradient id="line" x1="130" y1="86" x2="1070" y2="340" gradientUnits="userSpaceOnUse">
      <stop stop-color="#00C2FF"/>
      <stop offset="0.55" stop-color="#00E2B8"/>
      <stop offset="1" stop-color="#8CFF5A"/>
    </linearGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="4" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <rect width="1200" height="460" rx="18" fill="url(#bg)"/>
  <rect x="24" y="24" width="1152" height="412" rx="14" stroke="#2A4762" stroke-width="1.5"/>

  <text x="70" y="68" fill="#E6F3FF" font-size="30" font-family="SF Pro Display, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-weight="700">GitHub Release Downloads</text>
  <text x="70" y="96" fill="#9CC3E6" font-size="18" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">Snapshot: SNAPSHOT_DATE</text>

GRID_LINES
Y_LABELS

  <polyline
    points="POLYLINE_POINTS"
    fill="none"
    stroke="url(#line)"
    stroke-width="5"
    stroke-linecap="round"
    stroke-linejoin="round"
    filter="url(#glow)"
  />

POINT_NODES
X_LABELS
VALUE_LABELS

  <rect x="792" y="24" width="340" height="54" rx="10" fill="#0A2D3B" stroke="#276B84" stroke-width="1.2"/>
  <circle cx="818" cy="51" r="6" fill="#00D6CB"/>
  <text x="838" y="56" fill="#D7F7FF" font-size="15" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">Trend line with highlighted points</text>
</svg>
""".replace("SNAPSHOT_DATE", snapshot_date).replace(
        "GRID_LINES", "\n".join(grid_lines)
    ).replace(
        "Y_LABELS", "\n".join(y_labels)
    ).replace(
        "POLYLINE_POINTS", polyline_points
    ).replace(
        "POINT_NODES", "\n".join(point_nodes)
    ).replace(
        "X_LABELS", "\n".join(x_labels)
    ).replace(
        "VALUE_LABELS", "\n".join(value_labels)
    )


def update_readme(content: str, latest_tag: str, total_downloads: int, today: str) -> str:
    release_badge_line = (
        '  <img alt="{tag} Downloads" '
        'src="https://img.shields.io/github/downloads/h3pdesign/Neon-Vision-Editor/{tag}/total'
        '?style=for-the-badge&label={tag}&color=22C55E">'
    ).format(tag=latest_tag)
    content = re.sub(
        r'(?m)^  <img alt="v[^"]+ Downloads" src="https://img\.shields\.io/github/downloads/h3pdesign/Neon-Vision-Editor/v[^/]+/total\?style=for-the-badge&label=v[^"&]+&color=22C55E">$',
        release_badge_line,
        content,
    )
    content = re.sub(
        r'<p align="center">Snapshot total downloads: <strong>\d+</strong> across releases\.</p>',
        f'<p align="center">Snapshot total downloads: <strong>{total_downloads}</strong> across releases.</p>',
        content,
    )
    content = re.sub(
        r"(?m)^> Latest release: \*\*.*\*\*$",
        f"> Latest release: **{latest_tag}**",
        content,
    )
    content = re.sub(
        r"(?m)^- Latest release: \*\*.*\*\*$",
        f"- Latest release: **{latest_tag}**",
        content,
    )
    content = re.sub(
        r"(?m)^> Last updated \(README\): \*\*.*\*\* for release line \*\*.*\*\*$",
        f"> Last updated (README): **{today}** for release line **{latest_tag}**",
        content,
    )
    if f"label={latest_tag}" not in content:
        raise RuntimeError("README download badge replacement failed.")
    return content


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh README download metrics and chart.")
    parser.add_argument("--check", action="store_true", help="Fail if files are not up-to-date.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    releases = fetch_releases()
    releases_desc = sorted(releases, key=lambda r: r.published_at, reverse=True)
    latest = releases_desc[0]
    total_downloads = sum(r.downloads for r in releases_desc)

    trend_points = sorted(releases_desc[:8], key=lambda r: r.published_at)
    snapshot_date = dt.date.today().isoformat()
    svg = generate_svg(trend_points, snapshot_date)

    readme_before = README.read_text(encoding="utf-8")
    readme_after = update_readme(
        readme_before,
        latest_tag=latest.tag,
        total_downloads=total_downloads,
        today=snapshot_date,
    )

    svg_before = SVG_PATH.read_text(encoding="utf-8") if SVG_PATH.exists() else ""

    changed = (readme_before != readme_after) or (svg_before != svg)
    if args.check:
        if changed:
            print("Download metrics are outdated. Run scripts/update_download_metrics.py", file=sys.stderr)
            return 1
        return 0

    README.write_text(readme_after, encoding="utf-8")
    SVG_PATH.parent.mkdir(parents=True, exist_ok=True)
    SVG_PATH.write_text(svg, encoding="utf-8")
    print(
        f"Updated metrics: latest={latest.tag} ({latest.downloads}) total={total_downloads} "
        f"points={len(trend_points)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
