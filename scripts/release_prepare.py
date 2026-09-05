#!/usr/bin/env python3
"""Isolated, resumable release preparation. Dry runs never contact remote services."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from cloud_build_number import CloudBuildCounter

ROOT = Path(__file__).resolve().parents[1]
PROJECT = "Neon Vision Editor.xcodeproj/project.pbxproj"
STATE = "release/prepared-release.json"


def run(*args: str, cwd: Path = ROOT, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def git(*args: str, cwd: Path = ROOT) -> str:
    return run("git", *args, cwd=cwd, capture=True)


def project_build(text: str) -> int:
    values = set(re.findall(r"CURRENT_PROJECT_VERSION = ([0-9]+);", text))
    if len(values) != 1:
        raise ValueError("Project build numbers must be present and consistent before preparation.")
    return int(values.pop())


def prepare_files(root: Path, state: dict) -> None:
    """Persist allocation before edits; retries always reuse this build and date."""
    validate_state(state)
    path = root / STATE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2) + "\n")
    run("python3", "scripts/prepare_release_docs.py", state["tag"],
        "--notes-only", "--date", state["date"], cwd=root)
    run("bash", "scripts/ci/release_notes_quality_gate.sh", state["tag"],
        "--preflight", cwd=root)
    project = root / PROJECT
    text = project.read_text()
    if not re.search(r"MARKETING_VERSION = [^;]+;", text):
        raise ValueError("Project marketing versions are missing.")
    project_build(text)
    text = re.sub(r"MARKETING_VERSION = [^;]+;",
                  f'MARKETING_VERSION = {state["tag"][1:]};', text)
    text = re.sub(r"CURRENT_PROJECT_VERSION = [0-9]+;",
                  f'CURRENT_PROJECT_VERSION = {state["build"]};', text)
    project.write_text(text)
    run("python3", "scripts/prepare_release_docs.py", state["tag"],
        "--build", str(state["build"]), cwd=root)
    if state["tag"].endswith(".0"):
        run("python3", "scripts/update_release_history_svg.py", state["tag"], cwd=root)
    run("python3", "scripts/prepare_release_docs.py", state["tag"], "--check", cwd=root)
    run("bash", "scripts/ci/validate_release_metadata.sh", state["tag"], cwd=root)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", nargs="?")
    parser.add_argument("--next", action="store_true")
    bump = parser.add_mutually_exclusive_group()
    bump.add_argument("--minor", action="store_true")
    bump.add_argument("--major", action="store_true")
    parser.add_argument("--date", type=dt.date.fromisoformat)
    parser.add_argument("--push", action="store_true", help="Push prepared branch and open protected main PR")
    parser.add_argument("--resume", action="store_true", help="Resume an interrupted allocation; regenerate only release-owned metadata")
    parser.add_argument("--dry-run", action="store_true", help="Offline disposable rehearsal, no commits or remote writes")
    parser.add_argument("--full-gate", action="store_true", help="Also run the Xcode release gate (requires developer-service access)")
    args = parser.parse_args()
    if bool(args.tag) == args.next:
        parser.error("Specify a tag or --next, not both.")
    if (args.minor or args.major) and not args.next:
        parser.error("--minor/--major require --next.")
    if args.push and args.dry_run:
        parser.error("--push and --dry-run cannot be combined.")
    return args


def main() -> None:
    args = parse_args()
    cloud = None
    cloud_snapshot = None
    if not args.dry_run:
        os.environ.pop("NVE_RELEASE_OFFLINE", None)
        if git("status", "--porcelain"):
            raise ValueError("Commit changes to develop before release preparation; nothing was changed.")
        cloud = CloudBuildCounter.from_environment()
        cloud_snapshot = cloud.snapshot()
        run("git", "fetch", "--tags", "origin", "develop")
        if git("config", "--get", "gpg.format") != "ssh" or not git("config", "--get", "user.signingkey"):
            raise ValueError("Release commits require a configured SSH signing key.")
    tag = args.tag
    if args.next:
        tag = run("python3", "scripts/next_release_version.py",
                  "--major" if args.major else "--minor" if args.minor else "--patch", capture=True)
    tag = tag if tag.startswith("v") else "v" + tag
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Expected a stable semantic version, for example v1.6.2.")
    if git("tag", "--list", tag):
        raise ValueError(f"{tag} already exists; preparation never retags a release.")
    source = git("rev-parse", "HEAD" if args.dry_run else "origin/develop")
    branch = "release/" + tag[1:]
    if args.dry_run:
        os.environ["NVE_RELEASE_OFFLINE"] = "1"
        print(f"DRY RUN: {tag}, source {source}; includes local tracked edits. Tags are local-cache only.", flush=True)
        with tempfile.TemporaryDirectory(prefix="nve-release-dry-") as temp:
            root = Path(temp)
            # Copy tracked inputs only: no .git, credentials, build caches or other worktrees.
            # Include newly authored release tooling while it is still under review.
            paths = git("ls-files", "-z").split("\0")
            paths += git("ls-files", "--others", "--exclude-standard", "-z").split("\0")
            for name in dict.fromkeys(paths):
                if not name:
                    continue
                path = ROOT / name
                if path.is_symlink() and (path.readlink().is_absolute() or not path.resolve().is_relative_to(ROOT)):
                    raise ValueError(f"Dry run refuses external symlink input: {name}")
                if path.is_file() or path.is_symlink():
                    dest = root / name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, dest, follow_symlinks=False)
            state = new_state(root, tag, source, args.date)
            prepare_files(root, state)
            first = snapshot(root)
            prepare_files(root, state)
            if snapshot(root) != first:
                raise ValueError("Preparation is not idempotent.")
            # Also exercise the post-publication transition, entirely offline.
            run("python3", "scripts/prepare_release_docs.py", tag, "--published", cwd=root)
            run("python3", "scripts/prepare_release_docs.py", tag, "--check", cwd=root)
            run("bash", "scripts/ci/validate_release_metadata.sh", tag, cwd=root)
            if args.full_gate:
                run("bash", "scripts/ci/release_gate.sh", tag, cwd=root)
            print(f"PASS: prepared and published documentation, metadata, repeatability; candidate build {state['build']}.")
            print("No source changes, commits, branches, tags, pushes, workflow dispatches or publication.")
            if not args.full_gate:
                print("Xcode builds, signing, notarization and public assets were NOT verified. Use --full-gate for local release validation.")
        return

    worktrees: list[Path] = []
    for block in git("worktree", "list", "--porcelain").split("\n\n"):
        fields = dict(line.split(" ", 1) for line in block.splitlines() if " " in line)
        if fields.get("branch") == "refs/heads/" + branch:
            worktrees.append(Path(fields["worktree"]))
    if worktrees:
        root = worktrees[0]
        state = json.loads((root / STATE).read_text())
        validate_state(state)
        if state["tag"] != tag or state["source"] != source:
            raise ValueError("Develop moved since allocation. Preserve the existing worktree and review its source before retrying.")
        if args.date and str(args.date) != state["date"]:
            raise ValueError("Retry date differs from the allocated release date.")
        run("git", "merge-base", "--is-ancestor", source, "HEAD", cwd=root)
        assert_release_only_changes(root, source)
        if git("status", "--porcelain", cwd=root) and not args.resume:
            raise ValueError(f"Preserved incomplete/edited preparation at {root}; review and commit it before retrying.")
        if args.resume:
            assert_release_only_changes(root)
        if state.get("cloud") != cloud_snapshot:
            raise ValueError("Cloud allocation is missing or stale. Review the preserved release worktree before retrying.")
        cloud.assert_unchanged(state["cloud"], state["build"])
        prepare_files(root, state)
    else:
        if git("branch", "--list", branch):
            raise ValueError(f"{branch} exists without its worktree. Reattach it explicitly before retrying.")
        if git("ls-remote", "--heads", "origin", "refs/heads/" + branch):
            raise ValueError(f"Remote {branch} already exists. Fetch and reattach it explicitly; it will not be overwritten.")
        if git("rev-parse", "HEAD") != source or git("branch", "--show-current") != "develop":
            raise ValueError("Start from clean develop aligned with origin/develop; no implicit rebase or stash.")
        root = ROOT.parent / (ROOT.name + "-release-" + tag[1:])
        # Validate allocation inputs before creating a branch. A bad baseline
        # must not leave an orphan worktree with no manifest to resume.
        state = new_state(ROOT, tag, source, args.date)
        state["build"] = max(state["build"], cloud_snapshot["max_number"] + 1)
        state["cloud"] = cloud_snapshot
        validate_state(state)
        run("git", "worktree", "add", "-b", branch, str(root), source)
        prepare_files(root, state)
    if args.full_gate:
        run("bash", "scripts/ci/release_gate.sh", tag, cwd=root)
    cloud.assert_unchanged(state["cloud"], state["build"])
    assert_release_only_changes(root, source)
    if git("status", "--porcelain", cwd=root):
        run("git", "add", "--all", cwd=root)
        env = dict(os.environ, NVE_SKIP_BUILD_NUMBER_BUMP="1")
        subprocess.run(["git", "commit", "-S", "-m", f"chore(release): prepare {tag}"], cwd=root, env=env, check=True)
    run("git", "verify-commit", "HEAD", cwd=root)
    print(f"Prepared {tag} in {root}; source checkout unchanged.")
    if args.push:
        cloud.assert_unchanged(state["cloud"], state["build"])
        run("git", "push", "-u", "origin", branch, cwd=root)
        pr = run("gh", "pr", "list", "--state", "open", "--base", "main", "--head", branch,
                 "--json", "number", "--jq", ".[0].number // empty", cwd=root, capture=True)
        if not pr:
            run("gh", "pr", "create", "--base", "main", "--head", branch,
                "--title", f"chore(release): prepare {tag}", "--body",
                f"Prepared from develop {source}. Build {state['build']}. Publication remains gated by signed archive and notarization checks.", cwd=root)
        run("gh", "pr", "merge", branch, "--auto", "--merge", "--delete-branch", cwd=root)


def new_state(root: Path, tag: str, source: str, date: dt.date | None) -> dict:
    prior = root / STATE
    if prior.exists():
        existing = json.loads(prior.read_text())
        validate_state(existing)
        if existing["tag"] == tag:
            return existing
        if existing["status"] != "published":
            raise ValueError("A different release is still prepared but unpublished.")
    text = (root / PROJECT).read_text()
    published = re.search(r"^> Latest release: \*\*(v\d+\.\d+\.\d+)\*\*", (root / "README.md").read_text(), re.M)
    if not published:
        raise ValueError("Cannot determine the last published release from README.")
    if tuple(map(int, tag[1:].split("."))) <= tuple(map(int, published[1][1:].split("."))):
        raise ValueError("The next release must be newer than the published version.")
    published_build = project_build(git("show", f"{published[1]}:{PROJECT}"))
    return dict(tag=tag, source=source, date=str(date or dt.date.today()),
                build=max(project_build(text), published_build) + 1, published_tag=published[1],
                published_build=published_build, status="prepared")


def validate_state(state: dict) -> None:
    try:
        if state["status"] not in ("prepared", "published") or not re.fullmatch(r"[a-f0-9]{40}", state["source"]):
            raise ValueError("Invalid status or source SHA")
        for key in ("tag", "published_tag"):
            if not re.fullmatch(r"v\d+\.\d+\.\d+", state[key]):
                raise ValueError("Invalid version")
        for key in ("build", "published_build"):
            if type(state[key]) is not int or state[key] <= 0:
                raise ValueError("Invalid build")
        if state["build"] <= state["published_build"] or tuple(map(int, state["tag"][1:].split("."))) <= tuple(map(int, state["published_tag"][1:].split("."))):
            raise ValueError("Candidate must be newer than the published release")
        dt.date.fromisoformat(state["date"])
        if "cloud" in state:
            cloud = state["cloud"]
            if not isinstance(cloud, dict) or not isinstance(cloud.get("product_id"), str) or not re.fullmatch(r"[A-Za-z0-9-]+", cloud["product_id"]):
                raise ValueError("Invalid Cloud product")
            if type(cloud.get("max_number")) is not int or cloud["max_number"] < 1 or state["build"] <= cloud["max_number"]:
                raise ValueError("Invalid Cloud counter")
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("Invalid release allocation; preserve and review the manifest before retrying.") from exc


def assert_release_only_changes(root: Path, base: str = "HEAD") -> None:
    allowed = {STATE, PROJECT, "CHANGELOG.md", "README.md", "ARCHITECTURE.md",
               "Neon Vision Editor/UI/PanelsAndHelpers.swift", "site/index.html", "site/changelog.html",
               *(f"site/{locale}/index.html" for locale in ("de", "da", "fr", "es", "ja", "zh-Hans")),
               "docs/images/neon-vision-release-history-0.1-to-0.5.svg",
               "docs/images/neon-vision-release-history-0.1-to-0.5-light.svg"}
    changed = set(git("diff", "--name-only", base, "-z", cwd=root).split("\0"))
    changed.update(git("ls-files", "--others", "--exclude-standard", "-z", cwd=root).split("\0"))
    unexpected = changed - allowed - {""}
    if unexpected:
        raise ValueError(f"Unrelated edits in release worktree: {sorted(unexpected)}")


def snapshot(root: Path) -> dict:
    result = {}
    for path in root.rglob("*"):
        if path.is_file() and "__pycache__" not in path.parts:
            with path.open("rb") as stream:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            result[str(path.relative_to(root))] = digest.hexdigest()
    return result


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"Release preparation stopped: {exc}")
