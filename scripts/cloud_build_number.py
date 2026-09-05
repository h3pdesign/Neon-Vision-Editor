#!/usr/bin/env python3
"""Read-only App Store Connect counter preflight. Never reserves or starts builds."""
from __future__ import annotations

import base64
import datetime as dt
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

ORIGIN = "https://api.appstoreconnect.apple.com"


def local_setting(name: str) -> str:
    """Read non-secret setup from this checkout's local Git config only."""
    try:
        result = subprocess.run(["git", "-C", str(Path(__file__).resolve().parents[1]),
                                 "config", "--local", "--get", "nve.asc." + name],
                                capture_output=True, text=True, timeout=10)
        if result.returncode not in (0, 1):
            raise ValueError("Could not read local App Store Connect configuration.")
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        raise ValueError("Could not read local App Store Connect configuration.") from None


class TeamKeyToken:
    """Generate a two-minute, GET-scoped JWT in memory for each request."""
    def __init__(self, key_id: str, issuer_id: str, key_path: str):
        if not re.fullmatch(r"[A-Z0-9]{10}", key_id or "") or not re.fullmatch(
                r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}", issuer_id or ""):
            raise ValueError("Set ASC_KEY_ID and ASC_ISSUER_ID for a team API key.")
        path = Path(key_path).expanduser()
        if not key_path or not path.is_absolute():
            raise ValueError("ASC_PRIVATE_KEY_PATH must be an absolute path outside Git.")
        try:
            path = path.resolve(strict=True)
            if any((parent / ".git").exists() for parent in path.parents):
                raise ValueError("Keep the API private key outside Git repositories and worktrees.")
            info = path.stat()
            if not stat.S_ISREG(info.st_mode) or info.st_size > 16384:
                raise ValueError("Expected a small private-key file.")
            if info.st_mode & 0o077:
                raise ValueError("Restrict the API private-key file permissions to 600 before use.")
            with path.open("rb") as source:
                pem = source.read(16385)
            if len(pem) > 16384:
                raise ValueError("Expected a small private-key file.")
        except OSError:
            raise ValueError("Could not read the configured API private-key file.") from None
        try:
            from cryptography.hazmat.primitives import serialization
            from cryptography.hazmat.primitives.asymmetric import ec
        except ImportError:
            raise ValueError("API-key signing requires cryptography; see docs/XCODE_CLOUD_RELEASE.md.") from None
        try:
            key = serialization.load_pem_private_key(pem, password=None)
        except (ValueError, TypeError):
            raise ValueError("Expected an unencrypted App Store Connect P-256 .p8 key.") from None
        if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
            raise ValueError("Expected an App Store Connect P-256 .p8 key.")
        self._key, self._key_id, self._issuer_id = key, key_id, issuer_id

    def __call__(self, url: str) -> str:
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec, utils
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com"
                or parsed.fragment or not re.fullmatch(
                    r"/v1/(?:ciProducts/[A-Za-z0-9-]+/buildRuns|ciBuildRuns/[A-Za-z0-9-]+/actions)", parsed.path)):
            raise ValueError("Refusing to sign an unexpected Cloud request.")
        now = int(time.time())
        header = {"alg": "ES256", "kid": self._key_id, "typ": "JWT"}
        scope = parsed.path + ("?" + parsed.query if parsed.query else "")
        claims = {"iss": self._issuer_id, "iat": now, "exp": now + 120,
                  "aud": "appstoreconnect-v1", "scope": ["GET " + scope]}
        def encode(value):
            return base64.urlsafe_b64encode(value).rstrip(b"=")
        message = b".".join(encode(json.dumps(value, separators=(",", ":")).encode()) for value in (header, claims))
        r, s = utils.decode_dss_signature(self._key.sign(message, ec.ECDSA(hashes.SHA256())))
        return (message + b"." + encode(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the bearer token to a redirect target.
        return None


class CloudBuildCounter:
    def __init__(self, product_id: str, token):
        if not re.fullmatch(r"[A-Za-z0-9-]+", product_id or ""):
            raise ValueError("Set ASC_CLOUD_PRODUCT_ID to the app's Xcode Cloud product ID.")
        if not callable(token) and (not isinstance(token, str) or not token or any(c.isspace() for c in token)):
            raise ValueError("A valid App Store Connect bearer token is required.")
        self.product_id = product_id
        self._token = token
        self._opener = urllib.request.build_opener(NoRedirect())

    @classmethod
    def from_environment(cls):
        product = os.environ.get("ASC_CLOUD_PRODUCT_ID")
        if product is None:
            product = local_setting("productId")
        if not product:
            raise ValueError("Set ASC_CLOUD_PRODUCT_ID or local nve.asc.productId.")
        token = os.environ.get("ASC_API_TOKEN", "")
        service = os.environ.get("ASC_TOKEN_KEYCHAIN_SERVICE", "")
        if not token and service:
            try:
                result = subprocess.run(["security", "find-generic-password", "-s", service, "-w"],
                                        capture_output=True, text=True, timeout=15, check=True)
                token = result.stdout.strip()
            except (OSError, subprocess.SubprocessError):
                raise ValueError("Could not read the configured App Store Connect token from Keychain.") from None
        if not token:
            def setting(env_name, config_name):
                return os.environ[env_name] if env_name in os.environ else local_setting(config_name)
            token = TeamKeyToken(setting("ASC_KEY_ID", "keyId"), setting("ASC_ISSUER_ID", "issuerId"),
                                 setting("ASC_PRIVATE_KEY_PATH", "privateKeyPath"))
        return cls(product, token)

    def _get(self, url: str, timeout: float, *, action_run_id: str | None = None) -> dict:
        parsed = urllib.parse.urlsplit(url)
        expected_path = f"/v1/ciProducts/{self.product_id}/buildRuns"
        if action_run_id is not None:
            if not re.fullmatch(r"[A-Za-z0-9-]+", action_run_id):
                raise ValueError("Invalid Cloud run ID.")
            expected_path = f"/v1/ciBuildRuns/{action_run_id}/actions"
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com" or parsed.path != expected_path or parsed.fragment:
            raise ValueError("Refusing an unexpected App Store Connect pagination URL.")
        token = self._token(url) if callable(self._token) else self._token
        request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token,
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

    def _only_lingering_distribution(self, run_id: str, deadline: float) -> bool:
        """Do not mistake a historical TestFlight post-action for active compilation.

        Names alone are not enough: require successful completed archives, all
        other actions successful, and distribution starting after all archives.
        Unknown/renamed actions fail closed. The caller also requires a newer
        completed run; never exempt the latest allocated run.
        """
        if not re.fullmatch(r"[A-Za-z0-9-]+", run_id):
            return False
        url = ORIGIN + f"/v1/ciBuildRuns/{run_id}/actions?limit=200"
        seen_urls, seen_ids, archives, distribution = set(), set(), [], []

        def timestamp(value):
            if not isinstance(value, str):
                raise ValueError("Missing action timestamp")
            result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
            if result.tzinfo is None:
                raise ValueError("Missing action timezone")
            return result

        while url:
            remaining = deadline - time.monotonic()
            if url in seen_urls or len(seen_urls) >= 100 or remaining <= 0:
                return False
            seen_urls.add(url)
            data = self._get(url, min(20, remaining), action_run_id=run_id)
            if not isinstance(data.get("data"), list) or not isinstance(data.get("links"), dict):
                return False
            for item in data["data"]:
                if (not isinstance(item, dict) or item.get("type") != "ciBuildActions"
                        or not isinstance(item.get("id"), str) or not item["id"] or item["id"] in seen_ids):
                    return False
                seen_ids.add(item["id"])
                attrs = item.get("attributes")
                if not isinstance(attrs, dict):
                    return False
                try:
                    if attrs.get("executionProgress") == "COMPLETE":
                        if attrs.get("completionStatus") != "SUCCEEDED":
                            return False
                        finished = timestamp(attrs.get("finishedDate"))
                        if attrs.get("actionType") == "ARCHIVE":
                            # Apple also reports notarization as ARCHIVE. It may
                            # run alongside TestFlight distribution, after the
                            # actual archives; require success but not ordering.
                            if attrs.get("name") == "Notarize - macOS":
                                continue
                            if not isinstance(attrs.get("name"), str) or not re.fullmatch(
                                    r"Archive - (?:macOS|iOS|visionOS|tvOS)", attrs["name"]):
                                return False
                            archives.append(finished)
                    elif (attrs.get("executionProgress") == "RUNNING" and attrs.get("actionType") == "TEST"
                          and attrs.get("completionStatus") is None and attrs.get("finishedDate") is None
                          and isinstance(attrs.get("name"), str) and re.fullmatch(
                              r"TestFlight (?:Internal|External) Testing - (?:macOS|iOS|visionOS|tvOS)", attrs["name"])):
                        distribution.append(timestamp(attrs.get("startedDate")))
                    else:
                        return False
                except (ValueError, OverflowError):
                    return False
            url = data["links"].get("next")
            if url is not None and (not isinstance(url, str) or not url):
                return False
        return bool(archives and distribution and min(distribution) >= max(archives))

    def snapshot(self) -> dict:
        url = ORIGIN + f"/v1/ciProducts/{self.product_id}/buildRuns?limit=200&fields%5BciBuildRuns%5D=number,executionProgress"
        deadline = time.monotonic() + 90
        seen_urls, seen_ids = set(), set()
        maximum = 0
        completed_maximum = 0
        unfinished = []
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
                progress = attrs.get("executionProgress")
                if progress not in ("COMPLETE", "RUNNING"):
                    raise ValueError("Cloud has an active, queued or unknown-state build. Wait for it to finish before allocating a release number.")
                if progress == "RUNNING":
                    unfinished.append((item["id"], attrs["number"]))
                else:
                    completed_maximum = max(completed_maximum, attrs["number"])
                maximum = max(maximum, attrs["number"])
            url = data["links"].get("next")
            if url is not None and (not isinstance(url, str) or not url):
                raise ValueError("Malformed Cloud pagination link.")
        if not maximum:
            raise ValueError("No Cloud build history exists; configure the initial counter explicitly.")
        for run_id, number in unfinished:
            if number >= completed_maximum or not self._only_lingering_distribution(run_id, deadline):
                raise ValueError(f"Cloud has an active, queued or unknown-state build ({number}). Wait for it to finish before allocating a release number.")
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
