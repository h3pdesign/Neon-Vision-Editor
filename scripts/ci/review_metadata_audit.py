#!/usr/bin/env python3
"""Audit App Store privacy/review metadata against security-sensitive code paths."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PRIVACY_MANIFEST = ROOT / "Neon Vision Editor" / "Resources" / "PrivacyInfo.xcprivacy"
PRIVACY_DOC = ROOT / "PRIVACY.md"
SECURITY_DOC = ROOT / "SECURITY.md"
REVIEW_NOTES = ROOT / "docs" / "AppStoreReviewNotes.md"
READINESS = ROOT / "release" / "App-Store-Readiness.md"
AI_CLIENT = ROOT / "Neon Vision Editor" / "AI" / "AIClient.swift"
SETTINGS_VIEW = ROOT / "Neon Vision Editor" / "UI" / "NeonSettingsView.swift"


def fail(message: str) -> None:
    print(f"[review-metadata-audit] {message}", file=sys.stderr)
    raise SystemExit(1)


def require_text(path: Path, fragments: dict[str, str]) -> None:
    text = path.read_text(encoding="utf-8")
    for description, fragment in fragments.items():
        if fragment not in text:
            fail(f"{path.relative_to(ROOT)} missing {description}: {fragment}")


def main() -> None:
    manifest = plistlib.loads(PRIVACY_MANIFEST.read_bytes())
    if manifest.get("NSPrivacyTracking") is not False:
        fail("PrivacyInfo.xcprivacy must declare NSPrivacyTracking=false")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        fail("PrivacyInfo.xcprivacy must not declare tracking domains")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        fail("PrivacyInfo.xcprivacy must not declare collected data while policy says no collection")

    accessed = manifest.get("NSPrivacyAccessedAPITypes", [])
    if not any(
        item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"
        and "CA92.1" in item.get("NSPrivacyAccessedAPITypeReasons", [])
        for item in accessed
    ):
        fail("PrivacyInfo.xcprivacy must retain the UserDefaults required-reason API declaration")

    require_text(
        PRIVACY_DOC,
        {
            "no telemetry statement": "No telemetry is sent by default.",
            "Keychain token storage": "API tokens for optional AI providers are stored in Apple Keychain.",
            "HTTPS provider transport": "Requests are sent over HTTPS to the selected provider endpoint.",
            "AI context disclosure": "External AI completion requests send only the active completion context",
            "custom provider HTTPS requirement": "Custom OpenAI-compatible providers must use HTTPS endpoints.",
        },
    )
    require_text(
        SECURITY_DOC,
        {
            "Keychain principle": "API tokens must remain in Keychain",
            "HTTPS principle": "HTTPS for external requests",
            "no telemetry principle": "No telemetry",
        },
    )
    require_text(
        REVIEW_NOTES,
        {
            "AI optionality": "AI completion is optional",
            "Keychain review note": "bring-your-own API keys stored in Keychain",
            "AI data disclosure": "AI Data Disclosure",
            "custom provider HTTPS note": "Custom OpenAI-compatible providers require HTTPS endpoints.",
            "nve helper privacy note": "does not collect data",
        },
    )
    require_text(
        READINESS,
        {
            "AI questionnaire warning": "AI prompts/source code sent to providers",
            "third-party AI pitfall": "Missing disclosure for data sent to third-party AI endpoints.",
        },
    )
    require_text(
        AI_CLIENT,
        {
            "custom provider HTTPS validator": "isSecureOpenAICompatibleBaseURL",
            "HTTPS scheme check": 'scheme == "https"',
            "loopback HTTP exception": 'scheme == "http", let host = url.host?.lowercased()',
            "loopback host validator": "isLoopbackOpenAICompatibleHost",
        },
    )
    require_text(
        SETTINGS_VIEW,
        {
            "in-app AI disclosure": "AI-assisted code completion is an optional feature.",
            "minimal context disclosure": "minimal contextual text necessary",
            "HTTPS disclosure": "encrypted HTTPS connections",
        },
    )

    print("[review-metadata-audit] OK")


if __name__ == "__main__":
    main()
