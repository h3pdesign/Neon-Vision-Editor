#!/usr/bin/env python3
"""Verify the stable performance limits backing the #184 profile protocol."""

from __future__ import annotations

import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASELINE = ROOT / "docs" / "performance-baselines.json"


def fail(message: str) -> None:
    print(f"[performance-budget] {message}", file=sys.stderr)
    raise SystemExit(1)


def require_literal(source: pathlib.Path, pattern: str, expected: int, label: str) -> None:
    text = source.read_text(encoding="utf-8")
    match = re.search(pattern, text)
    if not match:
        fail(f"missing {label} in {source.relative_to(ROOT)}")
    actual = int(match.group(1).replace("_", ""))
    if actual != expected:
        fail(f"{label} is {actual}, expected {expected}")


def main() -> None:
    try:
        baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read baseline: {error}")

    if baseline.get("schemaVersion") != 2:
        fail("unsupported baseline schema")

    fixture = baseline["fixture"]
    if fixture["markdownCards"] < 500 or fixture["pdfCards"] < 500:
        fail("project-preview fixture must cover at least 500 Markdown and PDF cards")
    if fixture["largeFileLines"] < 100_000:
        fail("large-file fixture must contain at least 100000 lines")
    required_syntax_languages = {"swift", "json", "ndjson", "csv", "typescript", "html", "minified-javascript", "markdown"}
    if set(fixture.get("syntaxLanguages", [])) != required_syntax_languages:
        fail("syntax fixture coverage must include every supported large-file performance class")

    benchmark = ROOT / "scripts" / "benchmark_large_file.sh"
    benchmark_text = benchmark.read_text(encoding="utf-8")
    for fixture_name in ("write_html_sample", "write_minified_javascript_sample"):
        if fixture_name not in benchmark_text:
            fail(f"missing {fixture_name} benchmark fixture")

    limits = baseline["enforcedLimits"]
    git_service = ROOT / "Neon Vision Editor" / "Core" / "GitService.swift"
    persistence = ROOT / "Neon Vision Editor" / "UI" / "ContentView+SessionPersistence.swift"
    require_literal(git_service, r"commitDiffFileLimit = (\d+)", limits["gitCommitDiffFileCount"], "Git diff file limit")
    require_literal(git_service, r"commitDiffBlobByteLimit = ([\d_]+)", limits["gitCommitDiffBlobBytes"], "Git diff blob limit")
    require_literal(git_service, r"maximumRetainedBytes = ([\d_]+) \* 1024 \* 1024", limits["gitRetainedOutputBytes"] // (1024 * 1024), "Git output limit in MiB")
    require_literal(persistence, r"maxPersistedDraftTabs: Int \{ (\d+) \}", limits["draftTabCount"], "draft tab limit")
    require_literal(persistence, r"maxPersistedDraftUTF16Length: Int \{ ([\d_]+) \}", limits["draftTabUTF16Length"], "draft tab length limit")
    require_literal(persistence, r"maxPersistedDraftTotalUTF16Length: Int \{ ([\d_]+) \}", limits["draftTotalUTF16Length"], "draft total length limit")

    policy = baseline["capturePolicy"]
    if set(policy["platforms"]) != {"macos", "iphone", "ipad"}:
        fail("capture policy must cover macOS, iPhone, and iPad")
    if policy["runsPerPlatform"] != 3 or policy["timeRegressionPercent"] != 20:
        fail("capture policy drifted from the documented protocol")

    print("[performance-budget] OK")


if __name__ == "__main__":
    main()
