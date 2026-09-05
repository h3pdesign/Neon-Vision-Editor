#!/usr/bin/env python3
"""Read-only App Store Connect counter preflight. Never reserves or starts builds."""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

ORIGIN = "https://api.appstoreconnect.apple.com"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the bearer token to a redirect target.
        return None


class CloudBuildCounter:
    def __init__(self, product_id: str, token: str):
        if not re.fullmatch(r"[A-Za-z0-9-]+", product_id or ""):
            raise ValueError("Set ASC_CLOUD_PRODUCT_ID to the app's Xcode Cloud product ID.")
        if not token or any(c.isspace() for c in token):
            raise ValueError("A valid App Store Connect bearer token is required.")
        self.product_id = product_id
        self._token = token
        self._opener = urllib.request.build_opener(NoRedirect())

    @classmethod
    def from_environment(cls):
        product = os.environ.get("ASC_CLOUD_PRODUCT_ID", "")
        token = os.environ.get("ASC_API_TOKEN", "")
        service = os.environ.get("ASC_TOKEN_KEYCHAIN_SERVICE", "")
        if not token and service:
            try:
                result = subprocess.run(["security", "find-generic-password", "-s", service, "-w"],
                                        capture_output=True, text=True, timeout=15, check=True)
                token = result.stdout.strip()
            except (OSError, subprocess.SubprocessError):
                raise ValueError("Could not read the configured App Store Connect token from Keychain.") from None
        if not product or not token:
            raise ValueError("Cloud preflight requires ASC_CLOUD_PRODUCT_ID and an App Store Connect JWT via ASC_API_TOKEN or ASC_TOKEN_KEYCHAIN_SERVICE. Do not put credentials in Git.")
        return cls(product, token)

    def _get(self, url: str, timeout: float) -> dict:
        parsed = urllib.parse.urlsplit(url)
        expected_path = f"/v1/ciProducts/{self.product_id}/buildRuns"
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com" or parsed.path != expected_path or parsed.fragment:
            raise ValueError("Refusing an unexpected App Store Connect pagination URL.")
        request = urllib.request.Request(url, headers={"Authorization": "Bearer " + self._token,
                                                      "Accept": "application/json"})
        try:
            with self._opener.open(request, timeout=timeout) as response:
                payload = response.read(2_000_001)
            if len(payload) > 2_000_000:
                raise ValueError("App Store Connect response exceeded the safety limit.")
            data = json.loads(payload)
            if not isinstance(data, dict):
                raise ValueError("Malformed App Store Connect response.")
            return data
        except urllib.error.HTTPError as exc:
            # Do not include request headers, token, URL or server response body.
            raise ValueError(f"App Store Connect returned HTTP {exc.code}; verify token permissions/expiry or retry later.") from None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError):
            raise ValueError("App Store Connect could not be read safely; no build number was allocated.") from None

    def snapshot(self) -> dict:
        url = ORIGIN + f"/v1/ciProducts/{self.product_id}/buildRuns?limit=200&fields%5BciBuildRuns%5D=number,executionProgress"
        deadline = time.monotonic() + 90
        seen_urls, seen_ids = set(), set()
        maximum = 0
        while url:
            if url in seen_urls or len(seen_urls) >= 100 or time.monotonic() >= deadline:
                raise ValueError("Cloud build history is incomplete or changing; retry preflight.")
            seen_urls.add(url)
            data = self._get(url, min(20, max(1, deadline - time.monotonic())))
            if not isinstance(data.get("data"), list) or not isinstance(data.get("links"), dict):
                raise ValueError("Malformed Cloud build history; refusing a guessed counter.")
            for item in data["data"]:
                if not isinstance(item, dict) or item.get("type") != "ciBuildRuns" or not isinstance(item.get("id"), str):
                    raise ValueError("Malformed Cloud build record.")
                if item["id"] in seen_ids:
                    raise ValueError("Cloud history changed during pagination; retry preflight.")
                seen_ids.add(item["id"])
                attrs = item.get("attributes")
                if not isinstance(attrs, dict) or type(attrs.get("number")) is not int or attrs["number"] < 1:
                    raise ValueError("Cloud build number is missing or invalid.")
                if attrs.get("executionProgress") != "COMPLETE":
                    raise ValueError("Cloud has an active, queued or unknown-state build. Wait for it to finish before allocating a release number.")
                maximum = max(maximum, attrs["number"])
            url = data["links"].get("next")
            if url is not None and (not isinstance(url, str) or not url):
                raise ValueError("Malformed Cloud pagination link.")
        if not maximum:
            raise ValueError("No Cloud build history exists; configure the initial counter explicitly.")
        return {"product_id": self.product_id, "max_number": maximum}

    def assert_unchanged(self, expected: dict, candidate: int) -> None:
        current = self.snapshot()
        if current != expected or candidate <= current["max_number"]:
            raise ValueError("Cloud counter changed or consumed the candidate. Preserve the release worktree and reconcile the allocation; nothing will be pushed.")


if __name__ == "__main__":
    try:
        print(json.dumps(CloudBuildCounter.from_environment().snapshot()))
    except ValueError as exc:
        raise SystemExit(str(exc))
