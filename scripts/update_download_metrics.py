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
import os
import pathlib
import re
import subprocess
import sys
import urllib.request
import urllib.parse
from dataclasses import dataclass


ROOT = pathlib.Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
SVG_PATH = ROOT / "docs" / "images" / "release-download-trend.svg"
OWNER = "h3pdesign"
REPO = "Neon-Vision-Editor"
API_URL = f"https://api.github.com/repos/{OWNER}/{REPO}/releases?per_page=100"
CLONES_API_URL = f"https://api.github.com/repos/{OWNER}/{REPO}/traffic/clones"
VIEWS_API_URL = f"https://api.github.com/repos/{OWNER}/{REPO}/traffic/views"
CLONES_WINDOW_DAYS = 14


@dataclass(frozen=True)
class ReleasePoint:
    tag: str
    downloads: int
    published_at: dt.datetime


@dataclass(frozen=True)
class ClonePoint:
    timestamp: dt.datetime
    count: int


@dataclass(frozen=True)
class ViewPoint:
    timestamp: dt.datetime
    count: int


def github_api_get(url: str) -> object:
    base_headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "neon-vision-editor-metrics-updater",
    }
    gh_token = os.environ.get("GH_TOKEN")
    github_token = os.environ.get("GITHUB_TOKEN")
    token_candidates: list[str | None] = []
    if gh_token:
        token_candidates.append(gh_token)
    if github_token and github_token != gh_token:
        token_candidates.append(github_token)
    if not token_candidates:
        token_candidates.append(None)

    last_error: Exception | None = None
    for token in token_candidates:
        headers = dict(base_headers)
        if token:
            headers["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as exc:
            last_error = exc

    if last_error is not None:
        raise last_error
    raise RuntimeError("GitHub API request failed without an error.")


def fetch_releases() -> list[ReleasePoint]:
    payload = github_api_get(API_URL)
    if not isinstance(payload, list):
        raise RuntimeError("Unexpected GitHub releases payload.")

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


def fetch_clone_traffic() -> tuple[list[ClonePoint], int | None, dt.datetime | None]:
    try:
        payload = github_api_get(CLONES_API_URL)
    except Exception:
        payload = None
    if payload is None:
        # Local fallback: reuse authenticated gh CLI when direct API auth is unavailable.
        try:
            out = subprocess.run(
                ["gh", "api", f"repos/{OWNER}/{REPO}/traffic/clones"],
                check=True,
                capture_output=True,
                text=True,
                timeout=20,
            )
            payload = json.loads(out.stdout)
        except Exception:
            return [], None, None
    if not isinstance(payload, dict):
        return [], None, None

    raw_points = payload.get("clones", [])
    if not isinstance(raw_points, list):
        raw_points = []

    points: list[ClonePoint] = []
    for point in raw_points:
        if not isinstance(point, dict):
            continue
        ts_raw = point.get("timestamp")
        count = point.get("count", 0)
        if not isinstance(ts_raw, str) or not isinstance(count, int):
            continue
        try:
            ts = dt.datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
        except ValueError:
            continue
        points.append(ClonePoint(timestamp=ts, count=count))

    points.sort(key=lambda p: p.timestamp)
    unique_total = payload.get("uniques")
    total_count = payload.get("count")
    latest_timestamp = points[-1].timestamp if points else None
    if isinstance(unique_total, int):
        return points, unique_total, latest_timestamp
    if isinstance(total_count, int):
        return points, total_count, latest_timestamp
    return points, None, latest_timestamp


def fetch_view_traffic() -> tuple[list[ViewPoint], int | None, dt.datetime | None]:
    try:
        payload = github_api_get(VIEWS_API_URL)
    except Exception:
        payload = None
    if payload is None:
        # Local fallback: reuse authenticated gh CLI when direct API auth is unavailable.
        try:
            out = subprocess.run(
                ["gh", "api", f"repos/{OWNER}/{REPO}/traffic/views"],
                check=True,
                capture_output=True,
                text=True,
                timeout=20,
            )
            payload = json.loads(out.stdout)
        except Exception:
            return [], None, None
    if not isinstance(payload, dict):
        return [], None, None

    raw_points = payload.get("views", [])
    if not isinstance(raw_points, list):
        raw_points = []

    points: list[ViewPoint] = []
    for point in raw_points:
        if not isinstance(point, dict):
            continue
        ts_raw = point.get("timestamp")
        count = point.get("count", 0)
        if not isinstance(ts_raw, str) or not isinstance(count, int):
            continue
        try:
            ts = dt.datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
        except ValueError:
            continue
        points.append(ViewPoint(timestamp=ts, count=count))

    points.sort(key=lambda p: p.timestamp)
    unique_total = payload.get("uniques")
    total_count = payload.get("count")
    latest_timestamp = points[-1].timestamp if points else None
    if isinstance(unique_total, int):
        return points, unique_total, latest_timestamp
    if isinstance(total_count, int):
        return points, total_count, latest_timestamp
    return points, None, latest_timestamp


def y_top(max_value: int, ticks: int = 4) -> int:
    if max_value <= 0:
        return ticks
    rough = max_value / ticks
    magnitude = 10 ** max(0, int(math.log10(max(1, rough))))
    step = max(1, int(math.ceil(rough / magnitude) * magnitude))
    return step * ticks


def generate_svg(points: list[ReleasePoint], clone_total: int, view_total: int, snapshot_date: str) -> str:
    width = 1200
    height = 620
    left = 130
    right = 1070
    top = 120
    bottom = 320

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
        label_x = 58 if value >= 10 else 68
        y_labels.append(
            f'  <text x="{label_x}" y="{y + 6:.1f}" fill="#9CC3E6" font-size="14" '
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
            f'  <text x="{x - 14:.1f}" y="352" fill="#D7E8F8" font-size="13" '
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

    clone_panel: list[str] = [
        '  <rect x="58" y="378" width="1084" height="210" rx="12" fill="#0A1A2B" stroke="#2A4762" stroke-width="1"/>',
        f'  <text x="84" y="412" fill="#E6F3FF" font-size="20" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-weight="700">Repository Traffic (last {CLONES_WINDOW_DAYS} days)</text>',
    ]
    panel_left = 86
    panel_right = 1110
    clone_bar_top = 450
    clone_bar_bottom = 476
    view_bar_top = 510
    view_bar_bottom = 536
    track_width = panel_right - panel_left
    traffic_scale_max = max(100, y_top(max(1, clone_total, view_total), ticks=4))
    clone_fill_ratio = min(1.0, clone_total / traffic_scale_max)
    clone_fill_width = max(8.0, track_width * clone_fill_ratio)
    view_fill_ratio = min(1.0, view_total / traffic_scale_max)
    view_fill_width = max(8.0, track_width * view_fill_ratio)
    mid_value = traffic_scale_max // 2
    mid_x = panel_left + (track_width * 0.5)
    clone_panel.extend(
        [
            f'  <text x="{panel_left}" y="{clone_bar_top - 12}" fill="#C4B5FD" font-size="15" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-weight="600">Unique cloners: {clone_total}</text>',
            f'  <rect x="{panel_left}" y="{clone_bar_top}" width="{track_width}" height="{clone_bar_bottom - clone_bar_top}" rx="10" fill="#15263A" stroke="#2B4255" stroke-width="1"/>',
            f'  <rect x="{panel_left}" y="{clone_bar_top}" width="{clone_fill_width:.1f}" height="{clone_bar_bottom - clone_bar_top}" rx="10" fill="url(#cloneFill)"/>',
            f'  <text x="{panel_left}" y="{view_bar_top - 12}" fill="#7DD3FC" font-size="15" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-weight="600">Unique visitors: {view_total}</text>',
            f'  <rect x="{panel_left}" y="{view_bar_top}" width="{track_width}" height="{view_bar_bottom - view_bar_top}" rx="10" fill="#15263A" stroke="#2B4255" stroke-width="1"/>',
            f'  <rect x="{panel_left}" y="{view_bar_top}" width="{view_fill_width:.1f}" height="{view_bar_bottom - view_bar_top}" rx="10" fill="url(#viewFill)"/>',
            f'  <line x1="{panel_left}" y1="{clone_bar_top - 20}" x2="{panel_left}" y2="{view_bar_bottom + 12}" stroke="#436280" stroke-width="1"/>',
            f'  <line x1="{mid_x:.1f}" y1="{clone_bar_top - 20}" x2="{mid_x:.1f}" y2="{view_bar_bottom + 12}" stroke="#436280" stroke-width="1"/>',
            f'  <line x1="{panel_right}" y1="{clone_bar_top - 20}" x2="{panel_right}" y2="{view_bar_bottom + 12}" stroke="#436280" stroke-width="1"/>',
            f'  <text x="{panel_left - 2}" y="{view_bar_bottom + 30}" text-anchor="start" fill="#9CC3E6" font-size="13" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">0</text>',
            f'  <text x="{mid_x:.1f}" y="{view_bar_bottom + 30}" text-anchor="middle" fill="#9CC3E6" font-size="13" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">{mid_value}</text>',
            f'  <text x="{panel_right + 2}" y="{view_bar_bottom + 30}" text-anchor="end" fill="#9CC3E6" font-size="13" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">{traffic_scale_max}</text>',
            f'  <text x="{panel_left}" y="{view_bar_bottom + 52}" fill="#9CC3E6" font-size="14" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">Shared scale: 0 to {traffic_scale_max} events in the last {CLONES_WINDOW_DAYS} days.</text>',
        ]
    )

    return """<svg width="1200" height="620" viewBox="0 0 1200 620" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="title desc">
  <title id="title">GitHub Release Downloads and Traffic Trend</title>
  <desc id="desc">Line chart of release downloads with 14-day traffic bars for clones and views.</desc>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1200" y2="620" gradientUnits="userSpaceOnUse">
      <stop stop-color="#061423"/>
      <stop offset="1" stop-color="#041C16"/>
    </linearGradient>
    <linearGradient id="line" x1="130" y1="86" x2="1070" y2="340" gradientUnits="userSpaceOnUse">
      <stop stop-color="#00C2FF"/>
      <stop offset="0.55" stop-color="#00E2B8"/>
      <stop offset="1" stop-color="#8CFF5A"/>
    </linearGradient>
    <linearGradient id="cloneFill" x1="86" y1="450" x2="1110" y2="450" gradientUnits="userSpaceOnUse">
      <stop stop-color="#7C3AED"/>
      <stop offset="1" stop-color="#C084FC"/>
    </linearGradient>
    <linearGradient id="viewFill" x1="86" y1="482" x2="1110" y2="482" gradientUnits="userSpaceOnUse">
      <stop stop-color="#0EA5E9"/>
      <stop offset="1" stop-color="#7DD3FC"/>
    </linearGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="4" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <rect width="1200" height="620" rx="18" fill="url(#bg)"/>
  <rect x="24" y="24" width="1152" height="572" rx="14" stroke="#2A4762" stroke-width="1.5"/>

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

  <text x="776" y="56" fill="#D7F7FF" font-size="15" font-family="SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">Release trend line with highlighted points</text>
CLONE_PANEL
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
    ).replace(
        "CLONE_PANEL", "\n".join(clone_panel)
    )


def parse_existing_clone_total(content: str) -> int | None:
    match = re.search(r"Git clones \(last \d+ days\): <strong>(\d+)</strong>\.", content)
    if not match:
        return None
    try:
        return int(match.group(1))
    except ValueError:
        return None


def parse_existing_view_total(content: str) -> int | None:
    match = re.search(r"GitHub views \(last \d+ days\): <strong>(\d+)</strong>\.", content)
    if not match:
        return None
    try:
        return int(match.group(1))
    except ValueError:
        return None


def shields_badge(label: str, message: str, color: str, style: str = "for-the-badge") -> str:
    query = urllib.parse.urlencode(
        {
            "label": label,
            "message": message,
            "color": color,
            "style": style,
        }
    )
    return f"https://img.shields.io/static/v1?{query}"


def update_readme(
    content: str,
    latest_tag: str,
    total_downloads: int,
    clone_total: int,
    clone_snapshot_utc: str,
    view_total: int,
    view_snapshot_utc: str,
    today: str,
) -> str:
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
        r'(?m)^<p align="center">Git clones \(last \d+ days\): <strong>\d+</strong>\.</p>\s*$',
        "",
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center">GitHub views \(last \d+ days\): <strong>\d+</strong>\.</p>\s*$',
        "",
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center">Clone data snapshot \(UTC\): <strong>[^<]+</strong>\.</p>\s*$',
        "",
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center">View data snapshot \(UTC\): <strong>[^<]+</strong>\.</p>\s*$',
        "",
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center">Snapshot total downloads: <strong>\d+</strong> across releases\.</p>\s*$',
        "",
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center"><strong>Release Download Trend</strong></p>$',
        '<p align="center"><strong>Release Download + Traffic Trend</strong></p>',
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center"><strong>Release Download \+ Clone Trend</strong></p>$',
        '<p align="center"><strong>Release Download + Traffic Trend</strong></p>',
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center"><em>Styled line chart with highlighted points shows per-release totals and trend direction\.</em></p>$',
        '<p align="center"><em>Styled line chart shows per-release totals with 14-day traffic counters for clones and views.</em></p>',
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center"><em>Styled line chart shows per-release totals plus a 14-day git clone sparkline\.</em></p>$',
        '<p align="center"><em>Styled line chart shows per-release totals with 14-day traffic counters for clones and views.</em></p>',
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center"><em>Styled line chart shows per-release totals plus a 14-day git clone volume strip\.</em></p>$',
        '<p align="center"><em>Styled line chart shows per-release totals with 14-day traffic counters for clones and views.</em></p>',
        content,
    )
    content = re.sub(
        r'(?m)^<p align="center"><em>Styled line chart shows per-release totals plus a scaled 14-day git clone volume bar\.</em></p>$',
        '<p align="center"><em>Styled line chart shows per-release totals with 14-day traffic counters for clones and views.</em></p>',
        content,
    )
    content = re.sub(
        r'(?s)<p align="center">\s*<img alt="(?:Git clones|Unique cloners) \(14d\)".*?</p>\s*'
        r'<p align="center">\s*<img alt="Clone snapshot \(UTC\)".*?</p>\s*',
        "",
        content,
    )
    traffic_badges = (
        "<p align=\"center\">\n"
        f"  <img alt=\"Unique cloners (14d)\" src=\"{shields_badge('Unique cloners (14d)', str(clone_total), '7C3AED')}\">\n"
        f"  <img alt=\"Unique visitors (14d)\" src=\"{shields_badge('Unique visitors (14d)', str(view_total), '0EA5E9')}\">\n"
        "</p>\n"
        "<p align=\"center\">\n"
        f"  <img alt=\"Clone snapshot (UTC)\" src=\"{shields_badge('Clone snapshot (UTC)', clone_snapshot_utc, '334155', style='flat-square')}\">\n"
        f"  <img alt=\"View snapshot (UTC)\" src=\"{shields_badge('View snapshot (UTC)', view_snapshot_utc, '334155', style='flat-square')}\">\n"
        "</p>"
    )
    content = content.replace(
        '<p align="center"><em>Styled line chart shows per-release totals with 14-day traffic counters for clones and views.</em></p>',
        '<p align="center"><em>Styled line chart shows per-release totals with 14-day traffic counters for clones and views.</em></p>\n'
        + traffic_badges,
        1,
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
    content = re.sub(r"\n</p>\n{3,}## Project Docs", "\n</p>\n\n## Project Docs", content)
    return content


def total_downloads_for_scale(points: list[ReleasePoint]) -> int:
    return max(1, sum(point.downloads for point in points))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh README download metrics and chart.")
    parser.add_argument("--check", action="store_true", help="Fail if files are not up-to-date.")
    parser.add_argument(
        "--require-traffic-api",
        action="store_true",
        help="Fail if clone/view traffic API data cannot be fetched.",
    )
    parser.add_argument(
        "--require-clone-api",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    require_traffic_api = args.require_traffic_api or args.require_clone_api
    update_timestamp_utc = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d %H:%M")
    releases = fetch_releases()
    clone_points, clone_total_api, clone_latest_timestamp = fetch_clone_traffic()
    view_points, view_total_api, view_latest_timestamp = fetch_view_traffic()
    releases_desc = sorted(releases, key=lambda r: r.published_at, reverse=True)
    latest = releases_desc[0]
    total_downloads = sum(r.downloads for r in releases_desc)

    trend_points = sorted(releases_desc[:8], key=lambda r: r.published_at)
    snapshot_date = dt.date.today().isoformat()

    readme_before = README.read_text(encoding="utf-8")
    existing_clone_total = parse_existing_clone_total(readme_before)
    existing_view_total = parse_existing_view_total(readme_before)
    if require_traffic_api and (clone_total_api is None or clone_latest_timestamp is None):
        print(
            "Clone traffic API unavailable. Refusing to reuse stale README clone metrics.",
            file=sys.stderr,
        )
        return 1
    if require_traffic_api and (view_total_api is None or view_latest_timestamp is None):
        print(
            "View traffic API unavailable. Refusing to reuse stale README view metrics.",
            file=sys.stderr,
        )
        return 1
    if clone_total_api is None:
        print(
            "Warning: clone traffic API unavailable; reusing existing README clone total.",
            file=sys.stderr,
        )
    clone_total = clone_total_api if clone_total_api is not None else (existing_clone_total or 0)
    clone_snapshot_utc = update_timestamp_utc
    if view_total_api is None:
        print(
            "Warning: view traffic API unavailable; reusing existing README view total.",
            file=sys.stderr,
        )
    view_total = view_total_api if view_total_api is not None else (existing_view_total or 0)
    view_snapshot_utc = update_timestamp_utc
    svg = generate_svg(trend_points, clone_total, view_total, snapshot_date)
    readme_after = update_readme(
        readme_before,
        latest_tag=latest.tag,
        total_downloads=total_downloads,
        clone_total=clone_total,
        clone_snapshot_utc=clone_snapshot_utc,
        view_total=view_total,
        view_snapshot_utc=view_snapshot_utc,
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
        f"clones14d={clone_total} points={len(trend_points)} clone_points={len(clone_points)} "
        f"clone_snapshot_utc={clone_snapshot_utc} views14d={view_total} "
        f"view_points={len(view_points)} view_snapshot_utc={view_snapshot_utc}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
