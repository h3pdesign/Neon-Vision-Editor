#!/usr/bin/env python3
"""Validate Localizable.strings key and placeholder consistency."""

from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "Project" / "Sources"
TARGETS = (
    "Neon Vision Editor",
    "Neon Pulse Watch App",
    "Neon Pulse Widget",
    "Neon Vision Editor Share Extension",
    "Neon Vision Editor App Clip",
    "Neon Vision Editor Quick Look",
)
EXPECTED_LOCALES = {"en.lproj", "de.lproj", "da.lproj", "fr.lproj", "es.lproj", "ja.lproj", "zh-Hans.lproj"}
ENTRY_RE = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:lld|ld|[@dfiuqxXsScCpPeEgGaA%])")


def strings_files(root: pathlib.Path) -> dict[str, pathlib.Path]:
    return {path.parent.name: path for path in sorted(root.glob("*.lproj/Localizable.strings"))}


def parse_strings(path: pathlib.Path) -> tuple[dict[str, str], list[tuple[int, str]], list[tuple[int, str]]]:
    entries: dict[str, str] = {}
    duplicates: list[tuple[int, str]] = []
    malformed: list[tuple[int, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
        match = ENTRY_RE.match(line)
        if not match:
            malformed.append((line_number, line))
            continue
        key, value = match.groups()
        if key in entries:
            duplicates.append((line_number, key))
        entries[key] = value
    return entries, duplicates, malformed


def placeholders(value: str) -> list[str]:
    return [item for item in PLACEHOLDER_RE.findall(value) if item != "%%"]


def welcome_tour_keys() -> set[str]:
    source = (SOURCE_ROOT / "Neon Vision Editor/UI/PanelsAndHelpers.swift").read_text(encoding="utf-8")
    pages = source.split("private let pages: [TourPage] = [", 1)[1].split("\n    var body:", 1)[0]
    keys: set[str] = set()
    for line in pages.splitlines():
        match = re.match(r'\s*(?:title: |subtitle: )?"((?:\\.|[^"\\])*)"[, ]*$', line)
        if match:
            keys.add(match.group(1))
            if ": " in match.group(1):
                title, detail = match.group(1).split(": ", 1)
                keys.update((title, detail))
    titles = source.split("private func whatsNewTitle(", 1)[1].split("private func whatsNewDescription(", 1)[0]
    keys.update(re.findall(r'return "((?:\\.|[^"\\])*)"', titles))
    support = source.split("struct SupportPromptSheetView:", 1)[1].split("private let bulletIcons:", 1)[0]
    keys.update(re.findall(r'^\s*"((?:\\.|[^"\\])*)",?$', support, re.MULTILINE))
    return keys


def audit_target(target: str) -> bool:
    files = strings_files(SOURCE_ROOT / target)
    if not files:
        print(f"{target}: no Localizable.strings files found.", file=sys.stderr)
        return False

    parsed: dict[str, dict[str, str]] = {}
    failed = False
    for locale in sorted(EXPECTED_LOCALES - set(files)):
        print(f"{target}: missing {locale}/Localizable.strings", file=sys.stderr)
        failed = True
    for locale, path in files.items():
        entries, duplicates, malformed = parse_strings(path)
        parsed[locale] = entries
        if duplicates:
            failed = True
            for line_number, key in duplicates:
                print(f"{path}:{line_number}: duplicate key {key!r}", file=sys.stderr)
        if malformed:
            failed = True
            for line_number, line in malformed:
                print(f"{path}:{line_number}: malformed strings entry: {line}", file=sys.stderr)

    all_keys = set().union(*(entries.keys() for entries in parsed.values()))
    for locale, entries in parsed.items():
        missing = sorted(all_keys - set(entries))
        if missing:
            failed = True
            print(f"{files[locale]}: missing {len(missing)} localization keys", file=sys.stderr)
            for key in missing:
                print(f"  - {key}", file=sys.stderr)

    reference_locale = "en.lproj" if "en.lproj" in parsed else sorted(parsed)[0]
    reference = parsed[reference_locale]
    source_pattern = re.compile(r'NSLocalizedString\(\s*"((?:\\.|[^"\\])*)"')
    source_keys = set()
    for source in (SOURCE_ROOT / target).rglob("*.swift"):
        source_keys.update(source_pattern.findall(source.read_text(encoding="utf-8")))
    if target == "Neon Vision Editor":
        source_keys.update(welcome_tour_keys())
    untranslated_source_keys = sorted(source_keys - set(reference))
    if untranslated_source_keys:
        failed = True
        print(f"{target}: {len(untranslated_source_keys)} NSLocalizedString keys missing from English catalog", file=sys.stderr)
        for key in untranslated_source_keys:
            print(f"  - {key}", file=sys.stderr)
    for locale, entries in parsed.items():
        for key in sorted(set(reference) & set(entries)):
            expected = placeholders(reference[key])
            actual = placeholders(entries[key])
            if expected != actual:
                failed = True
                print(
                    f"{files[locale]}: placeholder mismatch for {key!r}: "
                    f"{reference_locale}={expected}, {locale}={actual}",
                    file=sys.stderr,
                )

    if not failed:
        print(f"{target}: {len(files)} locales and {len(all_keys)} keys passed.")
    return not failed


def main() -> int:
    results = [audit_target(target) for target in TARGETS]
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
