#!/usr/bin/env python3
"""Wait for required PR checks on an immutable head; never bypass merge policy."""
import argparse
import json
import re
import subprocess
import time

# These required contexts must register even if unrelated checks appear first.
EXPECTED = {"build", "macOS Sequoia syntax regressions", "preflight"}


def checks_ready(checks):
    if not isinstance(checks, list):
        raise ValueError("Malformed required-check response.")
    names = set()
    pending = False
    for check in checks:
        if not isinstance(check, dict) or not isinstance(check.get("name"), str):
            raise ValueError("Malformed required check.")
        name = check["name"]
        if name in names:
            raise ValueError(f"Ambiguous duplicate required check: {name}.")
        names.add(name)
        bucket = check.get("bucket")
        if bucket == "pending":
            pending = True
        elif bucket not in {"pass", "skipping"}:
            raise ValueError(f"Required check did not pass: {name} ({bucket}).")
    return EXPECTED <= names and not pending


def wait(pr, repo, head, timeout=1200, interval=10):
    deadline = time.monotonic() + timeout

    def query(arguments, accepted=(0,)):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("Timed out waiting for required checks; PR left open.")
        result = subprocess.run(["gh", *arguments], capture_output=True, text=True,
                                timeout=min(30, remaining))
        if result.returncode not in accepted:
            # Do not echo API output or credentials into CI logs.
            raise ValueError("GitHub check query failed; PR left open.")
        if (result.returncode == 1 and not result.stdout.strip()
                and re.search(r"no (?:required )?checks reported", result.stderr.lower())):
            return []
        return json.loads(result.stdout)

    while time.monotonic() < deadline:
        info = query(["pr", "view", str(pr), "--repo", repo,
                      "--json", "headRefOid,state"])
        if not isinstance(info, dict) or info.get("headRefOid") != head or info.get("state") != "OPEN":
            raise ValueError("PR head or state changed during validation; PR left untouched.")
        # gh uses 8 for pending and 1 for failed checks. Empty/no-registration
        # responses are errors, not evidence that every required check passed.
        checks = query(["pr", "checks", str(pr), "--repo", repo, "--required",
                        "--json", "name,bucket"], accepted=(0, 1, 8))
        if checks_ready(checks):
            print(f"Required checks passed for PR {pr} at {head}.", flush=True)
            return
        print(f"PR {pr}: waiting for all required checks on {head[:12]}.", flush=True)
        time.sleep(min(interval, max(0, deadline - time.monotonic())))
    raise TimeoutError("Timed out waiting for required checks; PR left open.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pr", type=int)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()
    if (args.pr < 1 or args.timeout < 1 or not re.fullmatch(r"[0-9a-f]{40}", args.head)
            or not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo)):
        parser.error("A PR number, repository, immutable SHA and positive timeout are required.")
    try:
        wait(args.pr, args.repo, args.head, args.timeout)
    except (ValueError, TimeoutError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error)) from None


if __name__ == "__main__":
    main()
