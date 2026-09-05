#!/usr/bin/env python3
"""Conservative local branch cleanup. Remote deletion belongs to GitHub PR merges."""
import argparse
from datetime import datetime, timezone
import fcntl
import fnmatch
import json
from pathlib import Path
import subprocess
import sys

PRESERVE = ("main", "develop", "archive/*", "release/*", "automation/*",
            "codex/backup-*", "codex/macos-27-agentic-editor")


def run(*args, cwd):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True,
                          check=True, timeout=120).stdout.strip()


def skip_reason(name, upstream, in_use, open_pr_refs, remote_heads, merged):
    if any(fnmatch.fnmatchcase(name, pattern) for pattern in PRESERVE):
        return "preserved"
    if name in in_use:
        return "checked out in a worktree"
    if not upstream.startswith("refs/remotes/origin/"):
        return "no origin upstream; manual review"
    remote_name = upstream.removeprefix("refs/remotes/origin/")
    if name in open_pr_refs or remote_name in open_pr_refs:
        return "referenced by an open PR"
    if remote_name in remote_heads:
        return "remote branch still exists"
    if not merged:
        return "tip not reachable from origin/main or origin/develop; manual review"
    return None


def apply_enabled(apply, not_before, now):
    if not_before is not None and not_before.tzinfo is None:
        raise ValueError("--not-before must include a timezone")
    return apply and (not_before is None or now >= not_before)


def cleanup(args):
    repo = Path(args.repo).resolve()
    git = lambda *a: run("git", *a, cwd=repo)
    if git("rev-parse", "--show-toplevel") != str(repo):
        raise ValueError("--repo must be the repository root")
    expected = args.github_repo
    if git("remote", "get-url", "origin") not in (
            f"https://github.com/{expected}.git", f"https://github.com/{expected}",
            f"git@github.com:{expected}.git"):
        raise ValueError("origin does not match --github-repo")
    common = Path(git("rev-parse", "--git-common-dir"))
    if not common.is_absolute():
        common = repo / common
    with (common / "branch-cleanup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if git("status", "--porcelain", "--untracked-files=all"):
            raise ValueError("current worktree is dirty; no cleanup performed")
        # Abort on network/authentication failure. Never use stale merge/PR data.
        git("fetch", "--prune", "origin")
        bases = [git("rev-parse", "--verify", f"refs/remotes/origin/{b}^{{commit}}")
                 for b in ("main", "develop")]
        pages = json.loads(run("gh", "api", "--paginate", "--slurp",
                               f"repos/{expected}/pulls?state=open&per_page=100", cwd=repo))
        prs = [pr for page in pages for pr in page]
        open_refs = {pr[side]["ref"] for pr in prs for side in ("head", "base")}
        live_heads = {line.split("\t", 1)[1].removeprefix("refs/heads/")
                      for line in git("ls-remote", "--heads", "origin").splitlines()}
        in_use = {line.removeprefix("branch refs/heads/")
                  for line in git("worktree", "list", "--porcelain").splitlines()
                  if line.startswith("branch refs/heads/")}
        branches = git("for-each-ref", "--format=%(refname:short)%09%(objectname)%09%(upstream)", "refs/heads")
        apply = apply_enabled(args.apply, args.not_before, datetime.now(timezone.utc))
        for line in branches.splitlines():
            name, tip, upstream = (line + "\t").split("\t")[:3]
            merged = False
            for base in bases:
                result = subprocess.run(["git", "merge-base", "--is-ancestor", tip, base], cwd=repo)
                if result.returncode not in (0, 1):
                    raise ValueError("ancestry check failed")
                merged |= result.returncode == 0
            reason = skip_reason(name, upstream, in_use, open_refs, live_heads, merged)
            event = {"time": datetime.now(timezone.utc).isoformat(), "branch": name,
                     "tip": tip, "action": "skip" if reason else "candidate", "reason": reason}
            if reason is None and apply:
                # Recheck local ownership and tip immediately before deletion.
                current_worktrees = git("worktree", "list", "--porcelain").splitlines()
                if git("rev-parse", f"refs/heads/{name}") != tip or f"branch refs/heads/{name}" in current_worktrees:
                    event.update(action="skip", reason="branch changed during cleanup")
                else:
                    # Keep Git's own final merged/in-use checks. Never force-delete.
                    try:
                        git("branch", "-d", "--", name)
                        event["action"] = "deleted"
                    except subprocess.CalledProcessError:
                        event.update(action="skip", reason="git branch -d refused; manual review")
            record = json.dumps(event, sort_keys=True)
            print(record)
            with (common / "branch-cleanup.jsonl").open("a") as audit:
                audit.write(record + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--github-repo", required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Default; log candidates without deleting")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--not-before", type=datetime.fromisoformat,
                        help="With --apply, remain report-only until this timezone-aware ISO timestamp")
    args = parser.parse_args()
    try:
        apply_enabled(args.apply, args.not_before, datetime.now(timezone.utc))
        cleanup(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Cleanup stopped safely: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
