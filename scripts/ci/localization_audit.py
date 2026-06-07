#!/usr/bin/env python3
"""Validate Localizable.strings key and placeholder consistency."""

from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCALE_ROOT = ROOT / "Neon Vision Editor"
ENTRY_RE = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[@dfiuqxXsScCpPeEgGaA]|%%")


def strings_files() -> dict[str, pathlib.Path]:
    return {path.parent.name: path for path in sorted(LOCALE_ROOT.glob("*.lproj/Localizable.strings"))}


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


def main() -> int:
    files = strings_files()
    if not files:
        print("No Localizable.strings files found.", file=sys.stderr)
        return 1

    parsed: dict[str, dict[str, str]] = {}
    failed = False
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

    if failed:
        return 1

    print(f"Localization audit passed for {len(files)} locales and {len(all_keys)} keys.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
