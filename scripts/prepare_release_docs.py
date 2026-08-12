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
import html
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
CHANGELOG = ROOT / "CHANGELOG.md"
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
    "de": [
        ("Stabile Symbolleiste und Einstellungen", "Bündelt die Korrekturen aus v1.3.1 und stabilisiert das Einstellungenfenster auf dem Mac sowie die sichtbare Sprachanzeige.", ["Symbolleiste", "Einstellungen", "macOS"]),
        ("Sichtbare Toolbar-Statuswerte", "Zeigt die aktive Werkzeugleisten-Voreinstellung mit Symbol und Kurzbezeichnung und zentriert die Sprachstatusanzeige.", ["Symbolleiste", "macOS", "iPad"]),
        ("Quick Look passt sich dem Erscheinungsbild an", "Stimmt Hintergrund, Syntaxfarben und Zeilennummern auf den hellen oder dunklen macOS-Modus ab.", ["Quick Look", "macOS", "Darstellung"]),
        ("Quick Look und Einstellungen werden stabiler", "Verfeinert Quick Look und die Größenanpassung des macOS-Einstellungsfensters für einen ruhigeren Arbeitsablauf.", ["Quick Look", "Einstellungen", "macOS"]),
        ("Toolbar und Quick Look bleiben lesbar", "Stellt die Kurzbezeichnungen der Toolbar wieder her und bündelt Quick Look in einem eigenständigen, überprüfbaren Build-Schema.", ["Symbolleiste", "Quick Look", "macOS"]),
    ],
    "da": [
        ("Stabil værktøjslinje og indstillinger", "Samler rettelserne fra v1.3.1 og stabiliserer indstillingsvinduet på Mac samt den synlige sprogstatus.", ["Værktøjslinje", "Indstillinger", "macOS"]),
        ("Synlige værktøjslinjestatusser", "Viser den aktive værktøjslinjeforudindstilling med ikon og kort navn og centrerer sprogstatussen.", ["Værktøjslinje", "macOS", "iPad"]),
        ("Quick Look følger udseendet", "Tilpasser baggrund, syntaksfarver og linjenumre til macOS i lys eller mørk tilstand.", ["Quick Look", "macOS", "Udseende"]),
        ("Quick Look og indstillinger bliver mere stabile", "Forfiner Quick Look og størrelsestilpasningen af macOS-indstillingsvinduet for et roligere arbejdsforløb.", ["Quick Look", "Indstillinger", "macOS"]),
        ("Værktøjslinje og Quick Look forbliver læselige", "Gendanner værktøjslinjens korte etiketter og samler Quick Look i et selvstændigt, verificerbart byggeskema.", ["Værktøjslinje", "Quick Look", "macOS"]),
    ],
    "fr": [
        ("Barre d’outils et réglages stables", "Regroupe les correctifs de la v1.3.1 et stabilise la fenêtre Réglages sur Mac ainsi que l’état de langue visible.", ["Barre d’outils", "Réglages", "macOS"]),
        ("États visibles de la barre d’outils", "Affiche le préréglage actif avec une icône et un nom court et centre l’état de langue.", ["Barre d’outils", "macOS", "iPad"]),
        ("Quick Look suit l’apparence", "Adapte le fond, les couleurs de syntaxe et les numéros de ligne au mode clair ou sombre de macOS.", ["Quick Look", "macOS", "Apparence"]),
        ("Quick Look et les réglages gagnent en stabilité", "Affine Quick Look et l’adaptation de taille de la fenêtre Réglages sur macOS pour un flux de travail plus calme.", ["Quick Look", "Réglages", "macOS"]),
        ("Barre d’outils et Quick Look restent lisibles", "Restaure les libellés courts de la barre d’outils et regroupe Quick Look dans un schéma de build autonome et vérifiable.", ["Barre d’outils", "Quick Look", "macOS"]),
    ],
    "es": [
        ("Barra de herramientas y ajustes estables", "Reúne las correcciones de la v1.3.1 y estabiliza la ventana Ajustes en Mac y el estado de idioma visible.", ["Barra de herramientas", "Ajustes", "macOS"]),
        ("Estados visibles de la barra", "Muestra el preajuste activo con icono y nombre corto y centra el estado de idioma.", ["Barra de herramientas", "macOS", "iPad"]),
        ("Quick Look sigue la apariencia", "Adapta el fondo, los colores de sintaxis y los números de línea al modo claro u oscuro de macOS.", ["Quick Look", "macOS", "Apariencia"]),
        ("Quick Look y Ajustes ganan estabilidad", "Perfecciona Quick Look y el ajuste de tamaño de la ventana Ajustes de macOS para un flujo de trabajo más tranquilo.", ["Quick Look", "Ajustes", "macOS"]),
        ("La barra y Quick Look siguen siendo legibles", "Restaura las etiquetas abreviadas de la barra y reúne Quick Look en un esquema de compilación autónomo y verificable.", ["Barra", "Quick Look", "macOS"]),
    ],
    "ja": [
        ("安定したツールバーと設定", "v1.3.1 の修正をまとめ、Mac の設定ウインドウと表示中の言語状態を安定させます。", ["ツールバー", "設定", "macOS"]),
        ("見やすいツールバー状態", "有効なツールバー設定をアイコンと短い名前で表示し、言語状態を中央に配置します。", ["ツールバー", "macOS", "iPad"]),
        ("Quick Look の外観対応", "背景、構文色、行番号を macOS のライト／ダークモードに合わせます。", ["Quick Look", "macOS", "外観"]),
        ("Quick Look と設定がさらに安定", "Quick Look と macOS 設定ウインドウのサイズ調整を改善し、より落ち着いた作業環境にします。", ["Quick Look", "設定", "macOS"]),
        ("ツールバーと Quick Look の可読性を維持", "ツールバーの短いラベルを復元し、Quick Look を独立した検証可能なビルドスキームにまとめます。", ["ツールバー", "Quick Look", "macOS"]),
    ],
    "zh-Hans": [
        ("稳定的工具栏与设置", "整合 v1.3.1 的修复，并稳定 Mac 上的设置窗口和可见的语言状态。", ["工具栏", "设置", "macOS"]),
        ("可见的工具栏状态", "使用图标和简称显示当前工具栏预设，并居中显示语言状态。", ["工具栏", "macOS", "iPad"]),
        ("Quick Look 适配外观", "使背景、语法颜色和行号与 macOS 的浅色或深色模式保持一致。", ["Quick Look", "macOS", "外观"]),
        ("Quick Look 与设置更加稳定", "优化 Quick Look 和 macOS 设置窗口的尺寸调整，让工作流程更加稳定。", ["Quick Look", "设置", "macOS"]),
        ("工具栏与 Quick Look 保持清晰", "恢复工具栏的简短标签，并将 Quick Look 整合到独立且可验证的构建方案中。", ["工具栏", "Quick Look", "macOS"]),
    ],
}

README_PREVIOUS_RELEASE_OVERRIDES = {
    "v1.3.3": "v1.3.1",
}


def rebuild_localized_website_release_timeline(website: str, changelog: str, current_tag: str, locale: str) -> str:
    source_entries = release_timeline_entries(changelog, current_tag)
    copy = LOCALIZED_TIMELINE_COPY[locale]
    expected_tags = ("v1.3.2", "v1.3.3", "v1.3.4", "v1.3.5", "v1.3.6")
    if tuple(entry[0] for entry in source_entries) != expected_tags or len(source_entries) != len(copy):
        raise ValueError(f"Localized timeline copy is incomplete for {locale}.")
    entries: list[str] = []
    if len(source_entries) != len(copy):
        raise ValueError("Release timeline source and copy lengths differ.")
    for (tag, date, _, _, _), (title, description, tags) in zip(source_entries, copy):
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
        r"(?m)^(\| \*\*Beta\*\* \| [^|]+ \| [^|]+ \| \[TestFlight Invite\]\(https://testflight\.apple\.com/join/YWB2fGAP\) \| )\*\*v[^*]+\*\*( \| Early access builds for feedback; availability may vary by review state \|)$",
        r"\1**Availability varies**\2",
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
        "--build",
        help="Release build number used by static website fallbacks. Release preparation supplies this after bumping the project build.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tag = normalize_tag(args.tag)
    if args.build is not None and not re.fullmatch(r"[1-9]\d*", args.build):
        raise ValueError("Build number must be a positive integer.")
    release_date = args.date or dt.date.today().isoformat()

    original_changelog = read_text(CHANGELOG)
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
    write_text(WELCOME_TOUR_SWIFT, welcome_src)
    write_text(WEBSITE, website)
    write_text(CHANGELOG_PAGE, changelog_page)
    for locale, path in LOCALIZED_WEBSITES.items():
        write_text(path, localized_websites[locale])
    print("Updated README release references and top 3 release rows.")
    print("Updated English and localized GitHub Pages release fallbacks and timelines from CHANGELOG.")
    print(f"Updated Welcome Tour release page from CHANGELOG for {tag}.")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI friendly
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
